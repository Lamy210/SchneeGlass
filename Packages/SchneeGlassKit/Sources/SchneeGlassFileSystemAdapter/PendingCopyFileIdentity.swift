import Darwin
import Foundation

struct PreparedPendingCopyStaging: Hashable, Sendable {
    let size: Int64
    let resourceIdentifier: String?
}

/// Persistent ownership proof used only for app-created Pending Copy staging files.
///
/// Filesystem inode metadata can be recycled quickly on APFS, so it is not sufficient as a
/// persistent recovery authority. SchneeGlass writes a random nonce into an app-specific xattr on
/// the staging file and persists the same token in `PendingCopyRecord`. Recovery mutation is
/// allowed only when the xattr is still present and matches exactly.
enum PendingCopyFileIdentity {
    private static let schema = "xattr-v1"
    private static let attributeName = "com.schneeglass.pending-copy-proof"

    static func createToken(
        at url: URL,
        fileManager: FileManager
    ) throws -> String? {
        _ = fileManager
        let candidate = url.standardizedFileURL
        guard candidate.isFileURL else {
            return nil
        }

        return candidate.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return nil
            }

            let descriptor = open(path, O_RDWR | O_CLOEXEC | O_NOFOLLOW)
            guard descriptor >= 0 else {
                return nil
            }
            defer { close(descriptor) }

            return createToken(onFileDescriptor: descriptor)
        }
    }

    static func createToken(onFileDescriptor descriptor: Int32) -> String? {
        let token = "\(schema):\(UUID().uuidString.lowercased())"
        let data = Data(token.utf8)

        let result = attributeName.withCString { name in
            data.withUnsafeBytes { bytes in
                fsetxattr(
                    descriptor,
                    name,
                    bytes.baseAddress,
                    bytes.count,
                    0,
                    XATTR_CREATE
                )
            }
        }
        guard result == 0 else {
            return nil
        }
        return token
    }

    /// Finalizes the exact app-created staging inode while its `O_EXCL` descriptor is still open.
    ///
    /// The path is checked before and after proof creation. If another process unlinks/recreates the
    /// staging pathname, the proof can only be written to the pinned original inode and this method
    /// fails closed instead of claiming ownership of the replacement.
    static func prepareAppOwnedStaging(
        onFileDescriptor descriptor: Int32,
        pathURL: URL
    ) -> PreparedPendingCopyStaging? {
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              (metadata.st_mode & S_IFMT) == S_IFREG,
              descriptorMatchesPath(descriptor, pathURL: pathURL),
              removeInheritedTokenFromAppOwnedStaging(onFileDescriptor: descriptor)
        else {
            return nil
        }

        let resourceIdentifier = createToken(onFileDescriptor: descriptor)

        guard descriptorMatchesPath(descriptor, pathURL: pathURL),
              fstat(descriptor, &metadata) == 0,
              (metadata.st_mode & S_IFMT) == S_IFREG
        else {
            return nil
        }

        return PreparedPendingCopyStaging(
            size: Int64(metadata.st_size),
            resourceIdentifier: resourceIdentifier
        )
    }

    /// Descriptor-relative variant used by the production pinned-destination copy path. It never
    /// re-resolves the destination directory pathname while minting recovery authority.
    static func prepareAppOwnedStaging(
        onFileDescriptor descriptor: Int32,
        directoryDescriptor: Int32,
        filename: String
    ) -> PreparedPendingCopyStaging? {
        var metadata = stat()
        guard isSinglePathComponent(filename),
              fstat(descriptor, &metadata) == 0,
              (metadata.st_mode & S_IFMT) == S_IFREG,
              descriptorMatchesDirectoryEntry(
                  descriptor,
                  directoryDescriptor: directoryDescriptor,
                  filename: filename
              ),
              removeInheritedTokenFromAppOwnedStaging(onFileDescriptor: descriptor)
        else {
            return nil
        }

        let resourceIdentifier = createToken(onFileDescriptor: descriptor)

        guard descriptorMatchesDirectoryEntry(
                  descriptor,
                  directoryDescriptor: directoryDescriptor,
                  filename: filename
              ),
              fstat(descriptor, &metadata) == 0,
              (metadata.st_mode & S_IFMT) == S_IFREG
        else {
            return nil
        }

        return PreparedPendingCopyStaging(
            size: Int64(metadata.st_size),
            resourceIdentifier: resourceIdentifier
        )
    }

    /// Removes only a proof inherited through `COPYFILE_ALL` from a staging inode that the app
    /// just created with `O_EXCL`. This is deliberately separate from `createToken`: an existing
    /// proof on an arbitrary path must never be reissued or overwritten.
    static func removeInheritedTokenFromAppOwnedStaging(
        onFileDescriptor descriptor: Int32
    ) -> Bool {
        let result = attributeName.withCString { name in
            fremovexattr(descriptor, name, 0)
        }
        return result == 0 || errno == ENOATTR
    }

    static func token(
        at url: URL,
        fileManager: FileManager
    ) throws -> String? {
        _ = fileManager
        let candidate = url.standardizedFileURL
        guard candidate.isFileURL else {
            return nil
        }

        return candidate.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return nil
            }

            let descriptor = open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
            guard descriptor >= 0 else {
                return nil
            }
            defer { close(descriptor) }

            return token(onFileDescriptor: descriptor)
        }
    }

    static func token(onFileDescriptor descriptor: Int32) -> String? {
        let size = attributeName.withCString { name in
            fgetxattr(descriptor, name, nil, 0, 0, 0)
        }
        guard size > 0 else {
            return nil
        }

        var bytes = [UInt8](repeating: 0, count: size)
        let readCount = attributeName.withCString { name in
            bytes.withUnsafeMutableBytes { buffer in
                fgetxattr(
                    descriptor,
                    name,
                    buffer.baseAddress,
                    buffer.count,
                    0,
                    0
                )
            }
        }
        guard readCount == size,
              let token = String(bytes: bytes, encoding: .utf8),
              isValidToken(token)
        else {
            return nil
        }
        return token
    }

    static func isValidToken(_ token: String) -> Bool {
        let prefix = "\(schema):"
        guard token.hasPrefix(prefix) else {
            return false
        }
        let value = String(token.dropFirst(prefix.count))
        return UUID(uuidString: value) != nil
    }

    static func descriptorMatchesPath(
        _ descriptor: Int32,
        pathURL: URL
    ) -> Bool {
        var descriptorStat = stat()
        guard fstat(descriptor, &descriptorStat) == 0 else {
            return false
        }

        return pathURL.standardizedFileURL.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return false
            }
            var pathStat = stat()
            guard lstat(path, &pathStat) == 0 else {
                return false
            }
            return descriptorStat.st_dev == pathStat.st_dev
                && descriptorStat.st_ino == pathStat.st_ino
        }
    }

    static func descriptorMatchesDirectoryEntry(
        _ descriptor: Int32,
        directoryDescriptor: Int32,
        filename: String
    ) -> Bool {
        guard isSinglePathComponent(filename) else {
            return false
        }

        var descriptorStat = stat()
        guard fstat(descriptor, &descriptorStat) == 0 else {
            return false
        }

        return filename.withCString { name in
            var entryStat = stat()
            guard fstatat(
                directoryDescriptor,
                name,
                &entryStat,
                AT_SYMLINK_NOFOLLOW
            ) == 0 else {
                return false
            }
            return descriptorStat.st_dev == entryStat.st_dev
                && descriptorStat.st_ino == entryStat.st_ino
        }
    }

    private static func isSinglePathComponent(_ value: String) -> Bool {
        !value.isEmpty && (value as NSString).lastPathComponent == value
    }
}

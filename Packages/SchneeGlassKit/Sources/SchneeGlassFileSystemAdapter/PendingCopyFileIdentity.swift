import Darwin
import Foundation

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
}

import Darwin
import Foundation

public enum PhysicalStateStoreError: Error, Hashable, Sendable {
    case invalidPathComponent
    case unsafeTopology
    case alreadyExists
    case ioFailure(Int32)
}

/// POSIX-backed storage for SchneeGlass-owned metadata.
///
/// The caller chooses a root directory that is considered app-owned. The root itself and every
/// descendant opened by this type must be a physical directory entry; symbolic links and other
/// non-directory topology are rejected. Files are opened with `O_NOFOLLOW` and must be regular
/// files. Atomic replacement is implemented with a same-directory temporary file and `renameat`,
/// so state writes never follow a destination symbolic link.
public struct PhysicalStateStore: Sendable {
    private struct EntryIdentity: Hashable, Sendable {
        let device: UInt64
        let inode: UInt64

        init(_ metadata: stat) {
            self.device = UInt64(metadata.st_dev)
            self.inode = UInt64(metadata.st_ino)
        }
    }

    private let rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
    }

    public func readRegularFile(
        in directoryComponents: [String] = [],
        named filename: String
    ) throws -> Data? {
        try Self.validateComponent(filename)
        guard let directoryDescriptor = try openDirectoryChain(
            components: directoryComponents,
            create: false
        ) else {
            return nil
        }
        defer { close(directoryDescriptor) }

        guard let fileDescriptor = try Self.openRegularFile(
            directoryDescriptor: directoryDescriptor,
            filename: filename
        ) else {
            return nil
        }
        defer { close(fileDescriptor) }

        return try Self.readAll(from: fileDescriptor)
    }

    public func writeAtomically(
        _ data: Data,
        in directoryComponents: [String] = [],
        named filename: String,
        replaceExisting: Bool = true
    ) throws {
        try Self.validateComponent(filename)
        guard let directoryDescriptor = try openDirectoryChain(
            components: directoryComponents,
            create: true
        ) else {
            throw PhysicalStateStoreError.ioFailure(ENOENT)
        }
        defer { close(directoryDescriptor) }

        let originalIdentity = try Self.regularFileIdentityIfPresent(
            directoryDescriptor: directoryDescriptor,
            filename: filename
        )
        if !replaceExisting, originalIdentity != nil {
            throw PhysicalStateStoreError.alreadyExists
        }

        let temporaryName = ".schneeglass-state-\(UUID().uuidString.lowercased()).tmp"
        let temporaryDescriptor = try Self.createNewRegularFile(
            directoryDescriptor: directoryDescriptor,
            filename: temporaryName
        )

        var temporaryExists = true
        defer {
            close(temporaryDescriptor)
            if temporaryExists {
                temporaryName.withCString { name in
                    _ = unlinkat(directoryDescriptor, name, 0)
                }
            }
        }

        try Self.writeAll(data, to: temporaryDescriptor)
        guard fsync(temporaryDescriptor) == 0 else {
            throw PhysicalStateStoreError.ioFailure(errno)
        }

        let currentIdentity = try Self.regularFileIdentityIfPresent(
            directoryDescriptor: directoryDescriptor,
            filename: filename
        )

        if let originalIdentity {
            guard replaceExisting, currentIdentity == originalIdentity else {
                throw PhysicalStateStoreError.unsafeTopology
            }
        } else {
            guard currentIdentity == nil else {
                throw replaceExisting
                    ? PhysicalStateStoreError.unsafeTopology
                    : PhysicalStateStoreError.alreadyExists
            }
        }

        let renameResult = temporaryName.withCString { temporary in
            filename.withCString { final in
                renameat(directoryDescriptor, temporary, directoryDescriptor, final)
            }
        }
        guard renameResult == 0 else {
            throw Self.mapMutationError(errno)
        }

        // `renameat` is the final fallible commit step. Do not report a later housekeeping failure
        // after the visible state has already changed.
        temporaryExists = false
    }

    public func regularFileNames(
        in directoryComponents: [String] = []
    ) throws -> [String] {
        guard let directoryDescriptor = try openDirectoryChain(
            components: directoryComponents,
            create: false
        ) else {
            return []
        }
        defer { close(directoryDescriptor) }

        let duplicated = dup(directoryDescriptor)
        guard duplicated >= 0 else {
            throw PhysicalStateStoreError.ioFailure(errno)
        }
        guard let stream = fdopendir(duplicated) else {
            let observedErrno = errno
            close(duplicated)
            throw PhysicalStateStoreError.ioFailure(observedErrno)
        }
        defer { closedir(stream) }

        var names: [String] = []
        while let entry = readdir(stream) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) {
                    String(cString: $0)
                }
            }

            guard name != ".", name != ".." else {
                continue
            }

            var metadata = stat()
            let result = name.withCString { entryName in
                fstatat(directoryDescriptor, entryName, &metadata, AT_SYMLINK_NOFOLLOW)
            }
            if result != 0 {
                if errno == ENOENT {
                    continue
                }
                throw PhysicalStateStoreError.ioFailure(errno)
            }

            if (metadata.st_mode & S_IFMT) == S_IFREG {
                names.append(name)
            }
        }

        return names
    }

    public func removeRegularFile(
        in directoryComponents: [String] = [],
        named filename: String
    ) throws {
        try Self.validateComponent(filename)
        guard let directoryDescriptor = try openDirectoryChain(
            components: directoryComponents,
            create: false
        ) else {
            return
        }
        defer { close(directoryDescriptor) }

        guard let expectedIdentity = try Self.regularFileIdentityIfPresent(
            directoryDescriptor: directoryDescriptor,
            filename: filename
        ) else {
            return
        }
        guard try Self.regularFileIdentityIfPresent(
            directoryDescriptor: directoryDescriptor,
            filename: filename
        ) == expectedIdentity else {
            throw PhysicalStateStoreError.unsafeTopology
        }

        let result = filename.withCString { name in
            unlinkat(directoryDescriptor, name, 0)
        }
        guard result == 0 else {
            if errno == ENOENT {
                return
            }
            throw Self.mapMutationError(errno)
        }
    }

    private func openDirectoryChain(
        components: [String],
        create: Bool
    ) throws -> Int32? {
        for component in components {
            try Self.validateComponent(component)
        }

        guard var descriptor = try openRoot(create: create) else {
            return nil
        }

        do {
            for component in components {
                guard let next = try Self.openPhysicalDirectory(
                    parentDescriptor: descriptor,
                    component: component,
                    create: create
                ) else {
                    close(descriptor)
                    return nil
                }
                close(descriptor)
                descriptor = next
            }
            return descriptor
        } catch {
            close(descriptor)
            throw error
        }
    }

    private func openRoot(create: Bool) throws -> Int32? {
        let rootName = rootURL.lastPathComponent
        try Self.validateComponent(rootName)

        let parentURL = rootURL.deletingLastPathComponent().standardizedFileURL
        let anchor = try Self.openNearestExistingAncestor(startingAt: parentURL)
        var descriptor = anchor.descriptor

        do {
            for component in anchor.missingComponents + [rootName] {
                guard let next = try Self.openPhysicalDirectory(
                    parentDescriptor: descriptor,
                    component: component,
                    create: create
                ) else {
                    close(descriptor)
                    return nil
                }
                close(descriptor)
                descriptor = next
            }
            return descriptor
        } catch {
            close(descriptor)
            throw error
        }
    }

    private static func openNearestExistingAncestor(
        startingAt url: URL
    ) throws -> (descriptor: Int32, missingComponents: [String]) {
        var candidate = url.standardizedFileURL
        var missing: [String] = []

        while true {
            let descriptor = candidate.withUnsafeFileSystemRepresentation { path -> Int32 in
                guard let path else {
                    return -1
                }
                return open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
            }
            if descriptor >= 0 {
                return (descriptor, missing.reversed())
            }

            let observedErrno = errno
            guard observedErrno == ENOENT else {
                throw PhysicalStateStoreError.ioFailure(observedErrno)
            }

            let component = candidate.lastPathComponent
            guard !component.isEmpty else {
                throw PhysicalStateStoreError.ioFailure(observedErrno)
            }
            try validateComponent(component)
            missing.append(component)

            let parent = candidate.deletingLastPathComponent().standardizedFileURL
            guard parent.path != candidate.path else {
                throw PhysicalStateStoreError.ioFailure(observedErrno)
            }
            candidate = parent
        }
    }

    private static func openPhysicalDirectory(
        parentDescriptor: Int32,
        component: String,
        create: Bool
    ) throws -> Int32? {
        let openDirectory: () -> Int32 = {
            component.withCString { name in
                openat(
                    parentDescriptor,
                    name,
                    O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
                )
            }
        }

        var descriptor = openDirectory()
        if descriptor >= 0 {
            return descriptor
        }

        var observedErrno = errno
        if observedErrno == ENOENT, create {
            let mkdirResult = component.withCString { name in
                mkdirat(parentDescriptor, name, mode_t(0o700))
            }
            if mkdirResult != 0, errno != EEXIST {
                throw mapMutationError(errno)
            }

            descriptor = openDirectory()
            if descriptor >= 0 {
                return descriptor
            }
            observedErrno = errno
        }

        if observedErrno == ENOENT {
            return nil
        }
        if observedErrno == ELOOP || observedErrno == ENOTDIR {
            throw PhysicalStateStoreError.unsafeTopology
        }
        throw PhysicalStateStoreError.ioFailure(observedErrno)
    }

    private static func openRegularFile(
        directoryDescriptor: Int32,
        filename: String
    ) throws -> Int32? {
        let descriptor = filename.withCString { name in
            openat(directoryDescriptor, name, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        }
        if descriptor < 0 {
            let observedErrno = errno
            if observedErrno == ENOENT {
                return nil
            }
            if observedErrno == ELOOP || observedErrno == ENOTDIR {
                throw PhysicalStateStoreError.unsafeTopology
            }
            throw PhysicalStateStoreError.ioFailure(observedErrno)
        }

        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0 else {
            let observedErrno = errno
            close(descriptor)
            throw PhysicalStateStoreError.ioFailure(observedErrno)
        }
        guard (metadata.st_mode & S_IFMT) == S_IFREG else {
            close(descriptor)
            throw PhysicalStateStoreError.unsafeTopology
        }

        return descriptor
    }

    private static func regularFileIdentityIfPresent(
        directoryDescriptor: Int32,
        filename: String
    ) throws -> EntryIdentity? {
        var metadata = stat()
        let result = filename.withCString { name in
            fstatat(directoryDescriptor, name, &metadata, AT_SYMLINK_NOFOLLOW)
        }
        if result != 0 {
            if errno == ENOENT {
                return nil
            }
            throw PhysicalStateStoreError.ioFailure(errno)
        }

        guard (metadata.st_mode & S_IFMT) == S_IFREG else {
            throw PhysicalStateStoreError.unsafeTopology
        }
        return EntryIdentity(metadata)
    }

    private static func createNewRegularFile(
        directoryDescriptor: Int32,
        filename: String
    ) throws -> Int32 {
        let descriptor = filename.withCString { name in
            openat(
                directoryDescriptor,
                name,
                O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                mode_t(0o600)
            )
        }
        guard descriptor >= 0 else {
            if errno == EEXIST {
                throw PhysicalStateStoreError.alreadyExists
            }
            throw mapMutationError(errno)
        }
        return descriptor
    }

    private static func readAll(from descriptor: Int32) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)

        while true {
            var observedErrno = Int32(0)
            let count = buffer.withUnsafeMutableBytes { bytes -> Int in
                let result = Darwin.read(descriptor, bytes.baseAddress, bytes.count)
                if result < 0 {
                    observedErrno = errno
                }
                return result
            }

            if count == 0 {
                return data
            }
            if count < 0 {
                if observedErrno == EINTR {
                    continue
                }
                throw PhysicalStateStoreError.ioFailure(observedErrno)
            }
            data.append(contentsOf: buffer.prefix(count))
        }
    }

    private static func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let base = bytes.baseAddress?.advanced(by: offset)
                let written = Darwin.write(descriptor, base, bytes.count - offset)
                if written < 0 {
                    if errno == EINTR {
                        continue
                    }
                    throw PhysicalStateStoreError.ioFailure(errno)
                }
                guard written > 0 else {
                    throw PhysicalStateStoreError.ioFailure(EIO)
                }
                offset += written
            }
        }
    }

    private static func validateComponent(_ component: String) throws {
        guard !component.isEmpty,
              component != ".",
              component != "..",
              (component as NSString).lastPathComponent == component
        else {
            throw PhysicalStateStoreError.invalidPathComponent
        }
    }

    private static func mapMutationError(_ error: Int32) -> PhysicalStateStoreError {
        switch error {
        case ELOOP, ENOTDIR, EISDIR:
            return .unsafeTopology
        case EEXIST:
            return .alreadyExists
        default:
            return .ioFailure(error)
        }
    }
}

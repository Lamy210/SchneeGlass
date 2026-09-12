import Darwin
import Foundation

/// Process-local directory identity used to detect pathname replacement while an operation is active.
///
/// `st_dev` + `st_ino` are intentionally runtime-only. They are suitable for comparing two live
/// observations but must not be persisted as restart-safe authority because inode values can be
/// recycled after an object is removed.
public struct POSIXDirectoryIdentity: Hashable, Sendable {
    public let device: UInt64
    public let inode: UInt64

    public init(device: UInt64, inode: UInt64) {
        self.device = device
        self.inode = inode
    }
}

public enum POSIXDirectoryIdentityReader {
    /// Opens the directory and derives identity from the pinned descriptor rather than trusting
    /// path metadata returned before or after `open(2)`.
    public static func identity(at url: URL) -> POSIXDirectoryIdentity? {
        let candidate = url.standardizedFileURL
        guard candidate.isFileURL else {
            return nil
        }

        return candidate.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return nil
            }

            let descriptor = open(path, O_RDONLY | O_CLOEXEC | O_DIRECTORY)
            guard descriptor >= 0 else {
                return nil
            }
            defer { close(descriptor) }

            var metadata = stat()
            guard fstat(descriptor, &metadata) == 0,
                  (metadata.st_mode & S_IFMT) == S_IFDIR
            else {
                return nil
            }

            return POSIXDirectoryIdentity(
                device: UInt64(truncatingIfNeeded: metadata.st_dev),
                inode: UInt64(truncatingIfNeeded: metadata.st_ino)
            )
        }
    }
}

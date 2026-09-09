import Darwin
import Foundation

/// Physical identity token used only for Pending Copy ownership / commit verification.
///
/// The token is intentionally derived from `lstat(2)` rather than URL resource identifiers or
/// rounded Foundation dates. Pending Copy needs to distinguish a path that still names the exact
/// staged file from a path that was removed and recreated before commit/recovery. A same-filesystem
/// rename preserves these inode fields, while inode generation and nanosecond birth time strengthen
/// replacement detection when an inode number is reused quickly.
enum PendingCopyFileIdentity {
    private static let schema = "stat-v2"

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

            var metadata = stat()
            guard lstat(path, &metadata) == 0 else {
                // Identity is an authorization proof, not availability metadata. If the raw
                // identity cannot be read at this exact boundary, fail closed instead of trying
                // to infer ownership from the path alone.
                return nil
            }

            return [
                schema,
                String(metadata.st_dev),
                String(metadata.st_ino),
                String(metadata.st_gen),
                String(metadata.st_birthtimespec.tv_sec),
                String(metadata.st_birthtimespec.tv_nsec),
            ].joined(separator: ":")
        }
    }
}

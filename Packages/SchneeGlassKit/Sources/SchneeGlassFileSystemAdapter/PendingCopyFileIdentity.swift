import Foundation

/// Physical identity token used only for Pending Copy ownership / commit verification.
///
/// URL resource identifiers are intentionally not used as the sole ownership proof here. The
/// token combines filesystem/device number, filesystem file number, and creation time so a
/// same-path replacement can be distinguished from the file SchneeGlass originally staged while
/// a same-filesystem rename keeps the same identity.
enum PendingCopyFileIdentity {
    private static let schema = "stat-v1"

    static func token(
        at url: URL,
        fileManager: FileManager
    ) throws -> String? {
        let attributes = try fileManager.attributesOfItem(
            atPath: url.standardizedFileURL.path
        )
        return token(from: attributes)
    }

    static func token(
        from attributes: [FileAttributeKey: Any]
    ) -> String? {
        guard let systemNumber = attributes[.systemNumber] as? NSNumber,
              let fileNumber = attributes[.systemFileNumber] as? NSNumber,
              let creationDate = attributes[.creationDate] as? Date
        else {
            return nil
        }

        let creationBits = creationDate.timeIntervalSinceReferenceDate.bitPattern
        return [
            schema,
            String(systemNumber.uint64Value),
            String(fileNumber.uint64Value),
            String(creationBits, radix: 16),
        ].joined(separator: ":")
    }
}

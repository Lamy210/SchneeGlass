import Foundation
import SchneeGlassApplication

public actor PendingCopyRecoveryInspector: PendingCopyRecoveryInspecting {
    private enum FileObservation {
        case absent
        case regular(size: Int64)
        case unexpectedType
        case unavailable
    }

    private let fileManager: FileManager

    public init() {
        self.fileManager = .default
    }

    init(fileManager: FileManager) {
        self.fileManager = fileManager
    }

    public func assess(
        _ record: PendingCopyRecord,
        destinationAccess: FolderAccessHandle
    ) async -> PendingCopyRecoveryAssessment {
        guard record.destinationGlassID == destinationAccess.glassID else {
            return PendingCopyRecoveryAssessment(
                record: record,
                disposition: .destinationMismatch
            )
        }

        guard Self.isValid(record: record) else {
            return PendingCopyRecoveryAssessment(
                record: record,
                disposition: .invalidRecord
            )
        }

        let destination = destinationAccess.url.standardizedFileURL
        guard isReadableDirectory(destination) else {
            return PendingCopyRecoveryAssessment(
                record: record,
                disposition: .destinationUnavailable
            )
        }

        let stagingURL = destination
            .appendingPathComponent(record.stagingFilename, isDirectory: false)
            .standardizedFileURL
        let finalURL = destination
            .appendingPathComponent(record.finalFilename, isDirectory: false)
            .standardizedFileURL

        let staging = observeRegularFile(stagingURL)
        let final = observeRegularFile(finalURL)

        let disposition: PendingCopyRecoveryDisposition
        switch (staging, final) {
        case (.unavailable, _), (_, .unavailable):
            disposition = .destinationUnavailable

        case (.unexpectedType, _), (_, .unexpectedType):
            disposition = .unexpectedFileType

        case (.absent, .absent):
            disposition = .metadataOnly

        case let (.regular(size), .absent):
            disposition = .stagingPresent(
                Self.verification(actualSize: size, expectedSize: record.expectedSize)
            )

        case let (.absent, .regular(size)):
            disposition = .finalPresent(
                Self.verification(actualSize: size, expectedSize: record.expectedSize)
            )

        case (.regular, .regular):
            disposition = .stagingAndFinalPresent
        }

        return PendingCopyRecoveryAssessment(
            record: record,
            disposition: disposition
        )
    }

    private func isReadableDirectory(_ url: URL) -> Bool {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            return attributes[.type] as? FileAttributeType == .typeDirectory
        } catch {
            return false
        }
    }

    private func observeRegularFile(_ url: URL) -> FileObservation {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            let values = try url.resourceValues(forKeys: [
                .isAliasFileKey,
                .isPackageKey,
            ])

            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  values.isAliasFile != true,
                  values.isPackage != true
            else {
                return .unexpectedType
            }

            let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            return .regular(size: size)
        } catch {
            let cocoa = error as NSError
            if cocoa.domain == NSCocoaErrorDomain,
               cocoa.code == CocoaError.Code.fileNoSuchFile.rawValue
                || cocoa.code == CocoaError.Code.fileReadNoSuchFile.rawValue
            {
                return .absent
            }
            return .unavailable
        }
    }

    private static func isValid(record: PendingCopyRecord) -> Bool {
        let expectedStaging = ".schneeglass-copy-\(record.operationID.uuidString.lowercased()).partial"
        guard record.stagingFilename == expectedStaging,
              isSinglePathComponent(record.stagingFilename),
              isSinglePathComponent(record.finalFilename),
              record.stagingFilename != record.finalFilename
        else {
            return false
        }

        return true
    }

    private static func isSinglePathComponent(_ filename: String) -> Bool {
        guard !filename.isEmpty else {
            return false
        }
        return (filename as NSString).lastPathComponent == filename
    }

    private static func verification(
        actualSize: Int64,
        expectedSize: Int64?
    ) -> PendingCopyFileVerification {
        guard let expectedSize else {
            return .expectedSizeUnavailable(actual: actualSize)
        }
        guard expectedSize == actualSize else {
            return .sizeMismatch(expected: expectedSize, actual: actualSize)
        }
        return .matchesExpectedSize
    }
}

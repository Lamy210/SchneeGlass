import Foundation
import SchneeGlassApplication

public actor PendingCopyRecoveryInspector: PendingCopyRecoveryInspecting {
    private enum FileObservation {
        case absent
        case regular(size: Int64, resourceIdentifier: String?)
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

        guard PendingCopyRecoveryRecordValidator.isValid(record) else {
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

        case let (.regular(size, resourceIdentifier), .absent):
            disposition = .stagingPresent(
                Self.verification(
                    actualSize: size,
                    expectedSize: record.expectedSize,
                    observedResourceIdentifier: resourceIdentifier,
                    recordedResourceIdentifier: record.stagingResourceIdentifier
                )
            )

        case let (.absent, .regular(size, resourceIdentifier)):
            disposition = .finalPresent(
                Self.verification(
                    actualSize: size,
                    expectedSize: record.expectedSize,
                    observedResourceIdentifier: resourceIdentifier,
                    recordedResourceIdentifier: record.stagingResourceIdentifier
                )
            )

        case let (
            .regular(stagingSize, stagingResourceIdentifier),
            .regular(finalSize, finalResourceIdentifier)
        ):
            disposition = .stagingAndFinalPresent(
                staging: Self.verification(
                    actualSize: stagingSize,
                    expectedSize: record.expectedSize,
                    observedResourceIdentifier: stagingResourceIdentifier,
                    recordedResourceIdentifier: record.stagingResourceIdentifier
                ),
                final: Self.verification(
                    actualSize: finalSize,
                    expectedSize: record.expectedSize,
                    observedResourceIdentifier: finalResourceIdentifier,
                    recordedResourceIdentifier: record.stagingResourceIdentifier
                )
            )
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
            let resourceIdentifier = PendingCopyFileIdentity.token(from: attributes)
            return .regular(size: size, resourceIdentifier: resourceIdentifier)
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

    private static func verification(
        actualSize: Int64,
        expectedSize: Int64?,
        observedResourceIdentifier: String?,
        recordedResourceIdentifier: String?
    ) -> PendingCopyFileVerification {
        PendingCopyFileVerification(
            size: sizeVerification(actual: actualSize, expected: expectedSize),
            resourceIdentity: resourceIdentityVerification(
                observed: observedResourceIdentifier,
                recorded: recordedResourceIdentifier
            )
        )
    }

    private static func sizeVerification(
        actual: Int64,
        expected: Int64?
    ) -> PendingCopySizeVerification {
        guard let expected else {
            return .expectedSizeUnavailable(actual: actual)
        }
        guard expected == actual else {
            return .sizeMismatch(expected: expected, actual: actual)
        }
        return .matchesExpectedSize
    }

    private static func resourceIdentityVerification(
        observed: String?,
        recorded: String?
    ) -> PendingCopyResourceIdentityVerification {
        guard let recorded else {
            return .recordedIdentityUnavailable
        }
        guard let observed else {
            return .observedIdentityUnavailable
        }
        return observed == recorded
            ? .matchesRecordedIdentity
            : .mismatchesRecordedIdentity
    }
}

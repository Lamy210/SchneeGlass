import Darwin
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
        let candidate = url.standardizedFileURL
        switch Self.pathEntryType(at: candidate) {
        case .missing:
            return .absent
        case .regular:
            break
        case .other:
            return .unexpectedType
        case .unavailable:
            return .unavailable
        }

        let openResult = candidate.withUnsafeFileSystemRepresentation { path -> (Int32, Int32) in
            guard let path else {
                return (-1, EINVAL)
            }
            let descriptor = open(
                path,
                O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK
            )
            return (descriptor, descriptor >= 0 ? 0 : errno)
        }
        guard openResult.0 >= 0 else {
            if openResult.1 == ENOENT {
                return .absent
            }
            if openResult.1 == ELOOP {
                return .unexpectedType
            }
            return Self.observationAfterEntryChanged(at: candidate)
        }

        let descriptor = openResult.0
        defer { close(descriptor) }

        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0 else {
            return .unavailable
        }
        guard (metadata.st_mode & S_IFMT) == S_IFREG else {
            return .unexpectedType
        }
        guard PendingCopyFileIdentity.descriptorMatchesPath(
            descriptor,
            pathURL: candidate
        ) else {
            return Self.observationAfterEntryChanged(at: candidate)
        }

        let values: URLResourceValues
        do {
            values = try candidate.resourceValues(forKeys: [
                .isAliasFileKey,
                .isPackageKey,
            ])
        } catch {
            return Self.observationAfterEntryChanged(at: candidate)
        }

        guard PendingCopyFileIdentity.descriptorMatchesPath(
            descriptor,
            pathURL: candidate
        ) else {
            return Self.observationAfterEntryChanged(at: candidate)
        }
        guard values.isAliasFile != true,
              values.isPackage != true
        else {
            return .unexpectedType
        }

        return .regular(
            size: Int64(metadata.st_size),
            resourceIdentifier: PendingCopyFileIdentity.token(onFileDescriptor: descriptor)
        )
    }

    private enum PathEntryType {
        case missing
        case regular
        case other
        case unavailable
    }

    private static func pathEntryType(at url: URL) -> PathEntryType {
        var metadata = stat()
        let result = url.standardizedFileURL.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return Int32(-1)
            }
            return lstat(path, &metadata)
        }

        guard result == 0 else {
            return errno == ENOENT ? .missing : .unavailable
        }
        return (metadata.st_mode & S_IFMT) == S_IFREG ? .regular : .other
    }

    private static func observationAfterEntryChanged(at url: URL) -> FileObservation {
        switch pathEntryType(at: url) {
        case .missing:
            return .absent
        case .other:
            return .unexpectedType
        case .regular, .unavailable:
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

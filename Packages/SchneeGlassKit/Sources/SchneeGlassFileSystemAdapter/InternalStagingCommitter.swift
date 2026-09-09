import Foundation

public enum StagingCommitError: Error, Hashable, Sendable {
    case invalidStagingFile
    case crossDirectoryCommit
    case collision
    case stagingMissing
    case unexpectedFileType
    case sizeMismatch
    case resourceIdentityUnavailable
    case resourceIdentityMismatch
    case coordinationFailed
    case commitFailed
}

struct StagingCommitAuthorization: Hashable, Sendable {
    let expectedSize: Int64
    let expectedResourceIdentifier: String
}

protocol StagingCommitting: Sendable {
    func commit(stagingURL: URL, finalURL: URL) async throws
    func commit(
        stagingURL: URL,
        finalURL: URL,
        authorization: StagingCommitAuthorization
    ) async throws
}

extension StagingCommitting {
    func commit(
        stagingURL: URL,
        finalURL: URL,
        authorization: StagingCommitAuthorization
    ) async throws {
        try await commit(stagingURL: stagingURL, finalURL: finalURL)
    }
}

public actor InternalStagingCommitter: StagingCommitting {
    private static let stagingPrefix = ".schneeglass-copy-"
    private static let stagingSuffix = ".partial"

    private let fileManager: FileManager

    public init() {
        self.fileManager = .default
    }

    init(fileManager: FileManager) {
        self.fileManager = fileManager
    }

    func commit(stagingURL: URL, finalURL: URL) throws {
        let staging = stagingURL.standardizedFileURL
        guard Self.isOwnedStagingFilename(staging.lastPathComponent) else {
            throw StagingCommitError.invalidStagingFile
        }

        let authorization = try Self.currentAuthorization(
            at: staging,
            fileManager: fileManager
        )
        try commit(
            stagingURL: staging,
            finalURL: finalURL,
            authorization: authorization
        )
    }

    func commit(
        stagingURL: URL,
        finalURL: URL,
        authorization: StagingCommitAuthorization
    ) throws {
        let staging = stagingURL.standardizedFileURL
        let final = finalURL.standardizedFileURL
        let destinationDirectory = final.deletingLastPathComponent().standardizedFileURL

        guard staging.deletingLastPathComponent() == destinationDirectory else {
            throw StagingCommitError.crossDirectoryCommit
        }

        guard Self.isOwnedStagingFilename(staging.lastPathComponent) else {
            throw StagingCommitError.invalidStagingFile
        }

        let fileManager = self.fileManager
        var coordinationError: NSError?
        var operationError: StagingCommitError?

        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(
            writingItemAt: staging,
            options: .forMoving,
            writingItemAt: destinationDirectory,
            options: [],
            error: &coordinationError
        ) { coordinatedStaging, coordinatedDirectory in
            let coordinatedDestination = coordinatedDirectory
                .standardizedFileURL
                .appendingPathComponent(final.lastPathComponent, isDirectory: false)
                .standardizedFileURL

            do {
                try Self.revalidateOwnedStaging(
                    at: coordinatedStaging,
                    expectedDestination: coordinatedDirectory.standardizedFileURL,
                    expectedFilename: staging.lastPathComponent,
                    authorization: authorization,
                    fileManager: fileManager
                )

                guard !fileManager.fileExists(atPath: coordinatedDestination.path) else {
                    throw StagingCommitError.collision
                }

                do {
                    try fileManager.moveItem(
                        at: coordinatedStaging,
                        to: coordinatedDestination
                    )
                } catch {
                    if fileManager.fileExists(atPath: coordinatedDestination.path) {
                        throw StagingCommitError.collision
                    }
                    throw StagingCommitError.commitFailed
                }
            } catch let error as StagingCommitError {
                operationError = error
            } catch {
                operationError = .commitFailed
            }
        }

        if let operationError {
            throw operationError
        }
        if coordinationError != nil {
            throw StagingCommitError.coordinationFailed
        }
    }

    static func isOwnedStagingFilename(_ filename: String) -> Bool {
        guard filename.hasPrefix(stagingPrefix), filename.hasSuffix(stagingSuffix) else {
            return false
        }

        let start = filename.index(filename.startIndex, offsetBy: stagingPrefix.count)
        let end = filename.index(filename.endIndex, offsetBy: -stagingSuffix.count)
        guard start < end else {
            return false
        }

        let operationID = String(filename[start..<end])
        return UUID(uuidString: operationID) != nil
    }

    private static func currentAuthorization(
        at url: URL,
        fileManager: FileManager
    ) throws -> StagingCommitAuthorization {
        let candidate = url.standardizedFileURL
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try fileManager.attributesOfItem(atPath: candidate.path)
        } catch {
            if Self.isMissingFileError(error) {
                throw StagingCommitError.stagingMissing
            }
            throw StagingCommitError.commitFailed
        }

        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw StagingCommitError.unexpectedFileType
        }
        guard let size = (attributes[.size] as? NSNumber)?.int64Value else {
            throw StagingCommitError.sizeMismatch
        }

        let values: URLResourceValues
        do {
            values = try candidate.resourceValues(forKeys: [
                .isAliasFileKey,
                .isPackageKey,
            ])
        } catch {
            throw StagingCommitError.commitFailed
        }

        guard values.isAliasFile != true,
              values.isPackage != true
        else {
            throw StagingCommitError.unexpectedFileType
        }
        guard let identity = try PendingCopyFileIdentity.token(
            at: candidate,
            fileManager: fileManager
        ) else {
            throw StagingCommitError.resourceIdentityUnavailable
        }

        return StagingCommitAuthorization(
            expectedSize: size,
            expectedResourceIdentifier: identity
        )
    }

    private static func revalidateOwnedStaging(
        at url: URL,
        expectedDestination: URL,
        expectedFilename: String,
        authorization: StagingCommitAuthorization,
        fileManager: FileManager
    ) throws {
        let candidate = url.standardizedFileURL
        guard candidate.deletingLastPathComponent() == expectedDestination,
              candidate.lastPathComponent == expectedFilename
        else {
            throw StagingCommitError.invalidStagingFile
        }

        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try fileManager.attributesOfItem(atPath: candidate.path)
        } catch {
            if Self.isMissingFileError(error) {
                throw StagingCommitError.stagingMissing
            }
            throw StagingCommitError.commitFailed
        }

        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw StagingCommitError.unexpectedFileType
        }

        guard let observedSize = (attributes[.size] as? NSNumber)?.int64Value,
              observedSize == authorization.expectedSize
        else {
            throw StagingCommitError.sizeMismatch
        }

        let values: URLResourceValues
        do {
            values = try candidate.resourceValues(forKeys: [
                .isAliasFileKey,
                .isPackageKey,
            ])
        } catch {
            throw StagingCommitError.commitFailed
        }

        guard values.isAliasFile != true,
              values.isPackage != true
        else {
            throw StagingCommitError.unexpectedFileType
        }

        guard let observedIdentity = try PendingCopyFileIdentity.token(
            at: candidate,
            fileManager: fileManager
        ) else {
            throw StagingCommitError.resourceIdentityUnavailable
        }
        guard observedIdentity == authorization.expectedResourceIdentifier else {
            throw StagingCommitError.resourceIdentityMismatch
        }
    }

    private static func isMissingFileError(_ error: Error) -> Bool {
        let cocoa = error as NSError
        guard cocoa.domain == NSCocoaErrorDomain else {
            return false
        }
        return cocoa.code == CocoaError.Code.fileNoSuchFile.rawValue
            || cocoa.code == CocoaError.Code.fileReadNoSuchFile.rawValue
    }
}

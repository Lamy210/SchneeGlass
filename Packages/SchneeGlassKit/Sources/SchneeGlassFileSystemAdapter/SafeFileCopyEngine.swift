import Foundation
import FileDomain
import SchneeGlassApplication

struct CopySourceMetadata: Hashable, Sendable {
    let size: Int64
}

enum CopyFileSystemError: Error, Hashable, Sendable {
    case sourceUnavailable
    case unsupportedItem
    case destinationUnavailable
    case permissionDenied
    case insufficientSpace
    case collision
    case verificationFailed
    case unexpected
}

protocol CopyFileSystemAccessing: Sendable {
    func sourceMetadata(at url: URL) async throws -> CopySourceMetadata
    func isWritableDirectory(at url: URL) async -> Bool
    func itemExists(at url: URL) async -> Bool
    func copyItem(at sourceURL: URL, to stagingURL: URL) async throws
    func regularFileSize(at url: URL) async throws -> Int64
}

actor FoundationCopyFileSystemAccessor: CopyFileSystemAccessing {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func sourceMetadata(at url: URL) throws -> CopySourceMetadata {
        let sourceURL = url.standardizedFileURL
        let didStart = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStart {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let attributes = try fileManager.attributesOfItem(atPath: sourceURL.path)
            let resourceValues = try sourceURL.resourceValues(forKeys: [
                .isAliasFileKey,
                .isPackageKey,
            ])

            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  resourceValues.isAliasFile != true,
                  resourceValues.isPackage != true
            else {
                throw CopyFileSystemError.unsupportedItem
            }

            let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            return CopySourceMetadata(size: size)
        } catch let error as CopyFileSystemError {
            throw error
        } catch {
            throw Self.map(error)
        }
    }

    func isWritableDirectory(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let path = url.standardizedFileURL.path
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }
        return fileManager.isWritableFile(atPath: path)
    }

    func itemExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.standardizedFileURL.path)
    }

    func copyItem(at sourceURL: URL, to stagingURL: URL) throws {
        let source = sourceURL.standardizedFileURL
        let staging = stagingURL.standardizedFileURL
        let destinationDirectory = staging.deletingLastPathComponent()
        let didStart = source.startAccessingSecurityScopedResource()
        defer {
            if didStart {
                source.stopAccessingSecurityScopedResource()
            }
        }

        guard !fileManager.fileExists(atPath: staging.path) else {
            throw CopyFileSystemError.collision
        }

        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var operationError: Error?
        let fileManager = self.fileManager

        coordinator.coordinate(
            readingItemAt: source,
            options: [],
            writingItemAt: destinationDirectory,
            options: [],
            error: &coordinationError
        ) { coordinatedSource, coordinatedDirectory in
            let coordinatedStaging = coordinatedDirectory
                .appendingPathComponent(staging.lastPathComponent, isDirectory: false)
            do {
                try fileManager.copyItem(at: coordinatedSource, to: coordinatedStaging)
            } catch {
                operationError = error
            }
        }

        if let operationError {
            throw Self.map(operationError)
        }
        if let coordinationError {
            throw Self.map(coordinationError)
        }
    }

    func regularFileSize(at url: URL) throws -> Int64 {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.standardizedFileURL.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else {
                throw CopyFileSystemError.verificationFailed
            }
            return (attributes[.size] as? NSNumber)?.int64Value ?? 0
        } catch let error as CopyFileSystemError {
            throw error
        } catch {
            throw Self.map(error)
        }
    }

    private static func map(_ error: Error) -> CopyFileSystemError {
        let cocoa = error as NSError
        guard cocoa.domain == NSCocoaErrorDomain else {
            return .unexpected
        }

        switch cocoa.code {
        case CocoaError.Code.fileReadNoPermission.rawValue,
             CocoaError.Code.fileWriteNoPermission.rawValue:
            return .permissionDenied
        case CocoaError.Code.fileWriteOutOfSpace.rawValue:
            return .insufficientSpace
        case CocoaError.Code.fileNoSuchFile.rawValue,
             CocoaError.Code.fileReadNoSuchFile.rawValue:
            return .sourceUnavailable
        default:
            return .unexpected
        }
    }
}

public actor SafeFileCopyEngine: FileCopying {
    private struct PreparedItem: Sendable {
        let plan: CopyItemPlan
        let sourceSize: Int64
        let stagingURL: URL
        let finalURL: URL
    }

    private enum PreflightResult: Sendable {
        case ready([PreparedItem])
        case failed(index: Int, failure: CopyItemFailure)
    }

    private let fileSystem: any CopyFileSystemAccessing
    private let committer: any StagingCommitting
    private let recoveryStore: any PendingCopyRecording

    public init(recoveryStore: any PendingCopyRecording) {
        self.fileSystem = FoundationCopyFileSystemAccessor()
        self.committer = InternalStagingCommitter()
        self.recoveryStore = recoveryStore
    }

    init(
        fileSystem: any CopyFileSystemAccessing,
        committer: any StagingCommitting,
        recoveryStore: any PendingCopyRecording
    ) {
        self.fileSystem = fileSystem
        self.committer = committer
        self.recoveryStore = recoveryStore
    }

    public func copy(_ request: AuthorizedCopyBatchRequest) async -> CopyBatchResult {
        switch await preflight(request) {
        case let .failed(index, failure):
            return CopyBatchResult(
                batchID: request.plan.batchID,
                succeeded: [],
                failed: failure,
                notAttempted: request.plan.items.enumerated().compactMap { offset, item in
                    offset == index ? nil : item
                }
            )

        case let .ready(preparedItems):
            var succeeded: [CopyItemSuccess] = []
            succeeded.reserveCapacity(preparedItems.count)

            for (index, item) in preparedItems.enumerated() {
                let result = await execute(item, request: request)
                switch result {
                case let .success(success):
                    succeeded.append(success)
                case let .failure(failure):
                    let notAttempted = preparedItems.dropFirst(index + 1).map(\.plan)
                    return CopyBatchResult(
                        batchID: request.plan.batchID,
                        succeeded: succeeded,
                        failed: failure,
                        notAttempted: notAttempted
                    )
                }
            }

            return CopyBatchResult(
                batchID: request.plan.batchID,
                succeeded: succeeded,
                failed: nil,
                notAttempted: []
            )
        }
    }

    private func preflight(_ request: AuthorizedCopyBatchRequest) async -> PreflightResult {
        guard request.destinationAccess.glassID == request.plan.destination.glassID,
              request.destinationAccess.url.standardizedFileURL == request.plan.destination.url.standardizedFileURL,
              request.plan.destination.capabilities.locationKind != .network,
              request.plan.destination.capabilities.isWritable,
              await fileSystem.isWritableDirectory(at: request.destinationAccess.url)
        else {
            return .failed(
                index: 0,
                failure: CopyItemFailure(
                    operationID: request.plan.items[0].operationID,
                    reason: .destinationUnavailable
                )
            )
        }

        var prepared: [PreparedItem] = []
        prepared.reserveCapacity(request.plan.items.count)
        let destinationDirectory = request.destinationAccess.url.standardizedFileURL

        for (index, item) in request.plan.items.enumerated() {
            let source = item.sourceURL.standardizedFileURL
            let finalURL = destinationDirectory
                .appendingPathComponent(item.destinationFilename, isDirectory: false)
                .standardizedFileURL
            let stagingURL = destinationDirectory
                .appendingPathComponent(
                    ".schneeglass-copy-\(item.operationID.uuidString.lowercased()).partial",
                    isDirectory: false
                )
                .standardizedFileURL

            guard !item.destinationFilename.isEmpty,
                  (item.destinationFilename as NSString).lastPathComponent == item.destinationFilename,
                  finalURL.deletingLastPathComponent() == destinationDirectory,
                  stagingURL.deletingLastPathComponent() == destinationDirectory
            else {
                return .failed(
                    index: index,
                    failure: CopyItemFailure(operationID: item.operationID, reason: .unsupportedItem)
                )
            }

            guard source.deletingLastPathComponent() != destinationDirectory else {
                return .failed(
                    index: index,
                    failure: CopyItemFailure(operationID: item.operationID, reason: .collision)
                )
            }

            let metadata: CopySourceMetadata
            do {
                metadata = try await fileSystem.sourceMetadata(at: source)
            } catch {
                return .failed(
                    index: index,
                    failure: CopyItemFailure(
                        operationID: item.operationID,
                        reason: Self.failureReason(for: error)
                    )
                )
            }

            let finalExists = await fileSystem.itemExists(at: finalURL)
            let stagingExists = await fileSystem.itemExists(at: stagingURL)
            if finalExists || stagingExists {
                return .failed(
                    index: index,
                    failure: CopyItemFailure(operationID: item.operationID, reason: .collision)
                )
            }

            prepared.append(
                PreparedItem(
                    plan: item,
                    sourceSize: metadata.size,
                    stagingURL: stagingURL,
                    finalURL: finalURL
                )
            )
        }

        return .ready(prepared)
    }

    private func execute(
        _ item: PreparedItem,
        request: AuthorizedCopyBatchRequest
    ) async -> Result<CopyItemSuccess, CopyItemFailure> {
        let baseRecord = PendingCopyRecord(
            operationID: item.plan.operationID,
            batchID: request.plan.batchID,
            destinationGlassID: request.destinationAccess.glassID,
            stagingFilename: item.stagingURL.lastPathComponent,
            finalFilename: item.finalURL.lastPathComponent,
            expectedSize: item.sourceSize,
            state: .recorded
        )

        do {
            try await recoveryStore.upsert(baseRecord)
            try await recoveryStore.upsert(baseRecord.updating(state: .staging))
            try await fileSystem.copyItem(at: item.plan.sourceURL, to: item.stagingURL)

            try await recoveryStore.upsert(baseRecord.updating(state: .verifying))
            let stagedSize = try await fileSystem.regularFileSize(at: item.stagingURL)
            guard stagedSize == item.sourceSize else {
                throw CopyFileSystemError.verificationFailed
            }
        } catch {
            await removeStaleRecordWhenNoStagingExists(
                operationID: item.plan.operationID,
                stagingURL: item.stagingURL
            )
            return .failure(
                CopyItemFailure(
                    operationID: item.plan.operationID,
                    reason: Self.failureReason(for: error)
                )
            )
        }

        if await fileSystem.itemExists(at: item.finalURL) {
            return .failure(
                CopyItemFailure(operationID: item.plan.operationID, reason: .collision)
            )
        }

        do {
            try await recoveryStore.upsert(baseRecord.updating(state: .committing))
            try await committer.commit(stagingURL: item.stagingURL, finalURL: item.finalURL)
        } catch {
            return .failure(
                CopyItemFailure(
                    operationID: item.plan.operationID,
                    reason: Self.failureReason(for: error)
                )
            )
        }

        var cleanupPending = false
        do {
            try await recoveryStore.remove(operationID: item.plan.operationID)
        } catch {
            cleanupPending = true
        }

        return .success(
            CopyItemSuccess(
                operationID: item.plan.operationID,
                destinationURL: item.finalURL,
                recoveryMetadataCleanupPending: cleanupPending
            )
        )
    }

    private func removeStaleRecordWhenNoStagingExists(
        operationID: UUID,
        stagingURL: URL
    ) async {
        guard !(await fileSystem.itemExists(at: stagingURL)) else {
            return
        }

        do {
            try await recoveryStore.remove(operationID: operationID)
        } catch {
            // Keep stale metadata. Startup recovery can discard a record when
            // neither staging nor final data exists.
        }
    }

    private static func failureReason(for error: Error) -> CopyItemFailure.Reason {
        if let copyError = error as? CopyFileSystemError {
            switch copyError {
            case .sourceUnavailable:
                return .sourceUnavailable
            case .unsupportedItem:
                return .unsupportedItem
            case .destinationUnavailable:
                return .destinationUnavailable
            case .permissionDenied:
                return .permissionDenied
            case .insufficientSpace:
                return .insufficientSpace
            case .collision:
                return .collision
            case .verificationFailed:
                return .verificationFailed
            case .unexpected:
                return .unexpected
            }
        }

        if let commitError = error as? StagingCommitError {
            switch commitError {
            case .collision:
                return .collision
            case .stagingMissing:
                return .verificationFailed
            case .invalidStagingFile, .crossDirectoryCommit, .commitFailed:
                return .unexpected
            }
        }

        return .unexpected
    }
}

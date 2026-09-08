import Foundation
import SchneeGlassDomain

public enum PendingCopyRecoveryNavigationError: Error, Hashable, Sendable {
    case unsupportedAction
    case recordsLoadFailed
    case configurationLoadFailed
    case recordMissing
    case configurationMissing
    case destinationUnavailable
    case actionNoLongerAvailable
}

/// Executes read-only manual-inspection actions for Pending Copy Recovery.
///
/// The caller supplies only an operation ID and requested reveal action. This use case reloads the
/// recovery record and current Glass configuration, reacquires destination access, performs a fresh
/// filesystem assessment, and only then asks macOS to reveal the item. UI-held paths and stale
/// assessments are never treated as authority.
public actor PendingCopyRecoveryNavigationUseCase {
    private let pendingCopyStore: any PendingCopyRecording
    private let configurationStore: any ConfigurationPersisting
    private let accessController: any FolderAccessControlling
    private let recoveryInspector: any PendingCopyRecoveryInspecting
    private let fileActor: any WorkspaceFileActing

    public init(
        pendingCopyStore: any PendingCopyRecording,
        configurationStore: any ConfigurationPersisting,
        accessController: any FolderAccessControlling,
        recoveryInspector: any PendingCopyRecoveryInspecting,
        fileActor: any WorkspaceFileActing
    ) {
        self.pendingCopyStore = pendingCopyStore
        self.configurationStore = configurationStore
        self.accessController = accessController
        self.recoveryInspector = recoveryInspector
        self.fileActor = fileActor
    }

    public func reveal(
        action: PendingCopyRecoveryAction,
        operationID: UUID
    ) async throws {
        guard action == .revealStaging || action == .revealFinal else {
            throw PendingCopyRecoveryNavigationError.unsupportedAction
        }

        let records: [PendingCopyRecord]
        do {
            records = try await pendingCopyStore.records()
        } catch {
            throw PendingCopyRecoveryNavigationError.recordsLoadFailed
        }
        guard let record = records.first(where: { $0.operationID == operationID }) else {
            throw PendingCopyRecoveryNavigationError.recordMissing
        }

        let configurations: [GlassConfiguration]
        do {
            configurations = try await configurationStore.load()
        } catch {
            throw PendingCopyRecoveryNavigationError.configurationLoadFailed
        }
        guard let configuration = configurations.first(where: { $0.id == record.destinationGlassID }) else {
            throw PendingCopyRecoveryNavigationError.configurationMissing
        }

        let acquisition: FolderAccessAcquisition
        do {
            acquisition = try await accessController.acquire(
                source: configuration.source,
                glassID: configuration.id
            )
        } catch {
            throw PendingCopyRecoveryNavigationError.destinationUnavailable
        }

        do {
            let assessment = await recoveryInspector.assess(
                record,
                destinationAccess: acquisition.handle
            )
            let freshActions = PendingCopyRecoveryActionPlanner.plan(for: assessment).actions
            guard freshActions.contains(action) else {
                await accessController.release(handleID: acquisition.handle.id)
                throw PendingCopyRecoveryNavigationError.actionNoLongerAvailable
            }

            let filename: String
            switch action {
            case .revealStaging:
                filename = record.stagingFilename
            case .revealFinal:
                filename = record.finalFilename
            case .discardMetadata, .removeOwnedStaging, .reconnectDestination:
                await accessController.release(handleID: acquisition.handle.id)
                throw PendingCopyRecoveryNavigationError.unsupportedAction
            }

            let url = acquisition.handle.url
                .appendingPathComponent(filename, isDirectory: false)
                .standardizedFileURL

            await fileActor.reveal(url: url)
            await accessController.release(handleID: acquisition.handle.id)
        } catch let error as PendingCopyRecoveryNavigationError {
            throw error
        } catch {
            await accessController.release(handleID: acquisition.handle.id)
            throw error
        }
    }
}

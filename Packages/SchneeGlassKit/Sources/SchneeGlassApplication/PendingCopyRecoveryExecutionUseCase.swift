public protocol PendingCopyOwnedStagingCleaning: Sendable {
    func removeOwnedStaging(
        record: PendingCopyRecord,
        destinationAccess: FolderAccessHandle
    ) async throws
}

public enum PendingCopyRecoveryExecutionError: Error, Hashable, Sendable {
    case unsupportedAction
    case actionNotEligible
    case metadataMutationFailed
    case ownedStagingCleanupFailed
}

/// Executes only the mutation-capable subset of an already modeled Recovery action.
///
/// Eligibility is recalculated from a fresh read-only assessment immediately before mutation.
/// The concrete owned-staging cleaner must independently revalidate ownership at the filesystem
/// boundary; the planner result alone is never treated as deletion authority.
public actor PendingCopyRecoveryExecutionUseCase {
    private let pendingCopyStore: any PendingCopyRecording
    private let recoveryInspector: any PendingCopyRecoveryInspecting
    private let ownedStagingCleaner: any PendingCopyOwnedStagingCleaning

    public init(
        pendingCopyStore: any PendingCopyRecording,
        recoveryInspector: any PendingCopyRecoveryInspecting,
        ownedStagingCleaner: any PendingCopyOwnedStagingCleaning
    ) {
        self.pendingCopyStore = pendingCopyStore
        self.recoveryInspector = recoveryInspector
        self.ownedStagingCleaner = ownedStagingCleaner
    }

    public func execute(
        action: PendingCopyRecoveryAction,
        record: PendingCopyRecord,
        destinationAccess: FolderAccessHandle
    ) async throws {
        switch action {
        case .discardMetadata, .removeOwnedStaging:
            break
        case .revealStaging, .revealFinal, .reconnectDestination:
            throw PendingCopyRecoveryExecutionError.unsupportedAction
        }

        let assessment = await recoveryInspector.assess(
            record,
            destinationAccess: destinationAccess
        )
        let plan = PendingCopyRecoveryActionPlanner.plan(for: assessment)
        guard plan.actions.contains(action) else {
            throw PendingCopyRecoveryExecutionError.actionNotEligible
        }

        switch action {
        case .discardMetadata:
            do {
                try await pendingCopyStore.remove(operationID: record.operationID)
            } catch {
                throw PendingCopyRecoveryExecutionError.metadataMutationFailed
            }

        case .removeOwnedStaging:
            do {
                try await ownedStagingCleaner.removeOwnedStaging(
                    record: record,
                    destinationAccess: destinationAccess
                )
            } catch {
                throw PendingCopyRecoveryExecutionError.ownedStagingCleanupFailed
            }

        case .revealStaging, .revealFinal, .reconnectDestination:
            throw PendingCopyRecoveryExecutionError.unsupportedAction
        }
    }
}

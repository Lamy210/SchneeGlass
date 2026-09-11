import FileDomain

public enum RecoveryMutationAdmission: Hashable, Sendable {
    case granted
    case copyInProgress
    case recoveryInProgress
}

/// Coordinates file-copy execution with explicit Recovery mutations, including configuration backup
/// restore and Pending Copy Recovery changes.
///
/// Copies may run concurrently with other copies according to their existing per-Glass runtime
/// rules, but no new copy is admitted while a Recovery mutation holds the lease. Recovery mutation
/// admission is exclusive and is refused while any copy is active.
public actor FileOperationActivityGate {
    private var activeCopyCount = 0
    private var recoveryMutationActive = false

    public init() {}

    public func beginCopy() -> Bool {
        guard !recoveryMutationActive else {
            return false
        }
        activeCopyCount += 1
        return true
    }

    public func endCopy() {
        precondition(activeCopyCount > 0, "Unbalanced file copy activity")
        activeCopyCount -= 1
    }

    public func beginRecoveryMutation() -> RecoveryMutationAdmission {
        guard !recoveryMutationActive else {
            return .recoveryInProgress
        }
        guard activeCopyCount == 0 else {
            return .copyInProgress
        }
        recoveryMutationActive = true
        return .granted
    }

    public func endRecoveryMutation() {
        precondition(recoveryMutationActive, "Unbalanced recovery mutation activity")
        recoveryMutationActive = false
    }

    public func hasActiveCopies() -> Bool {
        activeCopyCount > 0
    }

    public func hasActiveRecoveryMutation() -> Bool {
        recoveryMutationActive
    }
}

/// FileCopying decorator that makes Recovery/Copy exclusion enforceable below Presentation.
public actor ActivityTrackedFileCopying: FileCopying {
    private let delegate: any FileCopying
    private let abandoner: any AuthorizedCopyBatchAbandoning
    private let activityGate: FileOperationActivityGate

    public init(
        delegate: any FileCopying,
        abandoner: any AuthorizedCopyBatchAbandoning,
        activityGate: FileOperationActivityGate
    ) {
        self.delegate = delegate
        self.abandoner = abandoner
        self.activityGate = activityGate
    }

    public func copy(_ request: AuthorizedCopyBatchRequest) async -> CopyBatchResult {
        guard await activityGate.beginCopy() else {
            // Authoritative Drop planning may already hold source descriptor authority. If Recovery
            // wins the race between planning and execution, release that authority immediately
            // rather than waiting for the unconsumed-plan TTL fallback.
            await abandoner.abandon(request)

            let first = request.plan.items[0]
            return CopyBatchResult(
                batchID: request.plan.batchID,
                succeeded: [],
                failed: CopyItemFailure(
                    operationID: first.operationID,
                    reason: .cancelled
                ),
                notAttempted: Array(request.plan.items.dropFirst())
            )
        }

        let result = await delegate.copy(request)
        await activityGate.endCopy()
        return result
    }
}

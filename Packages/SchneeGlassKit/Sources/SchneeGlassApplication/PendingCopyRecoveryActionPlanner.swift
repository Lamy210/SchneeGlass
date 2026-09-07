public enum PendingCopyRecoveryAction: Hashable, Sendable {
    /// Remove only the app-owned recovery metadata. Never mutates user files.
    case discardMetadata

    /// Reveal the staging item to the user without claiming it is safe to delete.
    case revealStaging

    /// Reveal the final destination item without claiming ownership of it.
    case revealFinal

    /// Explicitly remove only a staging item whose persisted operation metadata
    /// and filesystem resource identity both match. Never runs automatically.
    case removeOwnedStaging

    /// Ask the user to restore/reconnect access to the destination folder.
    case reconnectDestination
}

public struct PendingCopyRecoveryActionPlan: Hashable, Sendable {
    public let actions: [PendingCopyRecoveryAction]

    public init(actions: [PendingCopyRecoveryAction]) {
        self.actions = actions
    }
}

public enum PendingCopyRecoveryActionPlanner {
    public static func plan(
        for assessment: PendingCopyRecoveryAssessment
    ) -> PendingCopyRecoveryActionPlan {
        let actions: [PendingCopyRecoveryAction]

        switch assessment.disposition {
        case .metadataOnly:
            actions = [.discardMetadata]

        case let .stagingPresent(verification):
            actions = stagingActions(verification: verification)

        case .finalPresent:
            actions = [.revealFinal, .discardMetadata]

        case let .stagingAndFinalPresent(staging, _):
            var conflictActions: [PendingCopyRecoveryAction] = [
                .revealStaging,
                .revealFinal,
            ]
            if staging.resourceIdentity == .matchesRecordedIdentity {
                conflictActions.append(.removeOwnedStaging)
            }
            actions = conflictActions

        case .destinationMismatch, .destinationUnavailable:
            actions = [.reconnectDestination]

        case .invalidRecord, .unexpectedFileType:
            actions = []
        }

        return PendingCopyRecoveryActionPlan(actions: actions)
    }

    private static func stagingActions(
        verification: PendingCopyFileVerification
    ) -> [PendingCopyRecoveryAction] {
        guard verification.resourceIdentity == .matchesRecordedIdentity else {
            return [.revealStaging]
        }
        return [.revealStaging, .removeOwnedStaging]
    }
}

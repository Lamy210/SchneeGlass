public enum PendingCopyRecoveryAction: Hashable, Sendable {
    /// Remove only the app-owned recovery metadata. Never mutates user files.
    case discardMetadata

    /// Reveal the app-owned staging item to the user.
    case revealStaging

    /// Reveal the final destination item without claiming ownership of it.
    case revealFinal

    /// Explicitly remove only the staging item proven by operation metadata.
    /// This action must never run automatically.
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

        case .stagingPresent:
            actions = [.revealStaging, .removeOwnedStaging]

        case .finalPresent:
            actions = [.revealFinal, .discardMetadata]

        case .stagingAndFinalPresent:
            actions = [.revealStaging, .revealFinal, .removeOwnedStaging]

        case .destinationMismatch, .destinationUnavailable:
            actions = [.reconnectDestination]

        case .invalidRecord, .unexpectedFileType:
            actions = []
        }

        return PendingCopyRecoveryActionPlan(actions: actions)
    }
}

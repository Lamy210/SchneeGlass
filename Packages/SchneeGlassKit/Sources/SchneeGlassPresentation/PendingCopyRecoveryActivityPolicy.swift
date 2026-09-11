import Foundation

/// Presentation-level exclusion for Pending Copy Recovery. A refresh and a row action must never
/// overlap because a late refresh result could overwrite the state produced by the newer action.
enum PendingCopyRecoveryActivityPolicy {
    static func canStart(
        isLoading: Bool,
        activeOperationID: UUID?
    ) -> Bool {
        !isLoading && activeOperationID == nil
    }
}

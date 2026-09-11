import Foundation

enum PendingCopyRecoveryActivityPolicy {
    static func canStart(
        isLoading: Bool,
        activeOperationID: UUID?
    ) -> Bool {
        !isLoading && activeOperationID == nil
    }
}

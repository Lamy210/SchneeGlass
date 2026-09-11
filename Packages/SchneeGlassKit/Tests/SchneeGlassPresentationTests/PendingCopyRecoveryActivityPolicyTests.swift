import Foundation
import Testing
@testable import SchneeGlassPresentation

@Test
func recoveryCenterActivityPolicyAllowsOnlyIdleState() {
    #expect(
        PendingCopyRecoveryActivityPolicy.canStart(
            isLoading: false,
            activeOperationID: nil
        )
    )

    #expect(
        !PendingCopyRecoveryActivityPolicy.canStart(
            isLoading: true,
            activeOperationID: nil
        )
    )

    #expect(
        !PendingCopyRecoveryActivityPolicy.canStart(
            isLoading: false,
            activeOperationID: UUID()
        )
    )

    #expect(
        !PendingCopyRecoveryActivityPolicy.canStart(
            isLoading: true,
            activeOperationID: UUID()
        )
    )
}

import Testing
@testable import SchneeGlassPresentation

@Test
func failedPostActionReloadDiscardsPreviouslyActionableItems() {
    let staleItems = [1, 2, 3]

    let result = PendingCopyRecoveryPostActionReloadPolicy.itemsAfterFailedReload(
        currentItems: staleItems
    )

    #expect(result.isEmpty)
}

@Test
func failedPostActionReloadKeepsEmptyStateEmpty() {
    let result: [Int] = PendingCopyRecoveryPostActionReloadPolicy.itemsAfterFailedReload(
        currentItems: []
    )

    #expect(result.isEmpty)
}

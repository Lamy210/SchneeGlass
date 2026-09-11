import Testing
@testable import SchneeGlassPresentation

@Test @MainActor
func placementPersistenceRetryWaitsPastLegacyAttemptLimit() async {
    var attempts = 0

    await retryPlacementPersistenceWhileBusy(retryDelayNanoseconds: 0) {
        attempts += 1
        return attempts < 9 ? .busy : .updated
    }

    #expect(attempts == 9)
}

@Test @MainActor
func placementPersistenceRetryStopsAfterNonBusyResult() async {
    var attempts = 0

    await retryPlacementPersistenceWhileBusy(retryDelayNanoseconds: 0) {
        attempts += 1
        return .missing
    }

    #expect(attempts == 1)
}

import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing

private func makeAssessment(
    _ disposition: PendingCopyRecoveryDisposition
) -> PendingCopyRecoveryAssessment {
    let operationID = UUID()
    let glassID = GlassID()
    let record = PendingCopyRecord(
        operationID: operationID,
        batchID: UUID(),
        destinationGlassID: glassID,
        stagingFilename: ".schneeglass-copy-\(operationID.uuidString.lowercased()).partial",
        finalFilename: "payload.txt",
        expectedSize: 7,
        state: .verifying
    )
    return PendingCopyRecoveryAssessment(
        record: record,
        disposition: disposition
    )
}

@Test
func metadataOnlyOffersMetadataDiscardOnly() {
    let plan = PendingCopyRecoveryActionPlanner.plan(
        for: makeAssessment(.metadataOnly)
    )

    #expect(plan.actions == [.discardMetadata])
}

@Test
func stagingPresentNeverOffersFinalMutation() {
    let plan = PendingCopyRecoveryActionPlanner.plan(
        for: makeAssessment(.stagingPresent(.matchesExpectedSize))
    )

    #expect(plan.actions == [.revealStaging, .removeOwnedStaging])
    #expect(!plan.actions.contains(.discardMetadata))
}

@Test
func finalPresentCanBeRevealedAndMetadataDismissed() {
    let plan = PendingCopyRecoveryActionPlanner.plan(
        for: makeAssessment(.finalPresent(.matchesExpectedSize))
    )

    #expect(plan.actions == [.revealFinal, .discardMetadata])
    #expect(!plan.actions.contains(.removeOwnedStaging))
}

@Test
func stagingAndFinalConflictNeverOffersMetadataDiscard() {
    let plan = PendingCopyRecoveryActionPlanner.plan(
        for: makeAssessment(.stagingAndFinalPresent)
    )

    #expect(plan.actions == [.revealStaging, .revealFinal, .removeOwnedStaging])
    #expect(!plan.actions.contains(.discardMetadata))
}

@Test
func unavailableDestinationOffersReconnectOnly() {
    let plan = PendingCopyRecoveryActionPlanner.plan(
        for: makeAssessment(.destinationUnavailable)
    )

    #expect(plan.actions == [.reconnectDestination])
}

@Test
func invalidOrUnexpectedRecoveryStateOffersNoMutationActions() {
    let invalidPlan = PendingCopyRecoveryActionPlanner.plan(
        for: makeAssessment(.invalidRecord)
    )
    let unexpectedPlan = PendingCopyRecoveryActionPlanner.plan(
        for: makeAssessment(.unexpectedFileType)
    )

    #expect(invalidPlan.actions.isEmpty)
    #expect(unexpectedPlan.actions.isEmpty)
}

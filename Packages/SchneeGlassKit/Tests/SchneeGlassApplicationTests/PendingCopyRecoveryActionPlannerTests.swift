import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing

private func verification(
    size: PendingCopySizeVerification = .matchesExpectedSize,
    identity: PendingCopyResourceIdentityVerification
) -> PendingCopyFileVerification {
    PendingCopyFileVerification(size: size, resourceIdentity: identity)
}

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
        stagingResourceIdentifier: "resource-a",
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
func stagingWithMatchingIdentityOffersExplicitOwnedCleanup() {
    let plan = PendingCopyRecoveryActionPlanner.plan(
        for: makeAssessment(
            .stagingPresent(
                verification(identity: .matchesRecordedIdentity)
            )
        )
    )

    #expect(plan.actions == [.revealStaging, .removeOwnedStaging])
    #expect(!plan.actions.contains(.discardMetadata))
}

@Test
func stagingWithoutRecordedIdentityIsRevealOnly() {
    let plan = PendingCopyRecoveryActionPlanner.plan(
        for: makeAssessment(
            .stagingPresent(
                verification(identity: .recordedIdentityUnavailable)
            )
        )
    )

    #expect(plan.actions == [.revealStaging])
}

@Test
func stagingWithIdentityMismatchIsRevealOnly() {
    let plan = PendingCopyRecoveryActionPlanner.plan(
        for: makeAssessment(
            .stagingPresent(
                verification(identity: .mismatchesRecordedIdentity)
            )
        )
    )

    #expect(plan.actions == [.revealStaging])
}

@Test
func finalPresentCanBeRevealedAndMetadataDismissed() {
    let plan = PendingCopyRecoveryActionPlanner.plan(
        for: makeAssessment(
            .finalPresent(
                verification(identity: .matchesRecordedIdentity)
            )
        )
    )

    #expect(plan.actions == [.revealFinal, .discardMetadata])
    #expect(!plan.actions.contains(.removeOwnedStaging))
}

@Test
func conflictWithMatchingStagingIdentityCanOfferOwnedStagingCleanup() {
    let plan = PendingCopyRecoveryActionPlanner.plan(
        for: makeAssessment(
            .stagingAndFinalPresent(
                staging: verification(identity: .matchesRecordedIdentity),
                final: verification(identity: .mismatchesRecordedIdentity)
            )
        )
    )

    #expect(plan.actions == [.revealStaging, .revealFinal, .removeOwnedStaging])
    #expect(!plan.actions.contains(.discardMetadata))
}

@Test
func conflictWithoutStagingIdentityMatchIsRevealOnly() {
    let plan = PendingCopyRecoveryActionPlanner.plan(
        for: makeAssessment(
            .stagingAndFinalPresent(
                staging: verification(identity: .recordedIdentityUnavailable),
                final: verification(identity: .matchesRecordedIdentity)
            )
        )
    )

    #expect(plan.actions == [.revealStaging, .revealFinal])
    #expect(!plan.actions.contains(.removeOwnedStaging))
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

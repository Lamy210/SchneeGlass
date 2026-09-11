import Testing
@testable import SchneeGlassPresentation

@Test
@MainActor
func cancelledDragSessionNotifiesWorkspaceExitCleanup() {
    var exitCount = 0
    let view = FileURLDropDestinationView(
        onPlan: { _ in false },
        onExit: { exitCount += 1 },
        onPerform: { _ in }
    )

    view.finishDraggingSession(performWasDispatched: false)

    #expect(exitCount == 1)
}

@Test
@MainActor
func completedDropDoesNotSendCancellationCleanup() {
    var exitCount = 0
    let view = FileURLDropDestinationView(
        onPlan: { _ in false },
        onExit: { exitCount += 1 },
        onPerform: { _ in }
    )

    view.finishDraggingSession(performWasDispatched: true)

    #expect(exitCount == 0)
}

@Test
func dropValidationRefreshPolicyRechecksStableSignatureWithoutOverlappingWork() {
    var policy = DropValidationRefreshPolicy(minimumInterval: 0.5)

    #expect(
        policy.decision(
            for: "same-files",
            now: 10,
            validationInFlight: false
        ) == .start(isNewSignature: true)
    )
    #expect(
        policy.decision(
            for: "same-files",
            now: 10.2,
            validationInFlight: false
        ) == .skip
    )
    #expect(
        policy.decision(
            for: "same-files",
            now: 10.6,
            validationInFlight: true
        ) == .skip
    )
    #expect(
        policy.decision(
            for: "same-files",
            now: 10.6,
            validationInFlight: false
        ) == .start(isNewSignature: false)
    )

    #expect(
        policy.decision(
            for: "different-files",
            now: 10.61,
            validationInFlight: true
        ) == .start(isNewSignature: true)
    )

    policy.reset()
    #expect(
        policy.decision(
            for: "different-files",
            now: 10.62,
            validationInFlight: false
        ) == .start(isNewSignature: true)
    )
}

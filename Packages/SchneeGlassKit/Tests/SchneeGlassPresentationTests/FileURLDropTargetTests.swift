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

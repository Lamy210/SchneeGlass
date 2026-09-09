import Testing
@testable import SchneeGlassPresentation

@Test
@MainActor
func dragSessionEndAlwaysNotifiesWorkspaceExitCleanup() {
    var exitCount = 0
    let view = FileURLDropDestinationView(
        onPlan: { _ in false },
        onExit: { exitCount += 1 },
        onPerform: { _ in }
    )

    view.finishDraggingSession()

    #expect(exitCount == 1)
}

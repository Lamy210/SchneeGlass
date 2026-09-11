import Testing
@testable import SchneeGlassPresentation

@Test
func workspaceRecoveryActivityStartsOnlyWhenWorkspaceIsIdle() {
    var tracker = WorkspaceRecoveryActivityTracker()

    let rejectedDuringConfigurationMutation = tracker.begin(configurationMutationActive: true)
    #expect(!rejectedDuringConfigurationMutation)
    #expect(!tracker.isActive)

    let didBegin = tracker.begin(configurationMutationActive: false)
    #expect(didBegin)
    #expect(tracker.isActive)

    let rejectedWhileRecoveryIsActive = tracker.begin(configurationMutationActive: false)
    #expect(!rejectedWhileRecoveryIsActive)
    #expect(tracker.isActive)

    tracker.end()
    #expect(!tracker.isActive)

    let didBeginAgain = tracker.begin(configurationMutationActive: false)
    #expect(didBeginAgain)
    tracker.end()
}

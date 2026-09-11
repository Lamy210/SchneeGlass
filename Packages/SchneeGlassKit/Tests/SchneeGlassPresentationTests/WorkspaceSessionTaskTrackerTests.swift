import Testing
@testable import SchneeGlassPresentation
import SchneeGlassDomain

@Test
func newerWorkspaceSessionTaskSupersedesOlderGeneration() {
    var tracker = WorkspaceSessionTaskTracker()
    let glassID = GlassID()

    let oldToken = tracker.begin(glassID)
    let newToken = tracker.begin(glassID)

    #expect(!tracker.isCurrent(oldToken, for: glassID))
    #expect(tracker.isCurrent(newToken, for: glassID))

    let oldDidFinish = tracker.finish(oldToken, for: glassID)
    #expect(!oldDidFinish)
    #expect(tracker.isCurrent(newToken, for: glassID))

    let newDidFinish = tracker.finish(newToken, for: glassID)
    #expect(newDidFinish)
    #expect(!tracker.isCurrent(newToken, for: glassID))
}

@Test
func invalidatedWorkspaceSessionTaskCannotFinishLate() {
    var tracker = WorkspaceSessionTaskTracker()
    let glassID = GlassID()
    let token = tracker.begin(glassID)

    tracker.invalidate(glassID)

    #expect(!tracker.isCurrent(token, for: glassID))
    let didFinish = tracker.finish(token, for: glassID)
    #expect(!didFinish)
}

@Test
func invalidatingAllWorkspaceSessionTasksMakesEveryGenerationStale() {
    var tracker = WorkspaceSessionTaskTracker()
    let firstGlassID = GlassID()
    let secondGlassID = GlassID()
    let firstToken = tracker.begin(firstGlassID)
    let secondToken = tracker.begin(secondGlassID)

    tracker.invalidateAll()

    #expect(!tracker.isCurrent(firstToken, for: firstGlassID))
    #expect(!tracker.isCurrent(secondToken, for: secondGlassID))
    let firstDidFinish = tracker.finish(firstToken, for: firstGlassID)
    let secondDidFinish = tracker.finish(secondToken, for: secondGlassID)
    #expect(!firstDidFinish)
    #expect(!secondDidFinish)
}

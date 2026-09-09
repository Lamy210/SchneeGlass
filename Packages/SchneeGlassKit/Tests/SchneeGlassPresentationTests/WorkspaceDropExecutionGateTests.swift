import SchneeGlassDomain
import Testing
@testable import SchneeGlassPresentation

@Test
func dropExecutionGateSerializesOneGlassButNotDifferentGlasses() {
    var gate = WorkspaceDropExecutionGate()
    let firstGlass = GlassID()
    let secondGlass = GlassID()

    let firstBegin = gate.begin(firstGlass)
    #expect(firstBegin)
    #expect(gate.contains(firstGlass))
    #expect(gate.hasActiveExecution)

    let duplicateBegin = gate.begin(firstGlass)
    let secondBegin = gate.begin(secondGlass)
    #expect(!duplicateBegin)
    #expect(secondBegin)
    #expect(gate.contains(secondGlass))

    gate.end(firstGlass)
    #expect(!gate.contains(firstGlass))
    #expect(gate.contains(secondGlass))
    let reacquiredFirst = gate.begin(firstGlass)
    #expect(reacquiredFirst)

    gate.end(firstGlass)
    gate.end(secondGlass)
    #expect(!gate.hasActiveExecution)
}

@Test
func endingUnknownGlassDoesNotReleaseAnotherExecution() {
    var gate = WorkspaceDropExecutionGate()
    let activeGlass = GlassID()

    let initialBegin = gate.begin(activeGlass)
    #expect(initialBegin)
    gate.end(GlassID())

    #expect(gate.contains(activeGlass))
    let duplicateBegin = gate.begin(activeGlass)
    #expect(!duplicateBegin)

    gate.end(activeGlass)
    let reacquired = gate.begin(activeGlass)
    #expect(reacquired)
}

@Test
func newerHoverPlanningSupersedesOlderResultForSameGlass() {
    var tracker = WorkspaceDropPlanningTracker()
    let glassID = GlassID()

    let older = tracker.begin(glassID)
    let newer = tracker.begin(glassID)

    #expect(!tracker.isCurrent(older, for: glassID))
    #expect(tracker.isCurrent(newer, for: glassID))

    tracker.finish(older, for: glassID)
    #expect(tracker.isCurrent(newer, for: glassID))

    tracker.finish(newer, for: glassID)
    #expect(!tracker.isCurrent(newer, for: glassID))
}

@Test
func invalidatingHoverPlanningMakesLateResultStale() {
    var tracker = WorkspaceDropPlanningTracker()
    let glassID = GlassID()
    let token = tracker.begin(glassID)

    tracker.invalidate(glassID)

    #expect(!tracker.isCurrent(token, for: glassID))
}

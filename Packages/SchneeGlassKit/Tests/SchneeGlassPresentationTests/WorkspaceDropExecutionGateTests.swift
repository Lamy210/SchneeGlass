import SchneeGlassDomain
import Testing
@testable import SchneeGlassPresentation

@Test
func dropExecutionGateSerializesOneGlassButNotDifferentGlasses() {
    var gate = WorkspaceDropExecutionGate()
    let firstGlass = GlassID()
    let secondGlass = GlassID()

    #expect(gate.begin(firstGlass))
    #expect(gate.contains(firstGlass))
    #expect(gate.hasActiveExecution)

    #expect(!gate.begin(firstGlass))
    #expect(gate.begin(secondGlass))
    #expect(gate.contains(secondGlass))

    gate.end(firstGlass)
    #expect(!gate.contains(firstGlass))
    #expect(gate.contains(secondGlass))
    #expect(gate.begin(firstGlass))

    gate.end(firstGlass)
    gate.end(secondGlass)
    #expect(!gate.hasActiveExecution)
}

@Test
func endingUnknownGlassDoesNotReleaseAnotherExecution() {
    var gate = WorkspaceDropExecutionGate()
    let activeGlass = GlassID()

    #expect(gate.begin(activeGlass))
    gate.end(GlassID())

    #expect(gate.contains(activeGlass))
    #expect(!gate.begin(activeGlass))

    gate.end(activeGlass)
    #expect(gate.begin(activeGlass))
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

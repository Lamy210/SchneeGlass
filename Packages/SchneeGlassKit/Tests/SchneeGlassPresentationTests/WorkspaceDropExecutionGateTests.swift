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

import SchneeGlassDomain

/// Main-actor workspace state that reserves one Drop execution per Glass from fresh planning
/// through copy completion. Different Glasses remain independent and may execute concurrently.
struct WorkspaceDropExecutionGate {
    private var activeGlassIDs: Set<GlassID> = []

    var hasActiveExecution: Bool {
        !activeGlassIDs.isEmpty
    }

    func contains(_ glassID: GlassID) -> Bool {
        activeGlassIDs.contains(glassID)
    }

    mutating func begin(_ glassID: GlassID) -> Bool {
        activeGlassIDs.insert(glassID).inserted
    }

    mutating func end(_ glassID: GlassID) {
        activeGlassIDs.remove(glassID)
    }
}

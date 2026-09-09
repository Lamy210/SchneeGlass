import Foundation
import SchneeGlassDomain

/// Tracks the latest hover-planning request for each Glass. Planning is intentionally not a lock:
/// a committed Drop execution may start while an older hover validation is still unwinding. The
/// token makes those superseded async results unable to overwrite the current interaction state.
struct WorkspaceDropPlanningTracker {
    private var tokenByGlassID: [GlassID: UUID] = [:]

    mutating func begin(_ glassID: GlassID) -> UUID {
        let token = UUID()
        tokenByGlassID[glassID] = token
        return token
    }

    func isCurrent(_ token: UUID, for glassID: GlassID) -> Bool {
        tokenByGlassID[glassID] == token
    }

    mutating func finish(_ token: UUID, for glassID: GlassID) {
        guard tokenByGlassID[glassID] == token else {
            return
        }
        tokenByGlassID.removeValue(forKey: glassID)
    }

    mutating func invalidate(_ glassID: GlassID) {
        tokenByGlassID.removeValue(forKey: glassID)
    }
}

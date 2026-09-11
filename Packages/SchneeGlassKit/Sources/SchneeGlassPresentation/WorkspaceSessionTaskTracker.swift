import Foundation
import SchneeGlassDomain

/// Tracks the current runtime-state consumer for each Glass.
///
/// Session streams can finish after cancellation while a replacement session for the same Glass ID
/// has already been activated. A generation token prevents that stale task from publishing late
/// state or clearing the replacement session/task during its terminal cleanup.
struct WorkspaceSessionTaskTracker {
    private var tokenByGlassID: [GlassID: UUID] = [:]

    mutating func begin(_ glassID: GlassID) -> UUID {
        let token = UUID()
        tokenByGlassID[glassID] = token
        return token
    }

    func isCurrent(_ token: UUID, for glassID: GlassID) -> Bool {
        tokenByGlassID[glassID] == token
    }

    mutating func finish(_ token: UUID, for glassID: GlassID) -> Bool {
        guard tokenByGlassID[glassID] == token else {
            return false
        }
        tokenByGlassID.removeValue(forKey: glassID)
        return true
    }

    mutating func invalidate(_ glassID: GlassID) {
        tokenByGlassID.removeValue(forKey: glassID)
    }

    mutating func invalidateAll() {
        tokenByGlassID.removeAll(keepingCapacity: false)
    }
}

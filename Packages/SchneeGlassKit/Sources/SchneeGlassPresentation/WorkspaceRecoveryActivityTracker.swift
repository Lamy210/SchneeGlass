/// Main-actor presentation state that excludes Recovery work from configuration mutation.
///
/// `SchneeGlassWorkspaceModel` already serializes configuration changes with
/// `isMutatingConfiguration`. Recovery begins through this tracker before its first suspension, so a
/// configuration mutation and a Recovery refresh/action cannot both pass admission in the same
/// MainActor turn.
struct WorkspaceRecoveryActivityTracker {
    private(set) var isActive = false

    mutating func begin(configurationMutationActive: Bool) -> Bool {
        guard !configurationMutationActive, !isActive else {
            return false
        }
        isActive = true
        return true
    }

    mutating func end() {
        precondition(isActive, "Unbalanced workspace Recovery activity")
        isActive = false
    }
}

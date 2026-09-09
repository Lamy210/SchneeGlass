import SchneeGlassApplication

/// Canonical composition boundary for native Drop planning and pinned-source copying.
///
/// Planning and execution must share one `SourceFileLeaseRegistry`: planning pins the exact source
/// inode and binds it to each operation ID, while execution consumes that same authority. Creating
/// the pair here prevents callers from accidentally wiring a planner and copier to unrelated lease
/// registries.
public struct PinnedDropCopyPipeline: Sendable {
    public let dropPlanning: NativeDropPlanningAdapter
    public let fileCopying: PinnedSourceFileCopying

    public init(recoveryStore: any PendingCopyRecording) {
        let sourceLeases = SourceFileLeaseRegistry()
        self.dropPlanning = NativeDropPlanningAdapter(sourceLeases: sourceLeases)
        self.fileCopying = PinnedSourceFileCopying(
            recoveryStore: recoveryStore,
            sourceLeases: sourceLeases
        )
    }
}

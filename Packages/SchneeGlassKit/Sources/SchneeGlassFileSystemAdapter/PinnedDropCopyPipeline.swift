import SchneeGlassApplication

/// Canonical composition boundary for native Drop planning and pinned-source copying.
///
/// Planning and execution must share one `SourceFileLeaseRegistry`: authoritative planning pins the
/// exact source inode and binds it to each operation ID, execution consumes that same authority, and
/// hover preview reads only the shared capacity without acquiring descriptors. Creating the pair
/// here prevents callers from accidentally wiring planning and copying to unrelated lease registries.
public struct PinnedDropCopyPipeline: Sendable {
    public let dropPlanning: PinnedDropPlanningFacade
    public let fileCopying: PinnedSourceFileCopying

    public init(recoveryStore: any PendingCopyRecording) {
        let sourceLeases = SourceFileLeaseRegistry()
        let nativePlanning = NativeDropPlanningAdapter(sourceLeases: sourceLeases)
        self.dropPlanning = PinnedDropPlanningFacade(
            delegate: nativePlanning,
            sourceLeases: sourceLeases
        )
        self.fileCopying = PinnedSourceFileCopying(
            recoveryStore: recoveryStore,
            sourceLeases: sourceLeases
        )
    }
}

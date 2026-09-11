public struct GlassRuntimeSessionFactory: Sendable {
    private let eventStreaming: any FileEventStreaming
    private let snapshotReader: any FolderSnapshotReading
    private let accessController: any FolderAccessControlling
    private let dropPlanning: any DropPlanning & AuthorizedCopyBatchAbandoning
    private let fileCopying: any FileCopying

    public init(
        eventStreaming: any FileEventStreaming,
        snapshotReader: any FolderSnapshotReading,
        accessController: any FolderAccessControlling,
        dropPlanning: any DropPlanning & AuthorizedCopyBatchAbandoning,
        fileCopying: any FileCopying
    ) {
        self.eventStreaming = eventStreaming
        self.snapshotReader = snapshotReader
        self.accessController = accessController
        self.dropPlanning = dropPlanning
        self.fileCopying = fileCopying
    }

    public func makeSession(from seed: CreatedGlassRuntimeSeed) -> GlassRuntimeSession {
        GlassRuntimeSession(
            seed: seed,
            eventStreaming: eventStreaming,
            snapshotReader: snapshotReader,
            accessController: accessController,
            dropPlanning: dropPlanning,
            fileCopying: fileCopying
        )
    }
}

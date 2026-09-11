public struct GlassRuntimeSessionFactory: Sendable {
    private let eventStreaming: any FileEventStreaming
    private let snapshotReader: any FolderSnapshotReading
    private let accessController: any FolderAccessControlling
    private let dropPlanning: any DropPlanning
    private let copyAbandoner: any AuthorizedCopyBatchAbandoning
    private let fileCopying: any FileCopying

    public init(
        eventStreaming: any FileEventStreaming,
        snapshotReader: any FolderSnapshotReading,
        accessController: any FolderAccessControlling,
        dropPlanning: any DropPlanning,
        copyAbandoner: any AuthorizedCopyBatchAbandoning,
        fileCopying: any FileCopying
    ) {
        self.eventStreaming = eventStreaming
        self.snapshotReader = snapshotReader
        self.accessController = accessController
        self.dropPlanning = dropPlanning
        self.copyAbandoner = copyAbandoner
        self.fileCopying = fileCopying
    }

    public func makeSession(from seed: CreatedGlassRuntimeSeed) -> GlassRuntimeSession {
        GlassRuntimeSession(
            seed: seed,
            eventStreaming: eventStreaming,
            snapshotReader: snapshotReader,
            accessController: accessController,
            dropPlanning: dropPlanning,
            copyAbandoner: copyAbandoner,
            fileCopying: fileCopying
        )
    }
}

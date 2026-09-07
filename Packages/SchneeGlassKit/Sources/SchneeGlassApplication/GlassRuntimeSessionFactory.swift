public struct GlassRuntimeSessionFactory: Sendable {
    private let eventStreaming: any FileEventStreaming
    private let snapshotReader: any FolderSnapshotReading
    private let accessController: any FolderAccessControlling

    public init(
        eventStreaming: any FileEventStreaming,
        snapshotReader: any FolderSnapshotReading,
        accessController: any FolderAccessControlling
    ) {
        self.eventStreaming = eventStreaming
        self.snapshotReader = snapshotReader
        self.accessController = accessController
    }

    public func makeSession(from seed: CreatedGlassRuntimeSeed) -> GlassRuntimeSession {
        GlassRuntimeSession(
            seed: seed,
            eventStreaming: eventStreaming,
            snapshotReader: snapshotReader,
            accessController: accessController
        )
    }
}

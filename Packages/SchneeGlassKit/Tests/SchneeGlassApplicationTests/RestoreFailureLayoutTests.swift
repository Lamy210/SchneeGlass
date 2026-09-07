import FileDomain
import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing

private actor LayoutRestoreConfigurationStore: ConfigurationPersisting {
    let configurations: [GlassConfiguration]

    init(configurations: [GlassConfiguration]) {
        self.configurations = configurations
    }

    func load() async throws -> [GlassConfiguration] {
        configurations
    }

    func save(_ configurations: [GlassConfiguration]) async throws {}
}

private actor LayoutRestoreFailingAccessController: FolderAccessControlling {
    let error: FolderAccessError

    init(error: FolderAccessError) {
        self.error = error
    }

    func acquire(
        source: FolderSource,
        glassID: GlassID
    ) async throws -> FolderAccessAcquisition {
        throw error
    }

    func release(handleID: UUID) async {}
}

private actor LayoutRestoreUnusedEventStream: FileEventStreaming {
    func subscribe(for access: FolderAccessHandle) async throws -> FileEventSubscription {
        Issue.record("Event stream must not start when folder access fails")
        return FileEventSubscription(events: AsyncStream { continuation in
            continuation.finish()
        })
    }

    func stop(subscriptionID: UUID) async {}
}

private actor LayoutRestoreUnusedSnapshotReader: FolderSnapshotReading {
    func snapshot(
        for access: FolderAccessHandle,
        generation: UInt64
    ) async throws -> FolderSnapshot {
        Issue.record("Snapshot must not run when folder access fails")
        return FolderSnapshot(
            folderIdentity: FolderIdentity(resourceIdentifier: nil, standardizedURL: access.url),
            items: [],
            isTruncated: false,
            generation: generation
        )
    }
}

@Test
func restoreFailurePreservesPlacementAndSpaceBehavior() async throws {
    let placement = try GlassPlacement(
        x: 3120,
        y: 240,
        width: 420,
        height: 300,
        displayHint: "External Display"
    )
    let configuration = try GlassConfiguration(
        title: "Offline Project",
        source: FolderSource(
            bookmarkData: Data([1, 2, 3]),
            lastKnownPath: "/Volumes/Work/Offline Project"
        ),
        placement: placement,
        showOnAllSpaces: true,
        createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    let useCase = RestoreApplicationUseCase(
        configurationStore: LayoutRestoreConfigurationStore(configurations: [configuration]),
        accessController: LayoutRestoreFailingAccessController(error: .bookmarkResolutionFailed),
        eventStreaming: LayoutRestoreUnusedEventStream(),
        snapshotReader: LayoutRestoreUnusedSnapshotReader()
    )

    let result = try await useCase.execute()

    #expect(result.seeds.isEmpty)
    #expect(result.failures.count == 1)
    #expect(result.failures[0].glassID == configuration.id)
    #expect(result.failures[0].placement == placement)
    #expect(result.failures[0].showOnAllSpaces)
    #expect(result.failures[0].reason == .folderAccess(.bookmarkResolutionFailed))
}

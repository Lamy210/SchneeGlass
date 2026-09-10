import Foundation
@testable import SchneeGlassApplication
import SchneeGlassDomain
import Testing

private enum ConfigurationRecoveryProviderTestError: Error, Hashable, Sendable {
    case injected
}

private actor ConfigurationRecoveryStoreSpy: ConfigurationRecoveryProviding, ConfigurationPersisting {
    private let backups: [ConfigurationBackupDescriptor]
    private let restoredConfigurations: [GlassConfiguration]
    private let currentConfigurations: [GlassConfiguration]
    private let failListing: Bool
    private let failRestore: Bool
    private let failLoad: Bool
    private var restoredIDs: [String] = []
    private var loadCount = 0

    init(
        backups: [ConfigurationBackupDescriptor] = [],
        restoredConfigurations: [GlassConfiguration] = [],
        currentConfigurations: [GlassConfiguration] = [],
        failListing: Bool = false,
        failRestore: Bool = false,
        failLoad: Bool = false
    ) {
        self.backups = backups
        self.restoredConfigurations = restoredConfigurations
        self.currentConfigurations = currentConfigurations
        self.failListing = failListing
        self.failRestore = failRestore
        self.failLoad = failLoad
    }

    func availableBackups() async throws -> [ConfigurationBackupDescriptor] {
        if failListing {
            throw ConfigurationRecoveryProviderTestError.injected
        }
        return backups
    }

    func restoreBackup(id: String) async throws -> [GlassConfiguration] {
        restoredIDs.append(id)
        if failRestore {
            throw ConfigurationRecoveryProviderTestError.injected
        }
        return restoredConfigurations
    }

    func load() async throws -> [GlassConfiguration] {
        loadCount += 1
        if failLoad {
            throw ConfigurationRecoveryProviderTestError.injected
        }
        return currentConfigurations
    }

    func save(_ configurations: [GlassConfiguration]) async throws {
        _ = configurations
    }

    func requestedRestoreIDs() -> [String] {
        restoredIDs
    }

    func currentLoadCount() -> Int {
        loadCount
    }
}

private actor ConfigurationRecoveryPendingCopyStore: PendingCopyRecording {
    private let loaded: [PendingCopyRecord]
    private let failLoad: Bool
    private var readCount = 0

    init(
        loaded: [PendingCopyRecord] = [],
        failLoad: Bool = false
    ) {
        self.loaded = loaded
        self.failLoad = failLoad
    }

    func records() async throws -> [PendingCopyRecord] {
        readCount += 1
        if failLoad {
            throw ConfigurationRecoveryProviderTestError.injected
        }
        return loaded
    }

    func upsert(_ record: PendingCopyRecord) async throws {
        _ = record
    }

    func remove(operationID: UUID) async throws {
        _ = operationID
    }

    func reads() -> Int {
        readCount
    }
}

private func configurationRecoveryGlass(
    id: GlassID = GlassID(),
    title: String = "Recovery Glass"
) throws -> GlassConfiguration {
    try GlassConfiguration(
        id: id,
        title: title,
        source: FolderSource(
            bookmarkData: Data([1, 2, 3]),
            lastKnownPath: "/tmp/\(title)"
        ),
        placement: GlassPlacement(x: 100, y: 120),
        createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
}

private func configurationRecoveryPendingRecord(glassID: GlassID) -> PendingCopyRecord {
    let operationID = UUID()
    return PendingCopyRecord(
        operationID: operationID,
        batchID: UUID(),
        destinationGlassID: glassID,
        stagingFilename: ".schneeglass-copy-\(operationID.uuidString.lowercased()).partial",
        finalFilename: "payload.txt",
        expectedSize: 7,
        stagingResourceIdentifier: "xattr-v1:\(UUID().uuidString.lowercased())",
        state: .verifying
    )
}

@Test
func configurationRecoveryListsBackupsWithoutReadingCurrentOrPendingCopies() async throws {
    let newer = ConfigurationBackupDescriptor(
        id: "backup-newer.json",
        createdAt: Date(timeIntervalSince1970: 2_000)
    )
    let older = ConfigurationBackupDescriptor(
        id: "backup-older.json",
        createdAt: Date(timeIntervalSince1970: 1_000)
    )
    let store = ConfigurationRecoveryStoreSpy(
        backups: [newer, older],
        failLoad: true
    )
    let pendingCopyStore = ConfigurationRecoveryPendingCopyStore(failLoad: true)
    let useCase = ConfigurationRecoveryUseCase(
        recoveryStore: store,
        pendingCopyStore: pendingCopyStore
    )

    let result = try await useCase.availableBackups()

    #expect(result == [newer, older])
    #expect(await store.currentLoadCount() == 0)
    #expect(await pendingCopyStore.reads() == 0)
}

@Test
func configurationRecoveryRestoresExactlyRequestedBackupWhenNoPendingCopyExists() async throws {
    let store = ConfigurationRecoveryStoreSpy(failLoad: true)
    let pendingCopyStore = ConfigurationRecoveryPendingCopyStore()
    let useCase = ConfigurationRecoveryUseCase(
        recoveryStore: store,
        pendingCopyStore: pendingCopyStore
    )

    let result = try await useCase.restoreBackup(id: "backup-selected.json")

    #expect(result.isEmpty)
    #expect(await pendingCopyStore.reads() == 1)
    #expect(await store.currentLoadCount() == 0)
    #expect(await store.requestedRestoreIDs() == ["backup-selected.json"])
}

@Test
func configurationRecoveryPropagatesListingFailureWithoutReadingRecoveryState() async {
    let store = ConfigurationRecoveryStoreSpy(
        failListing: true,
        failLoad: true
    )
    let pendingCopyStore = ConfigurationRecoveryPendingCopyStore(failLoad: true)
    let useCase = ConfigurationRecoveryUseCase(
        recoveryStore: store,
        pendingCopyStore: pendingCopyStore
    )

    do {
        _ = try await useCase.availableBackups()
        Issue.record("Expected listing failure")
    } catch let error as ConfigurationRecoveryProviderTestError {
        #expect(error == .injected)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(await store.currentLoadCount() == 0)
    #expect(await pendingCopyStore.reads() == 0)
}

@Test
func configurationRecoveryFailsClosedWhenPendingCopyMetadataCannotBeLoaded() async {
    let store = ConfigurationRecoveryStoreSpy()
    let pendingCopyStore = ConfigurationRecoveryPendingCopyStore(failLoad: true)
    let useCase = ConfigurationRecoveryUseCase(
        recoveryStore: store,
        pendingCopyStore: pendingCopyStore
    )

    do {
        _ = try await useCase.restoreBackup(id: "backup-selected.json")
        Issue.record("Expected pending-copy load failure")
    } catch let error as ConfigurationRecoveryUseCaseError {
        #expect(error == .pendingCopyLoadFailed)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(await store.currentLoadCount() == 0)
    #expect(await store.requestedRestoreIDs().isEmpty)
}

@Test
func configurationRecoveryPreservesLivePendingCopyGlassMapping() async throws {
    let pendingGlassID = GlassID()
    let current = try configurationRecoveryGlass(id: pendingGlassID)
    let store = ConfigurationRecoveryStoreSpy(currentConfigurations: [current])
    let pendingCopyStore = ConfigurationRecoveryPendingCopyStore(
        loaded: [configurationRecoveryPendingRecord(glassID: pendingGlassID)]
    )
    let useCase = ConfigurationRecoveryUseCase(
        recoveryStore: store,
        pendingCopyStore: pendingCopyStore
    )

    do {
        _ = try await useCase.restoreBackup(id: "backup-selected.json")
        Issue.record("Expected pending-copy recovery requirement")
    } catch let error as ConfigurationRecoveryUseCaseError {
        #expect(error == .pendingCopyRecoveryRequired)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(await pendingCopyStore.reads() == 1)
    #expect(await store.currentLoadCount() == 1)
    #expect(await store.requestedRestoreIDs().isEmpty)
}

@Test
func configurationRecoveryAllowsRestoreWhenPendingGlassMappingIsAlreadyMissing() async throws {
    let pendingGlassID = GlassID()
    let unrelated = try configurationRecoveryGlass(title: "Unrelated")
    let store = ConfigurationRecoveryStoreSpy(currentConfigurations: [unrelated])
    let pendingCopyStore = ConfigurationRecoveryPendingCopyStore(
        loaded: [configurationRecoveryPendingRecord(glassID: pendingGlassID)]
    )
    let useCase = ConfigurationRecoveryUseCase(
        recoveryStore: store,
        pendingCopyStore: pendingCopyStore
    )

    _ = try await useCase.restoreBackup(id: "backup-selected.json")

    #expect(await pendingCopyStore.reads() == 1)
    #expect(await store.currentLoadCount() == 1)
    #expect(await store.requestedRestoreIDs() == ["backup-selected.json"])
}

@Test
func configurationRecoveryAllowsExplicitRestoreWhenCurrentConfigurationIsUnreadable() async throws {
    let pendingGlassID = GlassID()
    let store = ConfigurationRecoveryStoreSpy(failLoad: true)
    let pendingCopyStore = ConfigurationRecoveryPendingCopyStore(
        loaded: [configurationRecoveryPendingRecord(glassID: pendingGlassID)]
    )
    let useCase = ConfigurationRecoveryUseCase(
        recoveryStore: store,
        pendingCopyStore: pendingCopyStore
    )

    _ = try await useCase.restoreBackup(id: "backup-selected.json")

    #expect(await pendingCopyStore.reads() == 1)
    #expect(await store.currentLoadCount() == 1)
    #expect(await store.requestedRestoreIDs() == ["backup-selected.json"])
}

@Test
func configurationRecoveryPropagatesRestoreFailureAfterPendingCopyCheck() async {
    let store = ConfigurationRecoveryStoreSpy(
        failRestore: true,
        failLoad: true
    )
    let pendingCopyStore = ConfigurationRecoveryPendingCopyStore()
    let useCase = ConfigurationRecoveryUseCase(
        recoveryStore: store,
        pendingCopyStore: pendingCopyStore
    )

    do {
        _ = try await useCase.restoreBackup(id: "backup-failing.json")
        Issue.record("Expected restore failure")
    } catch let error as ConfigurationRecoveryProviderTestError {
        #expect(error == .injected)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(await pendingCopyStore.reads() == 1)
    #expect(await store.currentLoadCount() == 0)
    #expect(await store.requestedRestoreIDs() == ["backup-failing.json"])
}

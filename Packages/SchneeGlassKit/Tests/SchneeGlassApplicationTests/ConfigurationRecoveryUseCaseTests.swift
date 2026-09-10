import Foundation
@testable import SchneeGlassApplication
import SchneeGlassDomain
import Testing

private enum ConfigurationRecoveryProviderTestError: Error, Hashable, Sendable {
    case injected
}

private actor ConfigurationRecoveryProviderSpy: ConfigurationRecoveryProviding {
    private let backups: [ConfigurationBackupDescriptor]
    private let restoredConfigurations: [GlassConfiguration]
    private let failListing: Bool
    private let failRestore: Bool
    private var restoredIDs: [String] = []

    init(
        backups: [ConfigurationBackupDescriptor] = [],
        restoredConfigurations: [GlassConfiguration] = [],
        failListing: Bool = false,
        failRestore: Bool = false
    ) {
        self.backups = backups
        self.restoredConfigurations = restoredConfigurations
        self.failListing = failListing
        self.failRestore = failRestore
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

    func requestedRestoreIDs() -> [String] {
        restoredIDs
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

private func configurationRecoveryPendingRecord() -> PendingCopyRecord {
    let operationID = UUID()
    return PendingCopyRecord(
        operationID: operationID,
        batchID: UUID(),
        destinationGlassID: GlassID(),
        stagingFilename: ".schneeglass-copy-\(operationID.uuidString.lowercased()).partial",
        finalFilename: "payload.txt",
        expectedSize: 7,
        stagingResourceIdentifier: "xattr-v1:\(UUID().uuidString.lowercased())",
        state: .verifying
    )
}

@Test
func configurationRecoveryListsBackupsWithoutReorderingOrReadingPendingCopies() async throws {
    let newer = ConfigurationBackupDescriptor(
        id: "backup-newer.json",
        createdAt: Date(timeIntervalSince1970: 2_000)
    )
    let older = ConfigurationBackupDescriptor(
        id: "backup-older.json",
        createdAt: Date(timeIntervalSince1970: 1_000)
    )
    let provider = ConfigurationRecoveryProviderSpy(backups: [newer, older])
    let pendingCopyStore = ConfigurationRecoveryPendingCopyStore(failLoad: true)
    let useCase = ConfigurationRecoveryUseCase(
        recoveryProvider: provider,
        pendingCopyStore: pendingCopyStore
    )

    let result = try await useCase.availableBackups()

    #expect(result == [newer, older])
    #expect(await pendingCopyStore.reads() == 0)
}

@Test
func configurationRecoveryRestoresExactlyRequestedBackupWhenNoPendingCopyExists() async throws {
    let provider = ConfigurationRecoveryProviderSpy()
    let pendingCopyStore = ConfigurationRecoveryPendingCopyStore()
    let useCase = ConfigurationRecoveryUseCase(
        recoveryProvider: provider,
        pendingCopyStore: pendingCopyStore
    )

    let result = try await useCase.restoreBackup(id: "backup-selected.json")

    #expect(result.isEmpty)
    #expect(await pendingCopyStore.reads() == 1)
    #expect(await provider.requestedRestoreIDs() == ["backup-selected.json"])
}

@Test
func configurationRecoveryPropagatesListingFailureWithoutReadingPendingCopies() async {
    let provider = ConfigurationRecoveryProviderSpy(failListing: true)
    let pendingCopyStore = ConfigurationRecoveryPendingCopyStore(failLoad: true)
    let useCase = ConfigurationRecoveryUseCase(
        recoveryProvider: provider,
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

    #expect(await pendingCopyStore.reads() == 0)
}

@Test
func configurationRecoveryFailsClosedWhenPendingCopyMetadataCannotBeLoaded() async {
    let provider = ConfigurationRecoveryProviderSpy()
    let pendingCopyStore = ConfigurationRecoveryPendingCopyStore(failLoad: true)
    let useCase = ConfigurationRecoveryUseCase(
        recoveryProvider: provider,
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

    #expect(await provider.requestedRestoreIDs().isEmpty)
}

@Test
func configurationRecoveryRefusesRestoreWhileAnyPendingCopyExists() async {
    let provider = ConfigurationRecoveryProviderSpy()
    let pendingCopyStore = ConfigurationRecoveryPendingCopyStore(
        loaded: [configurationRecoveryPendingRecord()]
    )
    let useCase = ConfigurationRecoveryUseCase(
        recoveryProvider: provider,
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
    #expect(await provider.requestedRestoreIDs().isEmpty)
}

@Test
func configurationRecoveryPropagatesRestoreFailureAfterPendingCopyCheck() async {
    let provider = ConfigurationRecoveryProviderSpy(failRestore: true)
    let pendingCopyStore = ConfigurationRecoveryPendingCopyStore()
    let useCase = ConfigurationRecoveryUseCase(
        recoveryProvider: provider,
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
    #expect(await provider.requestedRestoreIDs() == ["backup-failing.json"])
}

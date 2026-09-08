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

@Test
func configurationRecoveryListsBackupsWithoutReordering() async throws {
    let newer = ConfigurationBackupDescriptor(
        id: "backup-newer.json",
        createdAt: Date(timeIntervalSince1970: 2_000)
    )
    let older = ConfigurationBackupDescriptor(
        id: "backup-older.json",
        createdAt: Date(timeIntervalSince1970: 1_000)
    )
    let provider = ConfigurationRecoveryProviderSpy(backups: [newer, older])
    let useCase = ConfigurationRecoveryUseCase(recoveryProvider: provider)

    let result = try await useCase.availableBackups()

    #expect(result == [newer, older])
}

@Test
func configurationRecoveryRestoresExactlyRequestedBackup() async throws {
    let provider = ConfigurationRecoveryProviderSpy()
    let useCase = ConfigurationRecoveryUseCase(recoveryProvider: provider)

    let result = try await useCase.restoreBackup(id: "backup-selected.json")

    #expect(result.isEmpty)
    #expect(await provider.requestedRestoreIDs() == ["backup-selected.json"])
}

@Test
func configurationRecoveryPropagatesListingFailure() async {
    let provider = ConfigurationRecoveryProviderSpy(failListing: true)
    let useCase = ConfigurationRecoveryUseCase(recoveryProvider: provider)

    do {
        _ = try await useCase.availableBackups()
        Issue.record("Expected listing failure")
    } catch let error as ConfigurationRecoveryProviderTestError {
        #expect(error == .injected)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test
func configurationRecoveryPropagatesRestoreFailureForRequestedBackup() async {
    let provider = ConfigurationRecoveryProviderSpy(failRestore: true)
    let useCase = ConfigurationRecoveryUseCase(recoveryProvider: provider)

    do {
        _ = try await useCase.restoreBackup(id: "backup-failing.json")
        Issue.record("Expected restore failure")
    } catch let error as ConfigurationRecoveryProviderTestError {
        #expect(error == .injected)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(await provider.requestedRestoreIDs() == ["backup-failing.json"])
}

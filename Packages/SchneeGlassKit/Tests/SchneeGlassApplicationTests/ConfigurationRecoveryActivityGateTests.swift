import Foundation
@testable import SchneeGlassApplication
import SchneeGlassDomain
import Testing

private actor GatedConfigurationRecoveryStore: ConfigurationRecoveryProviding, ConfigurationPersisting {
    enum Failure: Error {
        case injected
    }

    private let blocksRestore: Bool
    private let failsRestore: Bool
    private var restoreStarted = false
    private var restoreContinuation: CheckedContinuation<Void, Never>?
    private var restoreCount = 0

    init(blocksRestore: Bool = false, failsRestore: Bool = false) {
        self.blocksRestore = blocksRestore
        self.failsRestore = failsRestore
    }

    func availableBackups() async throws -> [ConfigurationBackupDescriptor] {
        []
    }

    func load() async throws -> [GlassConfiguration] {
        []
    }

    func save(_ configurations: [GlassConfiguration]) async throws {
        _ = configurations
    }

    func restoreBackup(id: String) async throws -> [GlassConfiguration] {
        _ = id
        restoreCount += 1
        restoreStarted = true

        if blocksRestore {
            await withCheckedContinuation { continuation in
                restoreContinuation = continuation
            }
        }
        if failsRestore {
            throw Failure.injected
        }
        return []
    }

    func waitUntilRestoreStarts() async {
        while !restoreStarted {
            await Task.yield()
        }
    }

    func finishRestore() {
        restoreContinuation?.resume()
        restoreContinuation = nil
    }

    func restores() -> Int {
        restoreCount
    }
}

private actor GatedConfigurationRecoveryPendingCopyStore: PendingCopyRecording {
    private var readCount = 0

    func records() async throws -> [PendingCopyRecord] {
        readCount += 1
        return []
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

@Test
func configurationRecoveryRejectsBeforeStateReadsWhileCopyIsActive() async {
    let gate = FileOperationActivityGate()
    let store = GatedConfigurationRecoveryStore()
    let pending = GatedConfigurationRecoveryPendingCopyStore()
    let useCase = ConfigurationRecoveryUseCase(
        recoveryStore: store,
        pendingCopyStore: pending,
        activityGate: gate
    )

    #expect(await gate.beginCopy())

    do {
        _ = try await useCase.restoreBackup(id: "blocked-by-copy")
        Issue.record("Expected active copy to reject configuration restore")
    } catch let error as ConfigurationRecoveryUseCaseError {
        #expect(error == .copyInProgress)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(await pending.reads() == 0)
    #expect(await store.restores() == 0)
    await gate.endCopy()
}

@Test
func configurationRecoveryRejectsBeforeStateReadsWhileRecoveryMutationIsActive() async {
    let gate = FileOperationActivityGate()
    let store = GatedConfigurationRecoveryStore()
    let pending = GatedConfigurationRecoveryPendingCopyStore()
    let useCase = ConfigurationRecoveryUseCase(
        recoveryStore: store,
        pendingCopyStore: pending,
        activityGate: gate
    )

    #expect(await gate.beginRecoveryMutation() == .granted)

    do {
        _ = try await useCase.restoreBackup(id: "blocked-by-recovery")
        Issue.record("Expected active Recovery mutation to reject configuration restore")
    } catch let error as ConfigurationRecoveryUseCaseError {
        #expect(error == .recoveryInProgress)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(await pending.reads() == 0)
    #expect(await store.restores() == 0)
    await gate.endRecoveryMutation()
}

@Test
func configurationRecoveryHoldsSharedGateUntilRestoreCompletes() async throws {
    let gate = FileOperationActivityGate()
    let store = GatedConfigurationRecoveryStore(blocksRestore: true)
    let pending = GatedConfigurationRecoveryPendingCopyStore()
    let useCase = ConfigurationRecoveryUseCase(
        recoveryStore: store,
        pendingCopyStore: pending,
        activityGate: gate
    )

    let restoreTask = Task {
        try await useCase.restoreBackup(id: "blocking-restore")
    }
    await store.waitUntilRestoreStarts()

    #expect(!(await gate.beginCopy()))
    #expect(await gate.beginRecoveryMutation() == .recoveryInProgress)

    await store.finishRestore()
    _ = try await restoreTask.value

    #expect(await gate.beginCopy())
    await gate.endCopy()
    #expect(await gate.beginRecoveryMutation() == .granted)
    await gate.endRecoveryMutation()
}

@Test
func configurationRecoveryReleasesSharedGateAfterRestoreFailure() async {
    let gate = FileOperationActivityGate()
    let store = GatedConfigurationRecoveryStore(failsRestore: true)
    let pending = GatedConfigurationRecoveryPendingCopyStore()
    let useCase = ConfigurationRecoveryUseCase(
        recoveryStore: store,
        pendingCopyStore: pending,
        activityGate: gate
    )

    do {
        _ = try await useCase.restoreBackup(id: "failing-restore")
        Issue.record("Expected injected restore failure")
    } catch {
        // The specific persistence error is not part of the activity-gate contract.
    }

    #expect(await gate.beginCopy())
    await gate.endCopy()
}

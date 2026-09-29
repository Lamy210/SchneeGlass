import Foundation
import SchneeGlassDomain
import Testing

@testable import SchneeGlassApplication

private enum ConfigurationRecoveryCancellationStage: Sendable {
  case none
  case loadThrow
  case loadCancelAndReturn
  case restoreThrow
  case restoreCancelAndReturn
}

private actor CancellationConfigurationRecoveryStore:
  ConfigurationRecoveryProviding, ConfigurationPersisting
{
  private let current: [GlassConfiguration]
  private let restored: [GlassConfiguration]
  private let stage: ConfigurationRecoveryCancellationStage
  private var loadCount = 0
  private var restoreCount = 0

  init(
    current: [GlassConfiguration] = [],
    restored: [GlassConfiguration] = [],
    stage: ConfigurationRecoveryCancellationStage = .none
  ) {
    self.current = current
    self.restored = restored
    self.stage = stage
  }

  func availableBackups() async throws -> [ConfigurationBackupDescriptor] {
    []
  }

  func restoreBackup(id: String) async throws -> [GlassConfiguration] {
    _ = id
    restoreCount += 1

    switch stage {
    case .restoreThrow:
      throw CancellationError()
    case .restoreCancelAndReturn:
      withUnsafeCurrentTask { task in
        task?.cancel()
      }
      return restored
    case .none, .loadThrow, .loadCancelAndReturn:
      return restored
    }
  }

  func load() async throws -> [GlassConfiguration] {
    loadCount += 1

    switch stage {
    case .loadThrow:
      throw CancellationError()
    case .loadCancelAndReturn:
      withUnsafeCurrentTask { task in
        task?.cancel()
      }
      return current
    case .none, .restoreThrow, .restoreCancelAndReturn:
      return current
    }
  }

  func save(_ configurations: [GlassConfiguration]) async throws {
    _ = configurations
  }

  func counts() -> (loads: Int, restores: Int) {
    (loadCount, restoreCount)
  }
}

private enum PendingCopyCancellationStage: Sendable {
  case none
  case throwCancellation
  case cancelAndReturn
}

private actor CancellationRecoveryPendingCopyStore: PendingCopyRecording {
  private let values: [PendingCopyRecord]
  private let stage: PendingCopyCancellationStage
  private var readCount = 0

  init(
    values: [PendingCopyRecord] = [],
    stage: PendingCopyCancellationStage = .none
  ) {
    self.values = values
    self.stage = stage
  }

  func records() async throws -> [PendingCopyRecord] {
    readCount += 1

    switch stage {
    case .throwCancellation:
      throw CancellationError()
    case .cancelAndReturn:
      withUnsafeCurrentTask { task in
        task?.cancel()
      }
      return values
    case .none:
      return values
    }
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

private func cancellationRecoveryGlass(
  id: GlassID = GlassID()
) throws -> GlassConfiguration {
  try GlassConfiguration(
    id: id,
    title: "Recovery Target",
    source: FolderSource(
      bookmarkData: Data([1]),
      lastKnownPath: "/tmp/RecoveryTarget"
    ),
    placement: GlassPlacement(x: 100, y: 120)
  )
}

private func cancellationRecoveryRecord(
  glassID: GlassID
) -> PendingCopyRecord {
  let operationID = UUID()
  return PendingCopyRecord(
    operationID: operationID,
    batchID: UUID(),
    destinationGlassID: glassID,
    stagingFilename: ".schneeglass-copy-\(operationID.uuidString.lowercased()).partial",
    finalFilename: "payload.txt",
    expectedSize: 7,
    stagingResourceIdentifier: "recovery-cancellation",
    state: .verifying
  )
}

private func assertRecoveryGateReleased(
  _ gate: FileOperationActivityGate
) async {
  #expect(await gate.beginRecoveryMutation() == .granted)
  await gate.endRecoveryMutation()
}

@Test
func preCancelledConfigurationRecoveryDoesNotAcquireOrReadState() async {
  let gate = FileOperationActivityGate()
  let store = CancellationConfigurationRecoveryStore()
  let pending = CancellationRecoveryPendingCopyStore()
  let useCase = ConfigurationRecoveryUseCase(
    recoveryStore: store,
    pendingCopyStore: pending,
    activityGate: gate
  )

  let task = Task {
    withUnsafeCurrentTask { current in
      current?.cancel()
    }
    return try await useCase.restoreBackup(id: "backup.json")
  }

  do {
    _ = try await task.value
    Issue.record("Expected configuration recovery cancellation")
  } catch is CancellationError {
  } catch {
    Issue.record("Expected CancellationError, got \(error)")
  }

  #expect(await pending.reads() == 0)
  #expect(await store.counts().loads == 0)
  #expect(await store.counts().restores == 0)
  await assertRecoveryGateReleased(gate)
}

@Test
func pendingCopyCancellationPropagatesAndReleasesRecoveryLease() async {
  let gate = FileOperationActivityGate()
  let store = CancellationConfigurationRecoveryStore()
  let pending = CancellationRecoveryPendingCopyStore(stage: .throwCancellation)
  let useCase = ConfigurationRecoveryUseCase(
    recoveryStore: store,
    pendingCopyStore: pending,
    activityGate: gate
  )

  do {
    _ = try await useCase.restoreBackup(id: "backup.json")
    Issue.record("Expected configuration recovery cancellation")
  } catch is CancellationError {
  } catch {
    Issue.record("Expected CancellationError, got \(error)")
  }

  #expect(await pending.reads() == 1)
  #expect(await store.counts().restores == 0)
  await assertRecoveryGateReleased(gate)
}

@Test
func cancellationObservedAfterPendingCopyReadStopsBeforeRestore() async {
  let gate = FileOperationActivityGate()
  let store = CancellationConfigurationRecoveryStore()
  let pending = CancellationRecoveryPendingCopyStore(stage: .cancelAndReturn)
  let useCase = ConfigurationRecoveryUseCase(
    recoveryStore: store,
    pendingCopyStore: pending,
    activityGate: gate
  )

  do {
    _ = try await useCase.restoreBackup(id: "backup.json")
    Issue.record("Expected configuration recovery cancellation")
  } catch is CancellationError {
  } catch {
    Issue.record("Expected CancellationError, got \(error)")
  }

  #expect(await store.counts().loads == 0)
  #expect(await store.counts().restores == 0)
  await assertRecoveryGateReleased(gate)
}

@Test
func currentConfigurationCancellationNeverFallsBackToBackupRestore() async throws {
  let glassID = GlassID()
  let record = cancellationRecoveryRecord(glassID: glassID)
  let gate = FileOperationActivityGate()
  let store = CancellationConfigurationRecoveryStore(stage: .loadThrow)
  let pending = CancellationRecoveryPendingCopyStore(values: [record])
  let useCase = ConfigurationRecoveryUseCase(
    recoveryStore: store,
    pendingCopyStore: pending,
    activityGate: gate
  )

  do {
    _ = try await useCase.restoreBackup(id: "backup.json")
    Issue.record("Expected configuration recovery cancellation")
  } catch is CancellationError {
  } catch {
    Issue.record("Expected CancellationError, got \(error)")
  }

  #expect(await store.counts().loads == 1)
  #expect(await store.counts().restores == 0)
  await assertRecoveryGateReleased(gate)
}

@Test
func cancellationObservedAfterCurrentConfigurationReadNeverRestoresBackup() async throws {
  let glassID = GlassID()
  let current = try cancellationRecoveryGlass(id: glassID)
  let record = cancellationRecoveryRecord(glassID: GlassID())
  let gate = FileOperationActivityGate()
  let store = CancellationConfigurationRecoveryStore(
    current: [current],
    stage: .loadCancelAndReturn
  )
  let pending = CancellationRecoveryPendingCopyStore(values: [record])
  let useCase = ConfigurationRecoveryUseCase(
    recoveryStore: store,
    pendingCopyStore: pending,
    activityGate: gate
  )

  do {
    _ = try await useCase.restoreBackup(id: "backup.json")
    Issue.record("Expected configuration recovery cancellation")
  } catch is CancellationError {
  } catch {
    Issue.record("Expected CancellationError, got \(error)")
  }

  #expect(await store.counts().loads == 1)
  #expect(await store.counts().restores == 0)
  await assertRecoveryGateReleased(gate)
}

@Test
func backupRestoreCancellationPropagatesAndReleasesRecoveryLease() async {
  let gate = FileOperationActivityGate()
  let store = CancellationConfigurationRecoveryStore(stage: .restoreThrow)
  let pending = CancellationRecoveryPendingCopyStore()
  let useCase = ConfigurationRecoveryUseCase(
    recoveryStore: store,
    pendingCopyStore: pending,
    activityGate: gate
  )

  do {
    _ = try await useCase.restoreBackup(id: "backup.json")
    Issue.record("Expected configuration recovery cancellation")
  } catch is CancellationError {
  } catch {
    Issue.record("Expected CancellationError, got \(error)")
  }

  #expect(await store.counts().restores == 1)
  await assertRecoveryGateReleased(gate)
}

@Test
func successfulBackupRestoreRemainsCommitPointAfterLateCancellation() async throws {
  let restored = try cancellationRecoveryGlass()
  let gate = FileOperationActivityGate()
  let store = CancellationConfigurationRecoveryStore(
    restored: [restored],
    stage: .restoreCancelAndReturn
  )
  let pending = CancellationRecoveryPendingCopyStore()
  let useCase = ConfigurationRecoveryUseCase(
    recoveryStore: store,
    pendingCopyStore: pending,
    activityGate: gate
  )

  let result = try await useCase.restoreBackup(id: "backup.json")

  #expect(result == [restored])
  #expect(await store.counts().restores == 1)
  await assertRecoveryGateReleased(gate)
}

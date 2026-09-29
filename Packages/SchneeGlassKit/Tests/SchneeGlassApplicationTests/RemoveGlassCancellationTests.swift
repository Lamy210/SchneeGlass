import FileDomain
import Foundation
import SchneeGlassDomain
import Testing

@testable import SchneeGlassApplication

private enum RemoveCancellationStage: Sendable {
  case none
  case load
  case save
  case cancelAfterSaveSuccess
}

private actor RemoveCancellationConfigurationStore: ConditionalConfigurationPersisting {
  let configurations: [GlassConfiguration]
  let stage: RemoveCancellationStage
  private var loadCount = 0
  private var saveCount = 0

  init(
    configurations: [GlassConfiguration],
    stage: RemoveCancellationStage = .none
  ) {
    self.configurations = configurations
    self.stage = stage
  }

  func load() async throws -> [GlassConfiguration] {
    loadCount += 1
    if stage == .load {
      throw CancellationError()
    }
    return configurations
  }

  func save(_ configurations: [GlassConfiguration]) async throws {
    _ = configurations
  }

  func save(
    _ configurations: [GlassConfiguration],
    ifCurrentMatches expectedCurrent: [GlassConfiguration]
  ) async throws -> Bool {
    _ = configurations
    _ = expectedCurrent
    saveCount += 1

    switch stage {
    case .save:
      throw CancellationError()
    case .cancelAfterSaveSuccess:
      withUnsafeCurrentTask { task in
        task?.cancel()
      }
      return true
    case .none, .load:
      return true
    }
  }

  func counts() -> (loads: Int, saves: Int) {
    (loadCount, saveCount)
  }
}

private actor RemoveCancellationPendingCopyStore: PendingCopyRecording {
  let cancelRead: Bool
  private var readCount = 0

  init(cancelRead: Bool = false) {
    self.cancelRead = cancelRead
  }

  func records() async throws -> [PendingCopyRecord] {
    readCount += 1
    if cancelRead {
      throw CancellationError()
    }
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

private func removeCancellationConfiguration(
  id: GlassID = GlassID()
) throws -> GlassConfiguration {
  try GlassConfiguration(
    id: id,
    title: "Removal Target",
    source: FolderSource(
      bookmarkData: Data([1, 2, 3]),
      lastKnownPath: "/tmp/removal-target"
    ),
    placement: GlassPlacement(x: 100, y: 120),
    createdAt: Date(timeIntervalSince1970: 1_700_000_000)
  )
}

@Test
func preCancelledRemoveDoesNotReadConfiguration() async throws {
  let configuration = try removeCancellationConfiguration()
  let store = RemoveCancellationConfigurationStore(
    configurations: [configuration]
  )
  let pendingStore = RemoveCancellationPendingCopyStore()
  let useCase = RemoveGlassUseCase(
    configurationStore: store,
    pendingCopyStore: pendingStore
  )

  let task = Task {
    try await useCase.execute(glassID: configuration.id)
  }
  task.cancel()

  do {
    _ = try await task.value
    Issue.record("Expected remove cancellation")
  } catch is CancellationError {
  } catch {
    Issue.record("Expected CancellationError, got \(error)")
  }

  #expect(await store.counts().loads == 0)
  #expect(await pendingStore.reads() == 0)
}

@Test
func removeConfigurationLoadCancellationPropagatesBeforeRecoveryRead() async throws {
  let configuration = try removeCancellationConfiguration()
  let store = RemoveCancellationConfigurationStore(
    configurations: [configuration],
    stage: .load
  )
  let pendingStore = RemoveCancellationPendingCopyStore()
  let useCase = RemoveGlassUseCase(
    configurationStore: store,
    pendingCopyStore: pendingStore
  )

  do {
    _ = try await useCase.execute(glassID: configuration.id)
    Issue.record("Expected remove cancellation")
  } catch is CancellationError {
  } catch {
    Issue.record("Expected CancellationError, got \(error)")
  }

  #expect(await store.counts().loads == 1)
  #expect(await store.counts().saves == 0)
  #expect(await pendingStore.reads() == 0)
}

@Test
func removePendingRecoveryReadCancellationPropagatesWithoutSave() async throws {
  let configuration = try removeCancellationConfiguration()
  let store = RemoveCancellationConfigurationStore(
    configurations: [configuration]
  )
  let pendingStore = RemoveCancellationPendingCopyStore(cancelRead: true)
  let useCase = RemoveGlassUseCase(
    configurationStore: store,
    pendingCopyStore: pendingStore
  )

  do {
    _ = try await useCase.execute(glassID: configuration.id)
    Issue.record("Expected remove cancellation")
  } catch is CancellationError {
  } catch {
    Issue.record("Expected CancellationError, got \(error)")
  }

  #expect(await store.counts().loads == 1)
  #expect(await store.counts().saves == 0)
  #expect(await pendingStore.reads() == 1)
}

@Test
func removeSaveCancellationPropagatesBeforeCommit() async throws {
  let configuration = try removeCancellationConfiguration()
  let store = RemoveCancellationConfigurationStore(
    configurations: [configuration],
    stage: .save
  )
  let pendingStore = RemoveCancellationPendingCopyStore()
  let useCase = RemoveGlassUseCase(
    configurationStore: store,
    pendingCopyStore: pendingStore
  )

  do {
    _ = try await useCase.execute(glassID: configuration.id)
    Issue.record("Expected remove cancellation")
  } catch is CancellationError {
  } catch {
    Issue.record("Expected CancellationError, got \(error)")
  }

  #expect(await store.counts().loads == 1)
  #expect(await store.counts().saves == 1)
  #expect(await pendingStore.reads() == 1)
}

@Test
func removeSuccessfulSaveRemainsCommitPointAfterLateCancellation() async throws {
  let configuration = try removeCancellationConfiguration()
  let store = RemoveCancellationConfigurationStore(
    configurations: [configuration],
    stage: .cancelAfterSaveSuccess
  )
  let pendingStore = RemoveCancellationPendingCopyStore()
  let useCase = RemoveGlassUseCase(
    configurationStore: store,
    pendingCopyStore: pendingStore
  )

  let didRemove = try await useCase.execute(glassID: configuration.id)

  #expect(didRemove)
  #expect(await store.counts().loads == 1)
  #expect(await store.counts().saves == 1)
  #expect(await pendingStore.reads() == 1)
}

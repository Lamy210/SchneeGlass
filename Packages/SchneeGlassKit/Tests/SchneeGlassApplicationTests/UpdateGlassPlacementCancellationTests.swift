import Foundation
import SchneeGlassDomain
import Testing

@testable import SchneeGlassApplication

private enum PlacementCancellationStage: Sendable {
  case none
  case load
  case cancelAfterLoadSuccess
  case save
  case cancelAfterSaveSuccess
}

private actor PlacementCancellationConfigurationStore: ConditionalConfigurationPersisting {
  private var values: [GlassConfiguration]
  private let stage: PlacementCancellationStage
  private var loadCount = 0
  private var saveCount = 0

  init(
    values: [GlassConfiguration],
    stage: PlacementCancellationStage = .none
  ) {
    self.values = values
    self.stage = stage
  }

  func load() async throws -> [GlassConfiguration] {
    loadCount += 1

    switch stage {
    case .load:
      throw CancellationError()
    case .cancelAfterLoadSuccess:
      withUnsafeCurrentTask { task in
        task?.cancel()
      }
      return values
    case .none, .save, .cancelAfterSaveSuccess:
      return values
    }
  }

  func save(_ configurations: [GlassConfiguration]) async throws {
    values = configurations
  }

  func save(
    _ configurations: [GlassConfiguration],
    ifCurrentMatches expectedCurrent: [GlassConfiguration]
  ) async throws -> Bool {
    saveCount += 1

    if stage == .save {
      throw CancellationError()
    }

    guard values == expectedCurrent else {
      return false
    }

    values = configurations
    if stage == .cancelAfterSaveSuccess {
      withUnsafeCurrentTask { task in
        task?.cancel()
      }
    }
    return true
  }

  func counts() -> (loads: Int, saves: Int) {
    (loadCount, saveCount)
  }

  func current() -> [GlassConfiguration] {
    values
  }
}

private func placementCancellationConfiguration(
  id: GlassID = GlassID()
) throws -> GlassConfiguration {
  try GlassConfiguration(
    id: id,
    title: "Placement Target",
    source: FolderSource(
      bookmarkData: Data([1]),
      lastKnownPath: "/tmp/placement-target"
    ),
    placement: GlassPlacement(x: 100, y: 120),
    createdAt: Date(timeIntervalSince1970: 1_700_000_000)
  )
}

@Test
func preCancelledPlacementPersistenceDoesNotReadConfiguration() async throws {
  let configuration = try placementCancellationConfiguration()
  let store = PlacementCancellationConfigurationStore(values: [configuration])
  let useCase = UpdateGlassPlacementUseCase(configurationStore: store)
  let placement = try GlassPlacement(x: 200, y: 220)

  let task = Task {
    withUnsafeCurrentTask { current in
      current?.cancel()
    }
    return try await useCase.execute(
      glassID: configuration.id,
      placement: placement
    )
  }

  do {
    _ = try await task.value
    Issue.record("Expected placement persistence cancellation")
  } catch is CancellationError {
  } catch {
    Issue.record("Expected CancellationError, got \(error)")
  }

  #expect(await store.counts().loads == 0)
  #expect(await store.counts().saves == 0)
}

@Test
func placementLoadCancellationPropagatesWithoutSave() async throws {
  let configuration = try placementCancellationConfiguration()
  let store = PlacementCancellationConfigurationStore(
    values: [configuration],
    stage: .load
  )
  let useCase = UpdateGlassPlacementUseCase(configurationStore: store)

  do {
    _ = try await useCase.execute(
      glassID: configuration.id,
      placement: try GlassPlacement(x: 200, y: 220)
    )
    Issue.record("Expected placement persistence cancellation")
  } catch is CancellationError {
  } catch {
    Issue.record("Expected CancellationError, got \(error)")
  }

  #expect(await store.counts().loads == 1)
  #expect(await store.counts().saves == 0)
}

@Test
func cancellationObservedAfterPlacementLoadStopsBeforeSave() async throws {
  let configuration = try placementCancellationConfiguration()
  let store = PlacementCancellationConfigurationStore(
    values: [configuration],
    stage: .cancelAfterLoadSuccess
  )
  let useCase = UpdateGlassPlacementUseCase(configurationStore: store)

  do {
    _ = try await useCase.execute(
      glassID: configuration.id,
      placement: try GlassPlacement(x: 200, y: 220)
    )
    Issue.record("Expected placement persistence cancellation")
  } catch is CancellationError {
  } catch {
    Issue.record("Expected CancellationError, got \(error)")
  }

  #expect(await store.counts().loads == 1)
  #expect(await store.counts().saves == 0)
}

@Test
func placementSaveCancellationPropagatesBeforeCommit() async throws {
  let configuration = try placementCancellationConfiguration()
  let store = PlacementCancellationConfigurationStore(
    values: [configuration],
    stage: .save
  )
  let useCase = UpdateGlassPlacementUseCase(configurationStore: store)

  do {
    _ = try await useCase.execute(
      glassID: configuration.id,
      placement: try GlassPlacement(x: 200, y: 220)
    )
    Issue.record("Expected placement persistence cancellation")
  } catch is CancellationError {
  } catch {
    Issue.record("Expected CancellationError, got \(error)")
  }

  #expect(await store.counts().loads == 1)
  #expect(await store.counts().saves == 1)

  let persisted = try #require(await store.current().first)
  #expect(persisted.placement == configuration.placement)
}

@Test
func successfulPlacementSaveRemainsCommitPointAfterLateCancellation() async throws {
  let configuration = try placementCancellationConfiguration()
  let store = PlacementCancellationConfigurationStore(
    values: [configuration],
    stage: .cancelAfterSaveSuccess
  )
  let useCase = UpdateGlassPlacementUseCase(configurationStore: store)
  let placement = try GlassPlacement(x: 200, y: 220)

  let updated = try await useCase.execute(
    glassID: configuration.id,
    placement: placement
  )

  #expect(updated)
  #expect(await store.counts().loads == 1)
  #expect(await store.counts().saves == 1)

  let persisted = try #require(await store.current().first)
  #expect(persisted.placement == placement)
}

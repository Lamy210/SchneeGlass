import Foundation
import SchneeGlassDomain
import Testing

@testable import SchneeGlassApplication

private enum ResetPositionsCancellationStoreMode: Sendable {
  case normal
  case loadThrowsCancellation
  case loadCancelsAndReturns
  case saveThrowsCancellation
  case saveCancelsAndCommits
}

private actor ResetPositionsCancellationStore: ConditionalConfigurationPersisting {
  private let loaded: [GlassConfiguration]
  private let mode: ResetPositionsCancellationStoreMode
  private var loadCountValue = 0
  private var saveCountValue = 0
  private var saved: [[GlassConfiguration]] = []

  init(
    loaded: [GlassConfiguration],
    mode: ResetPositionsCancellationStoreMode
  ) {
    self.loaded = loaded
    self.mode = mode
  }

  func load() async throws -> [GlassConfiguration] {
    loadCountValue += 1
    switch mode {
    case .loadThrowsCancellation:
      throw CancellationError()
    case .loadCancelsAndReturns:
      withUnsafeCurrentTask { task in
        task?.cancel()
      }
      return loaded
    default:
      return loaded
    }
  }

  func save(_ configurations: [GlassConfiguration]) async throws {
    _ = try await save(
      configurations,
      ifCurrentMatches: loaded
    )
  }

  func save(
    _ configurations: [GlassConfiguration],
    ifCurrentMatches expectedCurrent: [GlassConfiguration]
  ) async throws -> Bool {
    saveCountValue += 1
    #expect(expectedCurrent == loaded)

    switch mode {
    case .saveThrowsCancellation:
      throw CancellationError()
    case .saveCancelsAndCommits:
      saved.append(configurations)
      withUnsafeCurrentTask { task in
        task?.cancel()
      }
      return true
    default:
      saved.append(configurations)
      return true
    }
  }

  func counts() -> (loads: Int, saves: Int) {
    (loadCountValue, saveCountValue)
  }

  func savedValues() -> [[GlassConfiguration]] {
    saved
  }
}

private func resetPositionsCancellationConfiguration() throws -> GlassConfiguration {
  try GlassConfiguration(
    title: "Projects",
    source: FolderSource(
      bookmarkData: Data([1]),
      lastKnownPath: "/tmp/Projects"
    ),
    placement: GlassPlacement(x: 100, y: 120),
    showOnAllSpaces: true,
    createdAt: Date(timeIntervalSince1970: 1_700_000_000)
  )
}

private func resetPositionsCancellationTarget(
  for configuration: GlassConfiguration
) throws -> [GlassID: GlassPlacement] {
  [
    configuration.id: try GlassPlacement(
      x: 40,
      y: 600,
      displayHint: "Built-in Display"
    )
  ]
}

private func expectResetPositionsCancellation(
  _ operation: @escaping @Sendable () async throws -> [GlassConfiguration]
) async {
  do {
    _ = try await operation()
    Issue.record("Expected CancellationError")
  } catch is CancellationError {
  } catch {
    Issue.record("Expected CancellationError, got \(error)")
  }
}

@Test
func preCancelledResetPositionsStopsBeforeConfigurationLoad() async throws {
  let configuration = try resetPositionsCancellationConfiguration()
  let placements = try resetPositionsCancellationTarget(for: configuration)
  let store = ResetPositionsCancellationStore(
    loaded: [configuration],
    mode: .normal
  )
  let useCase = ResetGlassPositionsUseCase(configurationStore: store)

  let task = Task {
    withUnsafeCurrentTask { current in
      current?.cancel()
    }
    return try await useCase.execute(placements: placements)
  }

  await expectResetPositionsCancellation {
    try await task.value
  }

  let counts = await store.counts()
  #expect(counts.loads == 0)
  #expect(counts.saves == 0)
}

@Test
func resetPositionsPropagatesConfigurationLoadCancellation() async throws {
  let configuration = try resetPositionsCancellationConfiguration()
  let placements = try resetPositionsCancellationTarget(for: configuration)
  let store = ResetPositionsCancellationStore(
    loaded: [configuration],
    mode: .loadThrowsCancellation
  )
  let useCase = ResetGlassPositionsUseCase(configurationStore: store)

  await expectResetPositionsCancellation {
    try await useCase.execute(placements: placements)
  }

  let counts = await store.counts()
  #expect(counts.loads == 1)
  #expect(counts.saves == 0)
}

@Test
func resetPositionsObservesCancellationAfterSuccessfulLoad() async throws {
  let configuration = try resetPositionsCancellationConfiguration()
  let placements = try resetPositionsCancellationTarget(for: configuration)
  let store = ResetPositionsCancellationStore(
    loaded: [configuration],
    mode: .loadCancelsAndReturns
  )
  let useCase = ResetGlassPositionsUseCase(configurationStore: store)

  await expectResetPositionsCancellation {
    try await useCase.execute(placements: placements)
  }

  let counts = await store.counts()
  #expect(counts.loads == 1)
  #expect(counts.saves == 0)
}

@Test
func resetPositionsPropagatesConfigurationSaveCancellation() async throws {
  let configuration = try resetPositionsCancellationConfiguration()
  let placements = try resetPositionsCancellationTarget(for: configuration)
  let store = ResetPositionsCancellationStore(
    loaded: [configuration],
    mode: .saveThrowsCancellation
  )
  let useCase = ResetGlassPositionsUseCase(configurationStore: store)

  await expectResetPositionsCancellation {
    try await useCase.execute(placements: placements)
  }

  let counts = await store.counts()
  #expect(counts.loads == 1)
  #expect(counts.saves == 1)
  #expect(await store.savedValues().isEmpty)
}

@Test
func resetPositionsReturnsCommittedResultWhenSaveCancelsAfterCommit() async throws {
  let configuration = try resetPositionsCancellationConfiguration()
  let placements = try resetPositionsCancellationTarget(for: configuration)
  let store = ResetPositionsCancellationStore(
    loaded: [configuration],
    mode: .saveCancelsAndCommits
  )
  let useCase = ResetGlassPositionsUseCase(configurationStore: store)

  let result = try await useCase.execute(placements: placements)

  let saved = try #require(await store.savedValues().last)
  #expect(result == saved)
  #expect(saved.count == 1)
  #expect(saved[0].placement == placements[configuration.id])
}

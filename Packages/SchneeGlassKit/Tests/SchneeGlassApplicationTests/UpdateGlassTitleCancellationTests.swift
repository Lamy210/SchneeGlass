import Foundation
import SchneeGlassDomain
import Testing

@testable import SchneeGlassApplication

private enum TitleCancellationStoreMode: Sendable {
  case normal
  case loadThrowsCancellation
  case loadCancelsAndReturns
  case saveThrowsCancellation
  case saveCancelsAndCommits
}

private actor TitleCancellationConfigurationStore: ConditionalConfigurationPersisting {
  private let loaded: [GlassConfiguration]
  private let mode: TitleCancellationStoreMode
  private var loadCountValue = 0
  private var saveCountValue = 0
  private var saved: [[GlassConfiguration]] = []

  init(
    loaded: [GlassConfiguration],
    mode: TitleCancellationStoreMode
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

private func titleCancellationConfiguration() throws -> GlassConfiguration {
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

private func expectTitleCancellation(
  _ operation: @escaping @Sendable () async throws -> Bool
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
func preCancelledTitleUpdateStopsBeforeConfigurationLoad() async throws {
  let configuration = try titleCancellationConfiguration()
  let store = TitleCancellationConfigurationStore(
    loaded: [configuration],
    mode: .normal
  )
  let useCase = UpdateGlassTitleUseCase(configurationStore: store)

  let task = Task {
    withUnsafeCurrentTask { current in
      current?.cancel()
    }
    return try await useCase.execute(
      glassID: configuration.id,
      title: "Renamed"
    )
  }

  await expectTitleCancellation {
    try await task.value
  }

  let counts = await store.counts()
  #expect(counts.loads == 0)
  #expect(counts.saves == 0)
}

@Test
func titleUpdatePropagatesConfigurationLoadCancellation() async throws {
  let configuration = try titleCancellationConfiguration()
  let store = TitleCancellationConfigurationStore(
    loaded: [configuration],
    mode: .loadThrowsCancellation
  )
  let useCase = UpdateGlassTitleUseCase(configurationStore: store)

  await expectTitleCancellation {
    try await useCase.execute(
      glassID: configuration.id,
      title: "Renamed"
    )
  }

  let counts = await store.counts()
  #expect(counts.loads == 1)
  #expect(counts.saves == 0)
}

@Test
func titleUpdateObservesCancellationAfterSuccessfulLoad() async throws {
  let configuration = try titleCancellationConfiguration()
  let store = TitleCancellationConfigurationStore(
    loaded: [configuration],
    mode: .loadCancelsAndReturns
  )
  let useCase = UpdateGlassTitleUseCase(configurationStore: store)

  await expectTitleCancellation {
    try await useCase.execute(
      glassID: configuration.id,
      title: "Renamed"
    )
  }

  let counts = await store.counts()
  #expect(counts.loads == 1)
  #expect(counts.saves == 0)
}

@Test
func titleUpdatePropagatesConfigurationSaveCancellation() async throws {
  let configuration = try titleCancellationConfiguration()
  let store = TitleCancellationConfigurationStore(
    loaded: [configuration],
    mode: .saveThrowsCancellation
  )
  let useCase = UpdateGlassTitleUseCase(configurationStore: store)

  await expectTitleCancellation {
    try await useCase.execute(
      glassID: configuration.id,
      title: "Renamed"
    )
  }

  let counts = await store.counts()
  #expect(counts.loads == 1)
  #expect(counts.saves == 1)
  #expect(await store.savedValues().isEmpty)
}

@Test
func titleUpdateReturnsCommittedResultWhenSaveCancelsAfterCommit() async throws {
  let configuration = try titleCancellationConfiguration()
  let store = TitleCancellationConfigurationStore(
    loaded: [configuration],
    mode: .saveCancelsAndCommits
  )
  let useCase = UpdateGlassTitleUseCase(configurationStore: store)

  let updated = try await useCase.execute(
    glassID: configuration.id,
    title: "Renamed"
  )

  #expect(updated)
  let saved = try #require(await store.savedValues().last)
  #expect(saved.count == 1)
  #expect(saved[0].title == "Renamed")
}

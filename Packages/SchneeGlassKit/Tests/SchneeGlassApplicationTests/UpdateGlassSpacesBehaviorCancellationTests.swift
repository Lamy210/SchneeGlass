import Foundation
import SchneeGlassDomain
import Testing

@testable import SchneeGlassApplication

private enum SpacesCancellationStoreMode: Sendable {
  case normal
  case loadThrowsCancellation
  case loadCancelsAndReturns
  case saveThrowsCancellation
  case saveCancelsAndCommits
}

private actor SpacesCancellationConfigurationStore: ConditionalConfigurationPersisting {
  private let loaded: [GlassConfiguration]
  private let mode: SpacesCancellationStoreMode
  private var loadCountValue = 0
  private var saveCountValue = 0
  private var saved: [[GlassConfiguration]] = []

  init(
    loaded: [GlassConfiguration],
    mode: SpacesCancellationStoreMode
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

private func spacesCancellationConfiguration() throws -> GlassConfiguration {
  try GlassConfiguration(
    title: "Projects",
    source: FolderSource(
      bookmarkData: Data([1]),
      lastKnownPath: "/tmp/Projects"
    ),
    placement: GlassPlacement(x: 100, y: 120),
    showOnAllSpaces: false,
    createdAt: Date(timeIntervalSince1970: 1_700_000_000)
  )
}

private func expectSpacesCancellation(
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
func preCancelledSpacesUpdateStopsBeforeConfigurationLoad() async throws {
  let configuration = try spacesCancellationConfiguration()
  let store = SpacesCancellationConfigurationStore(
    loaded: [configuration],
    mode: .normal
  )
  let useCase = UpdateGlassSpacesBehaviorUseCase(configurationStore: store)

  let task = Task {
    withUnsafeCurrentTask { current in
      current?.cancel()
    }
    return try await useCase.execute(
      glassID: configuration.id,
      showOnAllSpaces: true
    )
  }

  await expectSpacesCancellation {
    try await task.value
  }

  let counts = await store.counts()
  #expect(counts.loads == 0)
  #expect(counts.saves == 0)
}

@Test
func spacesUpdatePropagatesConfigurationLoadCancellation() async throws {
  let configuration = try spacesCancellationConfiguration()
  let store = SpacesCancellationConfigurationStore(
    loaded: [configuration],
    mode: .loadThrowsCancellation
  )
  let useCase = UpdateGlassSpacesBehaviorUseCase(configurationStore: store)

  await expectSpacesCancellation {
    try await useCase.execute(
      glassID: configuration.id,
      showOnAllSpaces: true
    )
  }

  let counts = await store.counts()
  #expect(counts.loads == 1)
  #expect(counts.saves == 0)
}

@Test
func spacesUpdateObservesCancellationAfterSuccessfulLoad() async throws {
  let configuration = try spacesCancellationConfiguration()
  let store = SpacesCancellationConfigurationStore(
    loaded: [configuration],
    mode: .loadCancelsAndReturns
  )
  let useCase = UpdateGlassSpacesBehaviorUseCase(configurationStore: store)

  await expectSpacesCancellation {
    try await useCase.execute(
      glassID: configuration.id,
      showOnAllSpaces: true
    )
  }

  let counts = await store.counts()
  #expect(counts.loads == 1)
  #expect(counts.saves == 0)
}

@Test
func spacesUpdatePropagatesConfigurationSaveCancellation() async throws {
  let configuration = try spacesCancellationConfiguration()
  let store = SpacesCancellationConfigurationStore(
    loaded: [configuration],
    mode: .saveThrowsCancellation
  )
  let useCase = UpdateGlassSpacesBehaviorUseCase(configurationStore: store)

  await expectSpacesCancellation {
    try await useCase.execute(
      glassID: configuration.id,
      showOnAllSpaces: true
    )
  }

  let counts = await store.counts()
  #expect(counts.loads == 1)
  #expect(counts.saves == 1)
  #expect(await store.savedValues().isEmpty)
}

@Test
func spacesUpdateReturnsCommittedResultWhenSaveCancelsAfterCommit() async throws {
  let configuration = try spacesCancellationConfiguration()
  let store = SpacesCancellationConfigurationStore(
    loaded: [configuration],
    mode: .saveCancelsAndCommits
  )
  let useCase = UpdateGlassSpacesBehaviorUseCase(configurationStore: store)

  let updated = try await useCase.execute(
    glassID: configuration.id,
    showOnAllSpaces: true
  )

  #expect(updated)
  let saved = try #require(await store.savedValues().last)
  #expect(saved.count == 1)
  #expect(saved[0].showOnAllSpaces)
}

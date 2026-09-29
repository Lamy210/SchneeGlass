import FileDomain
import Foundation
import SchneeGlassDomain
import Testing

@testable import SchneeGlassApplication

private enum ReconnectCancellationStage: Equatable, Sendable {
  case none
  case preflightLoad
  case commitLoad
  case save
}

@MainActor
private final class ReconnectCancellationFolderSelector: FolderSelecting {
  let url: URL?

  init(url: URL?) {
    self.url = url
  }

  func selectFolder() async -> URL? {
    url
  }
}

private actor ReconnectCancellationSourceCreator: FolderSourceCreating {
  let source: FolderSource

  init(source: FolderSource) {
    self.source = source
  }

  func createSource(for selectedURL: URL) async throws -> FolderSource {
    _ = selectedURL
    return source
  }
}

private actor ReconnectCancellationStore: ConditionalConfigurationPersisting {
  let configuration: GlassConfiguration
  let stage: ReconnectCancellationStage
  private var loadCount = 0
  private var saveCount = 0

  init(
    configuration: GlassConfiguration,
    stage: ReconnectCancellationStage
  ) {
    self.configuration = configuration
    self.stage = stage
  }

  func load() async throws -> [GlassConfiguration] {
    loadCount += 1
    if stage == .preflightLoad && loadCount == 1 {
      throw CancellationError()
    }
    if stage == .commitLoad && loadCount == 2 {
      throw CancellationError()
    }
    return [configuration]
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
    if stage == .save {
      throw CancellationError()
    }
    return true
  }

  func counts() -> (loads: Int, saves: Int) {
    (loadCount, saveCount)
  }
}

private actor ReconnectCancellationAccess: FolderAccessControlling {
  private var acquireCount = 0
  private var releaseCount = 0

  func acquire(
    source: FolderSource,
    glassID: GlassID
  ) async throws -> FolderAccessAcquisition {
    acquireCount += 1
    return FolderAccessAcquisition(
      handle: FolderAccessHandle(
        glassID: glassID,
        url: URL(
          fileURLWithPath: source.lastKnownPath,
          isDirectory: true
        )
      ),
      refreshedSource: nil
    )
  }

  func release(handleID: UUID) async {
    _ = handleID
    releaseCount += 1
  }

  func counts() -> (acquired: Int, released: Int) {
    (acquireCount, releaseCount)
  }
}

private actor ReconnectCancellationEvents: FileEventStreaming {
  let cancelSubscribe: Bool
  private var subscribeCount = 0
  private var stopCount = 0

  init(cancelSubscribe: Bool = false) {
    self.cancelSubscribe = cancelSubscribe
  }

  func subscribe(
    for access: FolderAccessHandle
  ) async throws -> FileEventSubscription {
    _ = access
    if cancelSubscribe {
      throw CancellationError()
    }
    subscribeCount += 1
    return FileEventSubscription(
      events: AsyncStream { continuation in
        continuation.finish()
      }
    )
  }

  func stop(subscriptionID: UUID) async {
    _ = subscriptionID
    stopCount += 1
  }

  func counts() -> (subscribed: Int, stopped: Int) {
    (subscribeCount, stopCount)
  }
}

private actor ReconnectCancellationSnapshotReader: FolderSnapshotReading {
  let cancel: Bool

  init(cancel: Bool = false) {
    self.cancel = cancel
  }

  func snapshot(
    for access: FolderAccessHandle,
    generation: UInt64
  ) async throws -> FolderSnapshot {
    if cancel {
      throw CancellationError()
    }

    return FolderSnapshot(
      folderIdentity: FolderIdentity(
        resourceIdentifier: nil,
        standardizedURL: access.url
      ),
      items: [],
      isTruncated: false,
      observedAt: Date(timeIntervalSince1970: 1_700_000_000),
      generation: generation
    )
  }
}

private func reconnectCancellationIdentity() -> PersistentFolderIdentity {
  PersistentFolderIdentity(
    volumeUUIDString: "volume-a",
    documentIdentifier: 42
  )
}

private func reconnectCancellationSource(
  marker: UInt8
) -> FolderSource {
  FolderSource(
    bookmarkData: Data([marker]),
    lastKnownPath: "/tmp/Projects",
    persistentIdentity: reconnectCancellationIdentity()
  )
}

private func reconnectCancellationConfiguration() throws -> GlassConfiguration {
  try GlassConfiguration(
    title: "Projects",
    source: reconnectCancellationSource(marker: 1),
    placement: GlassPlacement(x: 120, y: 140),
    createdAt: Date(timeIntervalSince1970: 1_700_000_000)
  )
}

@MainActor
private func makeReconnectCancellationFixture(
  stage: ReconnectCancellationStage = .none,
  cancelSubscribe: Bool = false,
  cancelSnapshot: Bool = false
) throws -> (
  useCase: ReconnectGlassSourceUseCase,
  configuration: GlassConfiguration,
  store: ReconnectCancellationStore,
  access: ReconnectCancellationAccess,
  events: ReconnectCancellationEvents
) {
  let configuration = try reconnectCancellationConfiguration()
  let store = ReconnectCancellationStore(
    configuration: configuration,
    stage: stage
  )
  let access = ReconnectCancellationAccess()
  let events = ReconnectCancellationEvents(
    cancelSubscribe: cancelSubscribe
  )
  let useCase = ReconnectGlassSourceUseCase(
    configurationStore: store,
    folderSelector: ReconnectCancellationFolderSelector(
      url: URL(
        fileURLWithPath: "/tmp/Projects",
        isDirectory: true
      )
    ),
    sourceCreator: ReconnectCancellationSourceCreator(
      source: reconnectCancellationSource(marker: 2)
    ),
    accessController: access,
    eventStreaming: events,
    snapshotReader: ReconnectCancellationSnapshotReader(
      cancel: cancelSnapshot
    )
  )
  return (useCase, configuration, store, access, events)
}

@Test
@MainActor
func reconnectPreflightLoadCancellationPropagatesWithoutResources()
  async throws
{
  let fixture = try makeReconnectCancellationFixture(
    stage: .preflightLoad
  )

  do {
    _ = try await fixture.useCase.execute(
      glassID: fixture.configuration.id
    )
    Issue.record("Expected reconnect cancellation")
  } catch is CancellationError {
  } catch {
    Issue.record("Expected CancellationError, got \(error)")
  }

  #expect(await fixture.store.counts().loads == 1)
  #expect(await fixture.access.counts().acquired == 0)
  #expect(await fixture.events.counts().subscribed == 0)
}

@Test
@MainActor
func reconnectSubscribeCancellationReleasesCurrentAccess()
  async throws
{
  let fixture = try makeReconnectCancellationFixture(
    cancelSubscribe: true
  )

  do {
    _ = try await fixture.useCase.execute(
      glassID: fixture.configuration.id
    )
    Issue.record("Expected reconnect cancellation")
  } catch is CancellationError {
  } catch {
    Issue.record("Expected CancellationError, got \(error)")
  }

  #expect(await fixture.access.counts().acquired == 1)
  #expect(await fixture.access.counts().released == 1)
  #expect(await fixture.events.counts().subscribed == 0)
  #expect(await fixture.events.counts().stopped == 0)
}

@Test
@MainActor
func reconnectSnapshotCancellationStopsEventsAndReleasesAccess()
  async throws
{
  let fixture = try makeReconnectCancellationFixture(
    cancelSnapshot: true
  )

  do {
    _ = try await fixture.useCase.execute(
      glassID: fixture.configuration.id
    )
    Issue.record("Expected reconnect cancellation")
  } catch is CancellationError {
  } catch {
    Issue.record("Expected CancellationError, got \(error)")
  }

  #expect(await fixture.access.counts().released == 1)
  #expect(await fixture.events.counts().subscribed == 1)
  #expect(await fixture.events.counts().stopped == 1)
  #expect(await fixture.store.counts().saves == 0)
}

@Test
@MainActor
func reconnectCommitLoadCancellationCleansPreparedRuntime()
  async throws
{
  let fixture = try makeReconnectCancellationFixture(
    stage: .commitLoad
  )

  do {
    _ = try await fixture.useCase.execute(
      glassID: fixture.configuration.id
    )
    Issue.record("Expected reconnect cancellation")
  } catch is CancellationError {
  } catch {
    Issue.record("Expected CancellationError, got \(error)")
  }

  #expect(await fixture.store.counts().loads == 2)
  #expect(await fixture.store.counts().saves == 0)
  #expect(await fixture.access.counts().released == 1)
  #expect(await fixture.events.counts().stopped == 1)
}

@Test
@MainActor
func reconnectSaveCancellationCleansPreparedRuntime()
  async throws
{
  let fixture = try makeReconnectCancellationFixture(
    stage: .save
  )

  do {
    _ = try await fixture.useCase.execute(
      glassID: fixture.configuration.id
    )
    Issue.record("Expected reconnect cancellation")
  } catch is CancellationError {
  } catch {
    Issue.record("Expected CancellationError, got \(error)")
  }

  #expect(await fixture.store.counts().loads == 2)
  #expect(await fixture.store.counts().saves == 1)
  #expect(await fixture.access.counts().released == 1)
  #expect(await fixture.events.counts().stopped == 1)
}

import FileDomain
import Foundation
import SchneeGlassDomain
import Testing

@testable import SchneeGlassApplication

private enum ReconnectGlassTestError: Error, Sendable {
  case injected
}

@MainActor
private final class ReconnectFolderSelector: FolderSelecting {
  let selectedURL: URL?

  init(selectedURL: URL?) {
    self.selectedURL = selectedURL
  }

  func selectFolder() async -> URL? {
    selectedURL
  }
}

private actor ReconnectSourceCreator: FolderSourceCreating {
  let source: FolderSource
  let error: FolderSourceCreationError?

  init(source: FolderSource, error: FolderSourceCreationError? = nil) {
    self.source = source
    self.error = error
  }

  func createSource(for selectedURL: URL) async throws -> FolderSource {
    if let error {
      throw error
    }
    return source
  }
}

private actor ReconnectConfigurationStore: ConditionalConfigurationPersisting {
  private var loads: [[GlassConfiguration]]
  private let failSave: Bool
  private let rejectConditionalSave: Bool
  private var saved: [[GlassConfiguration]] = []

  init(
    loads: [[GlassConfiguration]],
    failSave: Bool = false,
    rejectConditionalSave: Bool = false
  ) {
    self.loads = loads
    self.failSave = failSave
    self.rejectConditionalSave = rejectConditionalSave
  }

  func load() async throws -> [GlassConfiguration] {
    guard !loads.isEmpty else {
      throw ReconnectGlassTestError.injected
    }
    if loads.count == 1 {
      return loads[0]
    }
    return loads.removeFirst()
  }

  func save(_ configurations: [GlassConfiguration]) async throws {
    if failSave {
      throw ReconnectGlassTestError.injected
    }
    saved.append(configurations)
  }

  func save(
    _ configurations: [GlassConfiguration],
    ifCurrentMatches expectedCurrent: [GlassConfiguration]
  ) async throws -> Bool {
    if failSave {
      throw ReconnectGlassTestError.injected
    }
    guard !rejectConditionalSave else {
      return false
    }
    saved.append(configurations)
    return true
  }

  func savedValues() -> [[GlassConfiguration]] {
    saved
  }
}

private actor ReconnectAccessController: FolderAccessControlling {
  let refreshedSource: FolderSource?
  let failAcquire: Bool
  private var acquisitionCount = 0
  private var releaseCount = 0

  init(refreshedSource: FolderSource? = nil, failAcquire: Bool = false) {
    self.refreshedSource = refreshedSource
    self.failAcquire = failAcquire
  }

  func acquire(
    source: FolderSource,
    glassID: GlassID
  ) async throws -> FolderAccessAcquisition {
    if failAcquire {
      throw FolderAccessError.accessDenied
    }
    acquisitionCount += 1
    return FolderAccessAcquisition(
      handle: FolderAccessHandle(
        glassID: glassID,
        url: URL(fileURLWithPath: source.lastKnownPath, isDirectory: true)
      ),
      refreshedSource: refreshedSource
    )
  }

  func release(handleID: UUID) async {
    releaseCount += 1
  }

  func counts() -> (acquired: Int, released: Int) {
    (acquisitionCount, releaseCount)
  }
}

private actor ReconnectEventStreaming: FileEventStreaming {
  let failSubscribe: Bool
  private var subscriptionCount = 0
  private var stopCountValue = 0

  init(failSubscribe: Bool = false) {
    self.failSubscribe = failSubscribe
  }

  func subscribe(for access: FolderAccessHandle) async throws -> FileEventSubscription {
    if failSubscribe {
      throw ReconnectGlassTestError.injected
    }
    subscriptionCount += 1
    return FileEventSubscription(
      id: UUID(),
      events: AsyncStream { _ in }
    )
  }

  func stop(subscriptionID: UUID) async {
    stopCountValue += 1
  }

  func counts() -> (subscribed: Int, stopped: Int) {
    (subscriptionCount, stopCountValue)
  }
}

private actor ReconnectSnapshotReader: FolderSnapshotReading {
  let fail: Bool

  init(fail: Bool = false) {
    self.fail = fail
  }

  func snapshot(
    for access: FolderAccessHandle,
    generation: UInt64
  ) async throws -> FolderSnapshot {
    if fail {
      throw ReconnectGlassTestError.injected
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

private func reconnectIdentity(
  volume: String = "volume-a",
  document: Int = 42
) -> PersistentFolderIdentity {
  PersistentFolderIdentity(
    volumeUUIDString: volume,
    documentIdentifier: document
  )
}

private func reconnectSource(
  path: String,
  marker: UInt8,
  identity: PersistentFolderIdentity?
) -> FolderSource {
  FolderSource(
    bookmarkData: Data([marker]),
    lastKnownPath: path,
    persistentIdentity: identity
  )
}

private func reconnectConfiguration(
  id: GlassID = GlassID(),
  source: FolderSource
) throws -> GlassConfiguration {
  try GlassConfiguration(
    id: id,
    title: "Projects",
    source: source,
    placement: GlassPlacement(x: 120, y: 140, width: 420, height: 300),
    showOnAllSpaces: true,
    createdAt: Date(timeIntervalSince1970: 1_700_000_000)
  )
}

@MainActor
private func makeReconnectUseCase(
  configurations: [[GlassConfiguration]],
  selectedSource: FolderSource,
  refreshedSource: FolderSource? = nil,
  selectedURL: URL? = URL(fileURLWithPath: "/tmp/selected", isDirectory: true),
  failAcquire: Bool = false,
  failEvents: Bool = false,
  failSnapshot: Bool = false,
  failSave: Bool = false,
  rejectConditionalSave: Bool = false
) -> (
  useCase: ReconnectGlassSourceUseCase,
  store: ReconnectConfigurationStore,
  access: ReconnectAccessController,
  events: ReconnectEventStreaming
) {
  let store = ReconnectConfigurationStore(
    loads: configurations,
    failSave: failSave,
    rejectConditionalSave: rejectConditionalSave
  )
  let access = ReconnectAccessController(
    refreshedSource: refreshedSource,
    failAcquire: failAcquire
  )
  let events = ReconnectEventStreaming(failSubscribe: failEvents)
  let useCase = ReconnectGlassSourceUseCase(
    configurationStore: store,
    folderSelector: ReconnectFolderSelector(selectedURL: selectedURL),
    sourceCreator: ReconnectSourceCreator(source: selectedSource),
    accessController: access,
    eventStreaming: events,
    snapshotReader: ReconnectSnapshotReader(fail: failSnapshot)
  )
  return (useCase, store, access, events)
}

@Test
@MainActor
func sourceReconnectPersistsMatchingFolderAndReturnsPreparedRuntime() async throws {
  let identity = reconnectIdentity()
  let originalSource = reconnectSource(
    path: "/old/Projects",
    marker: 1,
    identity: identity
  )
  let selectedSource = reconnectSource(
    path: "/new/Projects",
    marker: 2,
    identity: identity
  )
  let configuration = try reconnectConfiguration(source: originalSource)
  let fixture = makeReconnectUseCase(
    configurations: [[configuration], [configuration]],
    selectedSource: selectedSource
  )

  let seed = try #require(try await fixture.useCase.execute(glassID: configuration.id))

  #expect(seed.configuration.id == configuration.id)
  #expect(seed.configuration.title == configuration.title)
  #expect(seed.configuration.placement == configuration.placement)
  #expect(seed.configuration.showOnAllSpaces == configuration.showOnAllSpaces)
  #expect(seed.configuration.createdAt == configuration.createdAt)
  #expect(seed.configuration.source == selectedSource)
  #expect(seed.access.glassID == configuration.id)
  #expect(seed.snapshot.generation == 1)

  let saved = try #require(await fixture.store.savedValues().last)
  #expect(saved.count == 1)
  #expect(saved[0] == seed.configuration)
  #expect(await fixture.access.counts().released == 0)
  #expect(await fixture.events.counts().stopped == 0)
}

@Test
@MainActor
func sourceReconnectCancellationDoesNotAcquireOrSave() async throws {
  let identity = reconnectIdentity()
  let source = reconnectSource(path: "/old/Projects", marker: 1, identity: identity)
  let configuration = try reconnectConfiguration(source: source)
  let fixture = makeReconnectUseCase(
    configurations: [[configuration]],
    selectedSource: source,
    selectedURL: nil
  )

  let seed = try await fixture.useCase.execute(glassID: configuration.id)

  #expect(seed == nil)
  #expect(await fixture.store.savedValues().isEmpty)
  #expect(await fixture.access.counts().acquired == 0)
}

@Test
@MainActor
func sourceReconnectRejectsDifferentPersistentIdentityBeforeAccess() async throws {
  let originalSource = reconnectSource(
    path: "/old/Projects",
    marker: 1,
    identity: reconnectIdentity(volume: "volume-a", document: 42)
  )
  let selectedSource = reconnectSource(
    path: "/other/Projects",
    marker: 2,
    identity: reconnectIdentity(volume: "volume-a", document: 99)
  )
  let configuration = try reconnectConfiguration(source: originalSource)
  let fixture = makeReconnectUseCase(
    configurations: [[configuration]],
    selectedSource: selectedSource
  )

  do {
    _ = try await fixture.useCase.execute(glassID: configuration.id)
    Issue.record("Expected persistent identity mismatch")
  } catch let error as ReconnectGlassSourceError {
    #expect(error == .selectedSourceMismatch)
  }

  #expect(await fixture.access.counts().acquired == 0)
  #expect(await fixture.store.savedValues().isEmpty)
}

@Test
@MainActor
func sourceReconnectFailsClosedWhenPersistentIdentityIsUnavailable() async throws {
  let originalSource = reconnectSource(
    path: "/old/Projects",
    marker: 1,
    identity: nil
  )
  let selectedSource = reconnectSource(
    path: "/old/Projects",
    marker: 2,
    identity: nil
  )
  let configuration = try reconnectConfiguration(source: originalSource)
  let fixture = makeReconnectUseCase(
    configurations: [[configuration]],
    selectedSource: selectedSource
  )

  do {
    _ = try await fixture.useCase.execute(glassID: configuration.id)
    Issue.record("Expected unavailable persistent identity")
  } catch let error as ReconnectGlassSourceError {
    #expect(error == .selectedSourceIdentityUnavailable)
  }

  #expect(await fixture.access.counts().acquired == 0)
  #expect(await fixture.store.savedValues().isEmpty)
}

@Test
@MainActor
func staleConfigurationAfterPreparationReleasesRuntimeResources() async throws {
  let identity = reconnectIdentity()
  let originalSource = reconnectSource(
    path: "/old/Projects",
    marker: 1,
    identity: identity
  )
  let selectedSource = reconnectSource(
    path: "/new/Projects",
    marker: 2,
    identity: identity
  )
  let original = try reconnectConfiguration(source: originalSource)
  let changed = try GlassConfiguration(
    id: original.id,
    title: "Changed",
    source: original.source,
    placement: original.placement,
    showOnAllSpaces: original.showOnAllSpaces,
    createdAt: original.createdAt
  )
  let fixture = makeReconnectUseCase(
    configurations: [[original], [changed]],
    selectedSource: selectedSource
  )

  do {
    _ = try await fixture.useCase.execute(glassID: original.id)
    Issue.record("Expected stale configuration rejection")
  } catch let error as ReconnectGlassSourceError {
    #expect(error == .staleConfiguration)
  }

  #expect(await fixture.store.savedValues().isEmpty)
  #expect(await fixture.access.counts() == (1, 1))
  #expect(await fixture.events.counts() == (1, 1))
}

@Test
@MainActor
func refreshedSourceIdentityMismatchReleasesAccessBeforeRuntimePreparation() async throws {
  let identity = reconnectIdentity()
  let originalSource = reconnectSource(
    path: "/old/Projects",
    marker: 1,
    identity: identity
  )
  let selectedSource = reconnectSource(
    path: "/new/Projects",
    marker: 2,
    identity: identity
  )
  let refreshedSource = reconnectSource(
    path: "/new/Projects",
    marker: 3,
    identity: reconnectIdentity(volume: "volume-a", document: 99)
  )
  let configuration = try reconnectConfiguration(source: originalSource)
  let fixture = makeReconnectUseCase(
    configurations: [[configuration]],
    selectedSource: selectedSource,
    refreshedSource: refreshedSource
  )

  do {
    _ = try await fixture.useCase.execute(glassID: configuration.id)
    Issue.record("Expected refreshed identity mismatch")
  } catch let error as ReconnectGlassSourceError {
    #expect(error == .selectedSourceMismatch)
  }

  let accessCounts = await fixture.access.counts()
  let eventCounts = await fixture.events.counts()
  #expect(accessCounts.acquired == 1)
  #expect(accessCounts.released == 1)
  #expect(eventCounts.subscribed == 0)
  #expect(eventCounts.stopped == 0)
  #expect(await fixture.store.savedValues().isEmpty)
}

@Test
@MainActor
func eventSubscriptionFailureReleasesAccess() async throws {
  let identity = reconnectIdentity()
  let originalSource = reconnectSource(
    path: "/old/Projects",
    marker: 1,
    identity: identity
  )
  let selectedSource = reconnectSource(
    path: "/new/Projects",
    marker: 2,
    identity: identity
  )
  let configuration = try reconnectConfiguration(source: originalSource)
  let fixture = makeReconnectUseCase(
    configurations: [[configuration]],
    selectedSource: selectedSource,
    failEvents: true
  )

  do {
    _ = try await fixture.useCase.execute(glassID: configuration.id)
    Issue.record("Expected event subscription failure")
  } catch let error as ReconnectGlassSourceError {
    #expect(error == .eventStreamFailed)
  }

  let accessCounts = await fixture.access.counts()
  let eventCounts = await fixture.events.counts()
  #expect(accessCounts.acquired == 1)
  #expect(accessCounts.released == 1)
  #expect(eventCounts.subscribed == 0)
  #expect(eventCounts.stopped == 0)
  #expect(await fixture.store.savedValues().isEmpty)
}

@Test
@MainActor
func snapshotFailureStopsEventsAndReleasesAccess() async throws {
  let identity = reconnectIdentity()
  let originalSource = reconnectSource(
    path: "/old/Projects",
    marker: 1,
    identity: identity
  )
  let selectedSource = reconnectSource(
    path: "/new/Projects",
    marker: 2,
    identity: identity
  )
  let configuration = try reconnectConfiguration(source: originalSource)
  let fixture = makeReconnectUseCase(
    configurations: [[configuration]],
    selectedSource: selectedSource,
    failSnapshot: true
  )

  do {
    _ = try await fixture.useCase.execute(glassID: configuration.id)
    Issue.record("Expected snapshot failure")
  } catch let error as ReconnectGlassSourceError {
    #expect(error == .snapshotFailed)
  }

  #expect(await fixture.access.counts() == (1, 1))
  #expect(await fixture.events.counts() == (1, 1))
  #expect(await fixture.store.savedValues().isEmpty)
}

@Test
@MainActor
func conditionalSaveRejectionCleansPreparedRuntimeResources() async throws {
  let identity = reconnectIdentity()
  let originalSource = reconnectSource(
    path: "/old/Projects",
    marker: 1,
    identity: identity
  )
  let selectedSource = reconnectSource(
    path: "/new/Projects",
    marker: 2,
    identity: identity
  )
  let configuration = try reconnectConfiguration(source: originalSource)
  let fixture = makeReconnectUseCase(
    configurations: [[configuration], [configuration]],
    selectedSource: selectedSource,
    rejectConditionalSave: true
  )

  do {
    _ = try await fixture.useCase.execute(glassID: configuration.id)
    Issue.record("Expected conditional save rejection")
  } catch let error as ReconnectGlassSourceError {
    #expect(error == .staleConfiguration)
  }

  #expect(await fixture.access.counts() == (1, 1))
  #expect(await fixture.events.counts() == (1, 1))
  #expect(await fixture.store.savedValues().isEmpty)
}

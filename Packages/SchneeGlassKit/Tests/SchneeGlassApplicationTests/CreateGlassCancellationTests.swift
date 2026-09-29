import FileDomain
import Foundation
import SchneeGlassDomain
import Testing

@testable import SchneeGlassApplication

private enum CreateCancellationStage: Equatable, Sendable {
  case none
  case load
  case save
}

@MainActor
private final class CreateCancellationFolderSelector: FolderSelecting {
  let url: URL?
  let cancelTask: Bool
  private(set) var selectionCount = 0

  init(
    url: URL?,
    cancelTask: Bool = false
  ) {
    self.url = url
    self.cancelTask = cancelTask
  }

  func selectFolder() async -> URL? {
    selectionCount += 1
    if cancelTask {
      withUnsafeCurrentTask { task in
        task?.cancel()
      }
    }
    return url
  }
}

private actor CreateCancellationSourceCreator: FolderSourceCreating {
  let source: FolderSource
  private var creationCount = 0

  init(source: FolderSource) {
    self.source = source
  }

  func createSource(for selectedURL: URL) async throws -> FolderSource {
    _ = selectedURL
    creationCount += 1
    return source
  }

  func count() -> Int {
    creationCount
  }
}

@MainActor
private final class CreateCancellationPlacementProvider:
  InitialGlassPlacementProviding
{
  func initialPlacement() throws -> GlassPlacement {
    try GlassPlacement(x: 100, y: 120)
  }
}

private actor CreateCancellationStore: ConditionalConfigurationPersisting {
  let stage: CreateCancellationStage
  private var loadCount = 0
  private var saveCount = 0

  init(stage: CreateCancellationStage) {
    self.stage = stage
  }

  func load() async throws -> [GlassConfiguration] {
    loadCount += 1
    if stage == .load {
      throw CancellationError()
    }
    return []
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

private actor CreateCancellationAccess: FolderAccessControlling {
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

private actor CreateCancellationEvents: FileEventStreaming {
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

private actor CreateCancellationSnapshotReader: FolderSnapshotReading {
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

private func createCancellationSource() -> FolderSource {
  FolderSource(
    bookmarkData: Data([1]),
    lastKnownPath: "/tmp/Projects"
  )
}

@MainActor
private func makeCreateCancellationFixture(
  selectedURL: URL? = URL(
    fileURLWithPath: "/tmp/Projects",
    isDirectory: true
  ),
  selectorCancelsTask: Bool = false,
  stage: CreateCancellationStage = .none,
  cancelSubscribe: Bool = false,
  cancelSnapshot: Bool = false
) -> (
  useCase: CreateGlassUseCase,
  selector: CreateCancellationFolderSelector,
  sourceCreator: CreateCancellationSourceCreator,
  store: CreateCancellationStore,
  access: CreateCancellationAccess,
  events: CreateCancellationEvents
) {
  let source = createCancellationSource()
  let selector = CreateCancellationFolderSelector(
    url: selectedURL,
    cancelTask: selectorCancelsTask
  )
  let sourceCreator = CreateCancellationSourceCreator(
    source: source
  )
  let store = CreateCancellationStore(stage: stage)
  let access = CreateCancellationAccess()
  let events = CreateCancellationEvents(
    cancelSubscribe: cancelSubscribe
  )
  let useCase = CreateGlassUseCase(
    folderSelector: selector,
    sourceCreator: sourceCreator,
    placementProvider: CreateCancellationPlacementProvider(),
    configurationStore: store,
    accessController: access,
    eventStreaming: events,
    snapshotReader: CreateCancellationSnapshotReader(
      cancel: cancelSnapshot
    )
  )
  return (useCase, selector, sourceCreator, store, access, events)
}

@Test
@MainActor
func normalFolderPickerCancellationReturnsNilWithoutOpeningResources() async throws {
  let fixture = makeCreateCancellationFixture(selectedURL: nil)

  let result = try await fixture.useCase.execute()

  #expect(result == nil)
  #expect(fixture.selector.selectionCount == 1)
  #expect(await fixture.sourceCreator.count() == 0)
  #expect(await fixture.store.counts().loads == 0)
  #expect(await fixture.access.counts().acquired == 0)
}

@Test
@MainActor
func preCancelledCreateTaskDoesNotOpenFolderPicker()
  async throws
{
  let fixture = makeCreateCancellationFixture()

  let task = Task {
    try await fixture.useCase.execute()
  }
  task.cancel()

  do {
    _ = try await task.value
    Issue.record("Expected create cancellation")
  } catch is CancellationError {
  } catch {
    Issue.record("Expected CancellationError, got \(error)")
  }

  #expect(fixture.selector.selectionCount == 0)
  #expect(await fixture.sourceCreator.count() == 0)
  #expect(await fixture.store.counts().loads == 0)
  #expect(await fixture.access.counts().acquired == 0)
}

@Test
@MainActor
func createTaskCancellationAfterFolderSelectionStopsBeforeSourceCreation()
  async throws
{
  let fixture = makeCreateCancellationFixture(
    selectorCancelsTask: true
  )

  let task = Task {
    try await fixture.useCase.execute()
  }

  do {
    _ = try await task.value
    Issue.record("Expected create cancellation")
  } catch is CancellationError {
  } catch {
    Issue.record("Expected CancellationError, got \(error)")
  }

  #expect(await fixture.sourceCreator.count() == 0)
  #expect(await fixture.store.counts().loads == 0)
  #expect(await fixture.access.counts().acquired == 0)
}

@Test
@MainActor
func createConfigurationLoadCancellationPropagatesBeforeAccess()
  async throws
{
  let fixture = makeCreateCancellationFixture(stage: .load)

  do {
    _ = try await fixture.useCase.execute()
    Issue.record("Expected create cancellation")
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
func createSubscribeCancellationReleasesCurrentAccess()
  async throws
{
  let fixture = makeCreateCancellationFixture(
    cancelSubscribe: true
  )

  do {
    _ = try await fixture.useCase.execute()
    Issue.record("Expected create cancellation")
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
func createSnapshotCancellationStopsEventsAndReleasesAccess()
  async throws
{
  let fixture = makeCreateCancellationFixture(
    cancelSnapshot: true
  )

  do {
    _ = try await fixture.useCase.execute()
    Issue.record("Expected create cancellation")
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
func createSaveCancellationCleansPreparedRuntime()
  async throws
{
  let fixture = makeCreateCancellationFixture(stage: .save)

  do {
    _ = try await fixture.useCase.execute()
    Issue.record("Expected create cancellation")
  } catch is CancellationError {
  } catch {
    Issue.record("Expected CancellationError, got \(error)")
  }

  #expect(await fixture.store.counts().loads == 1)
  #expect(await fixture.store.counts().saves == 1)
  #expect(await fixture.access.counts().released == 1)
  #expect(await fixture.events.counts().stopped == 1)
}

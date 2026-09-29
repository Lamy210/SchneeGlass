import FileDomain
import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing

private actor CancellationConfigurationStore:
  ConditionalConfigurationPersisting
{
  let configurations: [GlassConfiguration]
  let cancelLoad: Bool

  init(
    configurations: [GlassConfiguration],
    cancelLoad: Bool = false
  ) {
    self.configurations = configurations
    self.cancelLoad = cancelLoad
  }

  func load() async throws -> [GlassConfiguration] {
    if cancelLoad {
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
    return true
  }
}

private actor CancellationAccessController:
  FolderAccessControlling
{
  private var releaseCountValue = 0

  func acquire(
    source: FolderSource,
    glassID: GlassID
  ) async throws -> FolderAccessAcquisition {
    FolderAccessAcquisition(
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
    releaseCountValue += 1
  }

  func releaseCount() -> Int {
    releaseCountValue
  }
}

private actor CancellationEventStreaming: FileEventStreaming {
  private var stopCountValue = 0

  func subscribe(
    for access: FolderAccessHandle
  ) async throws -> FileEventSubscription {
    _ = access
    return FileEventSubscription(
      events: AsyncStream { continuation in
        continuation.finish()
      }
    )
  }

  func stop(subscriptionID: UUID) async {
    _ = subscriptionID
    stopCountValue += 1
  }

  func stopCount() -> Int {
    stopCountValue
  }
}

private actor CancellationSnapshotReader: FolderSnapshotReading {
  let cancelFor: GlassID?

  init(cancelFor: GlassID? = nil) {
    self.cancelFor = cancelFor
  }

  func snapshot(
    for access: FolderAccessHandle,
    generation: UInt64
  ) async throws -> FolderSnapshot {
    if access.glassID == cancelFor {
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

private func cancellationConfiguration(
  title: String,
  marker: UInt8
) throws -> GlassConfiguration {
  try GlassConfiguration(
    title: title,
    source: FolderSource(
      bookmarkData: Data([marker]),
      lastKnownPath: "/tmp/\(title)"
    ),
    placement: GlassPlacement(x: 100, y: 100),
    createdAt: Date(timeIntervalSince1970: 1_700_000_000)
  )
}

@Test
func configurationLoadCancellationPropagatesWithoutResources()
  async throws
{
  let store = CancellationConfigurationStore(
    configurations: [],
    cancelLoad: true
  )
  let access = CancellationAccessController()
  let events = CancellationEventStreaming()
  let reader = CancellationSnapshotReader()
  let useCase = RestoreApplicationUseCase(
    configurationStore: store,
    accessController: access,
    eventStreaming: events,
    snapshotReader: reader
  )

  do {
    _ = try await useCase.execute()
    Issue.record("Expected restore cancellation")
  } catch is CancellationError {
  } catch {
    Issue.record("Expected CancellationError, got \(error)")
  }

  #expect(await access.releaseCount() == 0)
  #expect(await events.stopCount() == 0)
}

@Test
func snapshotCancellationCleansPreparedResources()
  async throws
{
  let first = try cancellationConfiguration(
    title: "First",
    marker: 1
  )
  let second = try cancellationConfiguration(
    title: "Second",
    marker: 2
  )
  let store = CancellationConfigurationStore(
    configurations: [first, second]
  )
  let access = CancellationAccessController()
  let events = CancellationEventStreaming()
  let reader = CancellationSnapshotReader(
    cancelFor: second.id
  )
  let useCase = RestoreApplicationUseCase(
    configurationStore: store,
    accessController: access,
    eventStreaming: events,
    snapshotReader: reader
  )

  do {
    _ = try await useCase.execute()
    Issue.record("Expected restore cancellation")
  } catch is CancellationError {
  } catch {
    Issue.record("Expected CancellationError, got \(error)")
  }

  #expect(await events.stopCount() == 2)
  #expect(await access.releaseCount() == 2)
}

import FileDomain
import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing

private enum StateTerminationOrderingTestError: Error, Sendable {
  case unexpectedCall
}

private actor BlockingStateTerminationAccessController: FolderAccessControlling {
  private var releaseStartedValue = false
  private var releaseCountValue = 0
  private var releaseContinuation: CheckedContinuation<Void, Never>?

  func acquire(
    source: FolderSource,
    glassID: GlassID
  ) async throws -> FolderAccessAcquisition {
    _ = source
    _ = glassID
    throw StateTerminationOrderingTestError.unexpectedCall
  }

  func release(handleID: UUID) async {
    _ = handleID
    releaseStartedValue = true
    await withCheckedContinuation { continuation in
      releaseContinuation = continuation
    }
    releaseCountValue += 1
  }

  func hasReleaseStarted() -> Bool {
    releaseStartedValue
  }

  func releaseCount() -> Int {
    releaseCountValue
  }

  func finishRelease() {
    releaseContinuation?.resume()
    releaseContinuation = nil
  }
}

private actor StateTerminationEventStreaming: FileEventStreaming {
  private var stopCountValue = 0

  func subscribe(for access: FolderAccessHandle) async throws -> FileEventSubscription {
    _ = access
    throw StateTerminationOrderingTestError.unexpectedCall
  }

  func stop(subscriptionID: UUID) async {
    _ = subscriptionID
    stopCountValue += 1
  }

  func stopCount() -> Int {
    stopCountValue
  }
}

private struct StateTerminationSnapshotReader: FolderSnapshotReading {
  func snapshot(
    for access: FolderAccessHandle,
    generation: UInt64
  ) async throws -> FolderSnapshot {
    _ = access
    _ = generation
    throw StateTerminationOrderingTestError.unexpectedCall
  }
}

private struct StateTerminationDropPlanner: DropPlanning {
  func plan(
    sourceURLs: [URL],
    destinationAccess: FolderAccessHandle
  ) async -> DropPlan {
    _ = sourceURLs
    _ = destinationAccess
    return .noOperation
  }
}

private struct StateTerminationFileCopying: FileCopying {
  func copy(_ request: AuthorizedCopyBatchRequest) async -> CopyBatchResult {
    CopyBatchResult(
      batchID: request.plan.batchID,
      succeeded: [],
      failed: nil,
      notAttempted: request.plan.items
    )
  }
}

private actor StateTerminationProbe {
  private var observedStates: [GlassContentState] = []
  private var terminated = false

  func record(_ state: GlassContentState) {
    observedStates.append(state)
  }

  func markTerminated() {
    terminated = true
  }

  func snapshot() -> (states: [GlassContentState], terminated: Bool) {
    (observedStates, terminated)
  }
}

private func waitForStateTerminationCondition(
  _ condition: @escaping () async -> Bool
) async -> Bool {
  for _ in 0..<2_000 {
    if await condition() {
      return true
    }
    await Task.yield()
  }
  return false
}

@Test
func runtimeStateStreamTerminatesOnlyAfterAuthorityCleanupCompletes() async throws {
  let root = URL(fileURLWithPath: "/tmp/SchneeGlassStateTermination", isDirectory: true)
  let configuration = try GlassConfiguration(
    title: "State Termination",
    source: FolderSource(bookmarkData: Data([1]), lastKnownPath: root.path),
    placement: GlassPlacement(x: 20, y: 30),
    createdAt: Date(timeIntervalSince1970: 1_700_000_000)
  )
  let access = FolderAccessHandle(
    glassID: configuration.id,
    url: root,
    fingerprint: ResourceFingerprint(
      volumeIdentifier: "volume-A",
      resourceIdentifier: "folder-A"
    )
  )
  let initialSnapshot = FolderSnapshot(
    folderIdentity: FolderIdentity(
      resourceIdentifier: "folder-A",
      standardizedURL: root
    ),
    items: [],
    isTruncated: false,
    observedAt: Date(timeIntervalSince1970: 1_700_000_000),
    generation: 1
  )
  let eventPair = AsyncStream<FileEvent>.makeStream()
  let accessController = BlockingStateTerminationAccessController()
  let eventStreaming = StateTerminationEventStreaming()
  let session = GlassRuntimeSession(
    seed: CreatedGlassRuntimeSeed(
      configuration: configuration,
      access: access,
      snapshot: initialSnapshot,
      eventSubscription: FileEventSubscription(
        id: UUID(),
        events: eventPair.stream
      )
    ),
    eventStreaming: eventStreaming,
    snapshotReader: StateTerminationSnapshotReader(),
    accessController: accessController,
    dropPlanning: StateTerminationDropPlanner(),
    fileCopying: StateTerminationFileCopying()
  )

  let states = try await session.start()
  let probe = StateTerminationProbe()
  let consumer = Task {
    for await state in states {
      await probe.record(state)
    }
    await probe.markTerminated()
  }

  #expect(
    await waitForStateTerminationCondition {
      await probe.snapshot().states.contains(.empty(initialSnapshot))
    }
  )

  eventPair.continuation.finish()

  #expect(
    await waitForStateTerminationCondition {
      let snapshot = await probe.snapshot()
      return snapshot.states.contains(.failed(.unexpected))
        && await accessController.hasReleaseStarted()
    }
  )

  for _ in 0..<200 {
    await Task.yield()
  }

  #expect(!(await probe.snapshot().terminated))
  #expect(await accessController.releaseCount() == 0)
  #expect(await eventStreaming.stopCount() == 1)

  await accessController.finishRelease()
  await consumer.value

  #expect(await probe.snapshot().terminated)
  #expect(await accessController.releaseCount() == 1)
  #expect(await eventStreaming.stopCount() == 1)
}

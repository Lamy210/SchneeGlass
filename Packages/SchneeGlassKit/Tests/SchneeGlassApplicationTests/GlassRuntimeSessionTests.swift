import FileDomain
import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing

private enum RuntimeSessionTestError: Error, Sendable {
  case injected
}

private actor RuntimeAccessController: FolderAccessControlling {
  private var releasedIDs: [UUID] = []

  func acquire(
    source: FolderSource,
    glassID: GlassID
  ) async throws -> FolderAccessAcquisition {
    throw RuntimeSessionTestError.injected
  }

  func release(handleID: UUID) async {
    releasedIDs.append(handleID)
  }

  func releaseCount() -> Int {
    releasedIDs.count
  }
}

private actor RuntimeEventStreaming: FileEventStreaming {
  private var stoppedIDs: [UUID] = []

  func subscribe(for access: FolderAccessHandle) async throws -> FileEventSubscription {
    throw RuntimeSessionTestError.injected
  }

  func stop(subscriptionID: UUID) async {
    stoppedIDs.append(subscriptionID)
  }

  func stopCount() -> Int {
    stoppedIDs.count
  }
}

private actor RuntimeSnapshotReader: FolderSnapshotReading {
  enum Behavior: Sendable {
    case snapshot(FolderSnapshot)
    case fail
  }

  private var behaviors: [Behavior]
  private var readCount = 0

  init(behaviors: [Behavior]) {
    self.behaviors = behaviors
  }

  func snapshot(
    for access: FolderAccessHandle,
    generation: UInt64
  ) async throws -> FolderSnapshot {
    readCount += 1
    guard !behaviors.isEmpty else {
      throw RuntimeSessionTestError.injected
    }

    let behavior = behaviors.removeFirst()
    switch behavior {
    case .snapshot(let snapshot):
      return FolderSnapshot(
        folderIdentity: snapshot.folderIdentity,
        items: snapshot.items,
        isTruncated: snapshot.isTruncated,
        observedAt: snapshot.observedAt,
        generation: generation
      )
    case .fail:
      throw RuntimeSessionTestError.injected
    }
  }

  func callCount() -> Int {
    readCount
  }
}

private actor RuntimeDropPlanner: DropPlanning {
  private var result: DropPlan
  private var observedSourceURLs: [URL] = []
  private var observedAccess: FolderAccessHandle?

  init(result: DropPlan = .noOperation) {
    self.result = result
  }

  func plan(
    sourceURLs: [URL],
    destinationAccess: FolderAccessHandle
  ) async -> DropPlan {
    observedSourceURLs = sourceURLs
    observedAccess = destinationAccess
    return result
  }

  func setResult(_ result: DropPlan) {
    self.result = result
  }

  func observations() -> (sourceURLs: [URL], access: FolderAccessHandle?) {
    (observedSourceURLs, observedAccess)
  }
}

private actor RuntimeFileCopying: FileCopying {
  private let gate: AsyncStream<Void>?
  private var requests: [AuthorizedCopyBatchRequest] = []

  init(gate: AsyncStream<Void>? = nil) {
    self.gate = gate
  }

  func copy(_ request: AuthorizedCopyBatchRequest) async -> CopyBatchResult {
    requests.append(request)
    if let gate {
      var iterator = gate.makeAsyncIterator()
      _ = await iterator.next()
    }
    return CopyBatchResult(
      batchID: request.plan.batchID,
      succeeded: request.plan.items.map {
        CopyItemSuccess(
          operationID: $0.operationID,
          destinationURL: request.destinationAccess.url
            .appendingPathComponent($0.destinationFilename)
        )
      },
      failed: nil,
      notAttempted: []
    )
  }

  func callCount() -> Int {
    requests.count
  }

  func lastRequest() -> AuthorizedCopyBatchRequest? {
    requests.last
  }
}

private struct RuntimeFixture {
  let session: GlassRuntimeSession
  let eventContinuation: AsyncStream<FileEvent>.Continuation
  let copyGateContinuation: AsyncStream<Void>.Continuation?
  let accessController: RuntimeAccessController
  let eventStreaming: RuntimeEventStreaming
  let snapshotReader: RuntimeSnapshotReader
  let dropPlanner: RuntimeDropPlanner
  let fileCopying: RuntimeFileCopying
  let configuration: GlassConfiguration
  let access: FolderAccessHandle
  let initialSnapshot: FolderSnapshot
}

private func makeRuntimeFixture(
  initialItems: [GlassItem] = [],
  refreshBehaviors: [RuntimeSnapshotReader.Behavior] = [],
  blockCopy: Bool = false
) throws -> RuntimeFixture {
  let root = URL(fileURLWithPath: "/tmp/SchneeGlassRuntime", isDirectory: true)
  let configuration = try GlassConfiguration(
    title: "Runtime",
    source: FolderSource(bookmarkData: Data([1]), lastKnownPath: root.path),
    placement: try GlassPlacement(x: 100, y: 100),
    createdAt: Date(timeIntervalSince1970: 1_700_000_000)
  )
  let access = FolderAccessHandle(glassID: configuration.id, url: root)
  let initialSnapshot = FolderSnapshot(
    folderIdentity: FolderIdentity(resourceIdentifier: nil, standardizedURL: root),
    items: initialItems,
    isTruncated: false,
    observedAt: Date(timeIntervalSince1970: 1_700_000_001),
    generation: 1
  )
  let eventPair = AsyncStream<FileEvent>.makeStream()
  let subscription = FileEventSubscription(
    id: UUID(),
    events: eventPair.stream
  )
  let copyPair = blockCopy ? AsyncStream<Void>.makeStream() : nil
  let accessController = RuntimeAccessController()
  let eventStreaming = RuntimeEventStreaming()
  let reader = RuntimeSnapshotReader(behaviors: refreshBehaviors)
  let dropPlanner = RuntimeDropPlanner()
  let fileCopying = RuntimeFileCopying(gate: copyPair?.stream)
  let seed = CreatedGlassRuntimeSeed(
    configuration: configuration,
    access: access,
    snapshot: initialSnapshot,
    eventSubscription: subscription
  )

  return RuntimeFixture(
    session: GlassRuntimeSession(
      seed: seed,
      eventStreaming: eventStreaming,
      snapshotReader: reader,
      accessController: accessController,
      dropPlanning: dropPlanner,
      fileCopying: fileCopying
    ),
    eventContinuation: eventPair.continuation,
    copyGateContinuation: copyPair?.continuation,
    accessController: accessController,
    eventStreaming: eventStreaming,
    snapshotReader: reader,
    dropPlanner: dropPlanner,
    fileCopying: fileCopying,
    configuration: configuration,
    access: access,
    initialSnapshot: initialSnapshot
  )
}

private func item(named name: String) -> GlassItem {
  let url = URL(fileURLWithPath: "/tmp/SchneeGlassRuntime/\(name)")
  return GlassItem(
    id: FileIdentity(resourceIdentifier: nil, standardizedURL: url),
    url: url,
    displayName: name,
    kind: .regular,
    modificationDate: nil,
    fileSize: 1,
    isHidden: false
  )
}

private func copyPlan(for fixture: RuntimeFixture) throws -> CopyBatchPlan {
  let source = URL(fileURLWithPath: "/tmp/External/payload.txt")
  return try CopyBatchPlan(
    destination: DestinationDescriptor(
      glassID: fixture.configuration.id,
      folderIdentity: fixture.initialSnapshot.folderIdentity,
      url: fixture.access.url,
      capabilities: StorageCapabilities(
        locationKind: .localFixed,
        isWritable: true,
        supportsCaseSensitiveNames: false
      )
    ),
    items: [
      CopyItemPlan(
        sourceURL: source,
        originalFilename: source.lastPathComponent,
        destinationFilename: source.lastPathComponent,
        expectedSize: 7
      )
    ]
  )
}

private func authorizeCopyPlan(
  _ plan: CopyBatchPlan,
  in fixture: RuntimeFixture
) async -> CopyBatchPlan? {
  await fixture.dropPlanner.setResult(.copy(plan))
  let result = await fixture.session.planDrop(
    sourceURLs: plan.items.map(\.sourceURL)
  )
  guard case .copy(let authoritativePlan) = result else {
    return nil
  }
  return authoritativePlan
}

private func waitForCopyStart(_ copying: RuntimeFileCopying) async -> Bool {
  for _ in 0..<2_000 {
    if await copying.callCount() > 0 {
      return true
    }
    await Task.yield()
  }
  return false
}

private func waitForWatcherStop(_ streaming: RuntimeEventStreaming) async -> Bool {
  for _ in 0..<2_000 {
    if await streaming.stopCount() > 0 {
      return true
    }
    await Task.yield()
  }
  return false
}

private func waitForSnapshotReads(
  _ reader: RuntimeSnapshotReader,
  count: Int
) async -> Bool {
  for _ in 0..<2_000 {
    if await reader.callCount() >= count {
      return true
    }
    await Task.yield()
  }
  return false
}

@Test
func runtimeStateBufferKeepsOnlyLatestPendingSnapshot() async throws {
  let first = FolderSnapshot(
    folderIdentity: FolderIdentity(
      resourceIdentifier: nil,
      standardizedURL: URL(fileURLWithPath: "/tmp/SchneeGlassRuntime", isDirectory: true)
    ),
    items: [item(named: "first.txt")],
    isTruncated: false,
    observedAt: Date(timeIntervalSince1970: 1_700_000_002),
    generation: 99
  )
  let latest = FolderSnapshot(
    folderIdentity: first.folderIdentity,
    items: [item(named: "latest.txt")],
    isTruncated: false,
    observedAt: Date(timeIntervalSince1970: 1_700_000_003),
    generation: 100
  )
  let fixture = try makeRuntimeFixture(
    refreshBehaviors: [.snapshot(first), .snapshot(latest)]
  )

  let states = try await fixture.session.start()

  fixture.eventContinuation.yield(.changed)
  fixture.eventContinuation.yield(.changed)
  #expect(await waitForSnapshotReads(fixture.snapshotReader, count: 2))

  var iterator = states.makeAsyncIterator()
  let pending = await iterator.next()
  guard case .ready(let snapshot)? = pending else {
    Issue.record("Expected only the latest ready state to remain buffered")
    await fixture.session.stop()
    return
  }
  #expect(snapshot.items.map(\.displayName) == ["latest.txt"])
  #expect(snapshot.generation == 3)

  await fixture.session.stop()
  #expect(await iterator.next() == nil)
}

@Test
func terminalUnavailableReplacesStalePendingReadyStateAndStillTerminates() async throws {
  let refreshed = FolderSnapshot(
    folderIdentity: FolderIdentity(
      resourceIdentifier: nil,
      standardizedURL: URL(fileURLWithPath: "/tmp/SchneeGlassRuntime", isDirectory: true)
    ),
    items: [item(named: "stale.txt")],
    isTruncated: false,
    observedAt: Date(timeIntervalSince1970: 1_700_000_002),
    generation: 99
  )
  let fixture = try makeRuntimeFixture(
    refreshBehaviors: [.snapshot(refreshed)]
  )

  let states = try await fixture.session.start()

  fixture.eventContinuation.yield(.changed)
  #expect(await waitForSnapshotReads(fixture.snapshotReader, count: 1))
  fixture.eventContinuation.yield(.rootChanged)
  #expect(await waitForWatcherStop(fixture.eventStreaming))

  var iterator = states.makeAsyncIterator()
  #expect(await iterator.next() == .unavailable(.sourceMissing))
  #expect(await iterator.next() == nil)
  #expect(await fixture.accessController.releaseCount() == 1)
}

@Test
func initialStateMayBeSupersededBeforeConsumerStartsReading() async throws {
  let refreshed = FolderSnapshot(
    folderIdentity: FolderIdentity(
      resourceIdentifier: nil,
      standardizedURL: URL(fileURLWithPath: "/tmp/SchneeGlassRuntime", isDirectory: true)
    ),
    items: [item(named: "fresh.txt")],
    isTruncated: false,
    observedAt: Date(timeIntervalSince1970: 1_700_000_002),
    generation: 99
  )
  let fixture = try makeRuntimeFixture(
    refreshBehaviors: [.snapshot(refreshed)]
  )

  let states = try await fixture.session.start()
  fixture.eventContinuation.yield(.changed)
  #expect(await waitForSnapshotReads(fixture.snapshotReader, count: 1))

  var iterator = states.makeAsyncIterator()
  guard case .ready(let snapshot)? = await iterator.next() else {
    Issue.record("Expected refreshed state to supersede the unread initial state")
    await fixture.session.stop()
    return
  }
  #expect(snapshot.items.map(\.displayName) == ["fresh.txt"])

  await fixture.session.stop()
  #expect(await iterator.next() == nil)
}

@Test
func runtimeSessionImmediatelyPublishesInitialSnapshotAndRefreshesOnChange() async throws {
  let refreshed = FolderSnapshot(
    folderIdentity: FolderIdentity(
      resourceIdentifier: nil,
      standardizedURL: URL(fileURLWithPath: "/tmp/SchneeGlassRuntime", isDirectory: true)
    ),
    items: [item(named: "updated.txt")],
    isTruncated: false,
    observedAt: Date(timeIntervalSince1970: 1_700_000_002),
    generation: 999
  )
  let fixture = try makeRuntimeFixture(
    refreshBehaviors: [.snapshot(refreshed)]
  )

  let states = try await fixture.session.start()
  var iterator = states.makeAsyncIterator()

  #expect(await iterator.next() == .empty(fixture.initialSnapshot))

  fixture.eventContinuation.yield(.changed)
  let updatedState = await iterator.next()

  guard case .ready(let snapshot)? = updatedState else {
    Issue.record("Expected ready state after filesystem change")
    return
  }
  #expect(snapshot.generation == 2)
  #expect(snapshot.items.map(\.displayName) == ["updated.txt"])

  await fixture.session.stop()
  #expect(await fixture.eventStreaming.stopCount() == 1)
  #expect(await fixture.accessController.releaseCount() == 1)
}

@Test
func runtimeSessionRecoversAfterTransientSnapshotFailure() async throws {
  let recovered = FolderSnapshot(
    folderIdentity: FolderIdentity(
      resourceIdentifier: nil,
      standardizedURL: URL(fileURLWithPath: "/tmp/SchneeGlassRuntime", isDirectory: true)
    ),
    items: [item(named: "recovered.txt")],
    isTruncated: false,
    observedAt: Date(timeIntervalSince1970: 1_700_000_003),
    generation: 999
  )
  let fixture = try makeRuntimeFixture(
    refreshBehaviors: [.fail, .snapshot(recovered)]
  )

  let states = try await fixture.session.start()
  var iterator = states.makeAsyncIterator()
  _ = await iterator.next()

  fixture.eventContinuation.yield(.changed)
  #expect(await iterator.next() == .failed(.enumerationFailed))

  fixture.eventContinuation.yield(.requiresFullRescan)
  let recoveredState = await iterator.next()
  guard case .ready(let snapshot)? = recoveredState else {
    Issue.record("Expected runtime to recover on the next filesystem event")
    return
  }
  #expect(snapshot.generation == 3)

  await fixture.session.stop()
}

@Test
func rootChangePublishesUnavailableThenStopsWatcherAndAccess() async throws {
  let fixture = try makeRuntimeFixture()
  let states = try await fixture.session.start()
  var iterator = states.makeAsyncIterator()
  _ = await iterator.next()

  fixture.eventContinuation.yield(.rootChanged)

  #expect(await iterator.next() == .unavailable(.sourceMissing))
  #expect(await iterator.next() == nil)
  #expect(await fixture.eventStreaming.stopCount() == 1)
  #expect(await fixture.accessController.releaseCount() == 1)
}

@Test
func runtimeStopIsIdempotentAndFinishesStateStream() async throws {
  let fixture = try makeRuntimeFixture()
  let states = try await fixture.session.start()
  var iterator = states.makeAsyncIterator()
  _ = await iterator.next()

  await fixture.session.stop()
  await fixture.session.stop()

  #expect(await iterator.next() == nil)
  #expect(await fixture.eventStreaming.stopCount() == 1)
  #expect(await fixture.accessController.releaseCount() == 1)
}

@Test
func runtimeSessionCannotBeStartedTwice() async throws {
  let fixture = try makeRuntimeFixture()
  let states = try await fixture.session.start()
  _ = states

  do {
    _ = try await fixture.session.start()
    Issue.record("Expected second start to fail")
  } catch let error as GlassRuntimeSessionError {
    #expect(error == .alreadyStarted)
  }

  await fixture.session.stop()
}

@Test
func runtimeDropPlanningUsesTheSessionsAuthorizedDestination() async throws {
  let fixture = try makeRuntimeFixture()
  let states = try await fixture.session.start()
  _ = states
  let sources = [URL(fileURLWithPath: "/tmp/External/report.txt")]

  let result = await fixture.session.planDrop(sourceURLs: sources)
  let observations = await fixture.dropPlanner.observations()

  #expect(result == .noOperation)
  #expect(observations.sourceURLs == sources)
  #expect(observations.access?.id == fixture.access.id)
  #expect(observations.access?.glassID == fixture.configuration.id)

  await fixture.session.stop()
}

@Test
func runtimeCopyRejectsPlanWithoutPendingAuthorityBeforeMutation() async throws {
  let fixture = try makeRuntimeFixture()
  let states = try await fixture.session.start()
  _ = states
  let plan = try copyPlan(for: fixture)

  do {
    _ = try await fixture.session.executeCopy(plan)
    Issue.record("Expected missing pending-plan authority rejection")
  } catch let error as GlassCopyExecutionError {
    #expect(error == .planNotPending)
  } catch {
    Issue.record("Unexpected error: \(error)")
  }

  #expect(await fixture.fileCopying.callCount() == 0)
  await fixture.session.stop()
}

@Test
func runtimeCopyRejectsExplicitlyAbandonedPlanBeforeMutation() async throws {
  let fixture = try makeRuntimeFixture()
  let states = try await fixture.session.start()
  _ = states
  let candidate = try copyPlan(for: fixture)
  guard let plan = await authorizeCopyPlan(candidate, in: fixture) else {
    Issue.record("Expected authoritative copy plan")
    await fixture.session.stop()
    return
  }

  await fixture.session.abandonCopyPlan(plan)

  do {
    _ = try await fixture.session.executeCopy(plan)
    Issue.record("Expected abandoned-plan rejection")
  } catch let error as GlassCopyExecutionError {
    #expect(error == .planNotPending)
  } catch {
    Issue.record("Unexpected error: \(error)")
  }

  #expect(await fixture.fileCopying.callCount() == 0)
  await fixture.session.stop()
}

@Test
func runtimeCopyRejectsReplayAfterSuccessfulExecution() async throws {
  let fixture = try makeRuntimeFixture()
  let states = try await fixture.session.start()
  _ = states
  let candidate = try copyPlan(for: fixture)
  guard let plan = await authorizeCopyPlan(candidate, in: fixture) else {
    Issue.record("Expected authoritative copy plan")
    await fixture.session.stop()
    return
  }

  let firstResult = try await fixture.session.executeCopy(plan)
  #expect(firstResult.failed == nil)
  #expect(await fixture.fileCopying.callCount() == 1)

  do {
    _ = try await fixture.session.executeCopy(plan)
    Issue.record("Expected replay rejection")
  } catch let error as GlassCopyExecutionError {
    #expect(error == .planNotPending)
  } catch {
    Issue.record("Unexpected error: \(error)")
  }

  #expect(await fixture.fileCopying.callCount() == 1)
  await fixture.session.stop()
}

@Test
func rejectedSameBatchPlanDoesNotConsumeLegitimatePendingAuthority() async throws {
  let fixture = try makeRuntimeFixture()
  let states = try await fixture.session.start()
  _ = states
  let candidate = try copyPlan(for: fixture)
  guard let authoritativePlan = await authorizeCopyPlan(candidate, in: fixture) else {
    Issue.record("Expected authoritative copy plan")
    await fixture.session.stop()
    return
  }

  let forgedSource = URL(fileURLWithPath: "/tmp/External/forged.txt")
  let forgedPlan = try CopyBatchPlan(
    batchID: authoritativePlan.batchID,
    destination: authoritativePlan.destination,
    items: [
      CopyItemPlan(
        sourceURL: forgedSource,
        originalFilename: forgedSource.lastPathComponent,
        destinationFilename: forgedSource.lastPathComponent,
        expectedSize: 9
      )
    ],
    createdAt: authoritativePlan.createdAt
  )

  do {
    _ = try await fixture.session.executeCopy(forgedPlan)
    Issue.record("Expected same-batch mismatched-plan rejection")
  } catch let error as GlassCopyExecutionError {
    #expect(error == .planNotPending)
  } catch {
    Issue.record("Unexpected error: \(error)")
  }

  #expect(await fixture.fileCopying.callCount() == 0)

  let result = try await fixture.session.executeCopy(authoritativePlan)
  #expect(result.failed == nil)
  #expect(await fixture.fileCopying.callCount() == 1)

  await fixture.session.stop()
}

@Test
func runtimeCopyRejectsPlanForAnotherDestinationBeforeMutation() async throws {
  let fixture = try makeRuntimeFixture()
  let states = try await fixture.session.start()
  _ = states
  let validPlan = try copyPlan(for: fixture)
  let otherURL = URL(fileURLWithPath: "/tmp/OtherGlass", isDirectory: true)
  let invalidPlan = try CopyBatchPlan(
    destination: DestinationDescriptor(
      glassID: GlassID(),
      folderIdentity: FolderIdentity(resourceIdentifier: nil, standardizedURL: otherURL),
      url: otherURL,
      capabilities: StorageCapabilities(locationKind: .localFixed, isWritable: true)
    ),
    items: validPlan.items
  )

  do {
    _ = try await fixture.session.executeCopy(invalidPlan)
    Issue.record("Expected destination mismatch")
  } catch let error as GlassCopyExecutionError {
    #expect(error == .destinationMismatch)
  } catch {
    Issue.record("Unexpected error: \(error)")
  }

  #expect(await fixture.fileCopying.callCount() == 0)
  await fixture.session.stop()
}

@Test
func runtimeRejectsSecondCopyWhileOneIsInProgress() async throws {
  let fixture = try makeRuntimeFixture(blockCopy: true)
  let states = try await fixture.session.start()
  _ = states
  let candidate = try copyPlan(for: fixture)
  guard let plan = await authorizeCopyPlan(candidate, in: fixture) else {
    Issue.record("Expected authoritative copy plan")
    await fixture.session.stop()
    return
  }
  let session = fixture.session
  let firstCopy = Task {
    try await session.executeCopy(plan)
  }

  #expect(await waitForCopyStart(fixture.fileCopying))

  do {
    _ = try await session.executeCopy(plan)
    Issue.record("Expected concurrent copy rejection")
  } catch let error as GlassCopyExecutionError {
    #expect(error == .copyInProgress)
  } catch {
    Issue.record("Unexpected error: \(error)")
  }

  fixture.copyGateContinuation?.yield(())
  fixture.copyGateContinuation?.finish()
  _ = try await firstCopy.value
  #expect(await fixture.fileCopying.callCount() == 1)

  await session.stop()
}

@Test
func runtimeStopWaitsForActiveCopyBeforeReleasingSecurityScope() async throws {
  let fixture = try makeRuntimeFixture(blockCopy: true)
  let states = try await fixture.session.start()
  _ = states
  let candidate = try copyPlan(for: fixture)
  guard let plan = await authorizeCopyPlan(candidate, in: fixture) else {
    Issue.record("Expected authoritative copy plan")
    await fixture.session.stop()
    return
  }
  let session = fixture.session
  let copyTask = Task {
    try await session.executeCopy(plan)
  }

  #expect(await waitForCopyStart(fixture.fileCopying))

  let stopTask = Task {
    await session.stop()
  }
  #expect(await waitForWatcherStop(fixture.eventStreaming))
  #expect(await fixture.accessController.releaseCount() == 0)

  fixture.copyGateContinuation?.yield(())
  fixture.copyGateContinuation?.finish()
  _ = try await copyTask.value
  await stopTask.value

  #expect(await fixture.accessController.releaseCount() == 1)
  #expect(await fixture.eventStreaming.stopCount() == 1)
}

@Test
func runtimeCopyBeforeStartIsRejected() async throws {
  let fixture = try makeRuntimeFixture()
  let plan = try copyPlan(for: fixture)

  do {
    _ = try await fixture.session.executeCopy(plan)
    Issue.record("Expected session-not-running rejection")
  } catch let error as GlassCopyExecutionError {
    #expect(error == .sessionNotRunning)
  } catch {
    Issue.record("Unexpected error: \(error)")
  }

  #expect(await fixture.fileCopying.callCount() == 0)
  await fixture.session.stop()
}

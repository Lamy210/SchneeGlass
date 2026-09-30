import FileDomain
import Foundation
import SchneeGlassDomain
import Testing

@testable import SchneeGlassApplication

private enum CopyExecutionAuthorityTestError: Error, Sendable {
  case unexpectedCall
}

private actor CopyExecutionAuthorityAccessController: FolderAccessControlling {
  private var released: [UUID] = []

  func acquire(
    source: FolderSource,
    glassID: GlassID
  ) async throws -> FolderAccessAcquisition {
    _ = source
    _ = glassID
    throw CopyExecutionAuthorityTestError.unexpectedCall
  }

  func release(handleID: UUID) async {
    released.append(handleID)
  }

  func releaseCount() -> Int {
    released.count
  }
}

private actor CopyExecutionAuthorityEventStreaming: FileEventStreaming {
  func subscribe(for access: FolderAccessHandle) async throws -> FileEventSubscription {
    _ = access
    throw CopyExecutionAuthorityTestError.unexpectedCall
  }

  func stop(subscriptionID: UUID) async {
    _ = subscriptionID
  }
}

private struct CopyExecutionAuthoritySnapshotReader: FolderSnapshotReading {
  func snapshot(
    for access: FolderAccessHandle,
    generation: UInt64
  ) async throws -> FolderSnapshot {
    _ = access
    _ = generation
    throw CopyExecutionAuthorityTestError.unexpectedCall
  }
}

private actor CopyExecutionAuthorityDropPlanner: DropPlanning {
  private let result: DropPlan
  private var abandonedRequests: [AuthorizedCopyBatchRequest] = []

  init(result: DropPlan) {
    self.result = result
  }

  func plan(
    sourceURLs: [URL],
    destinationAccess: FolderAccessHandle
  ) async -> DropPlan {
    _ = sourceURLs
    _ = destinationAccess
    return result
  }

  func abandon(_ request: AuthorizedCopyBatchRequest) async {
    abandonedRequests.append(request)
  }

  func abandoned() -> [AuthorizedCopyBatchRequest] {
    abandonedRequests
  }
}

private actor CopyExecutionAuthorityFileCopying: FileCopying {
  private var requests: [AuthorizedCopyBatchRequest] = []

  func copy(_ request: AuthorizedCopyBatchRequest) async -> CopyBatchResult {
    requests.append(request)
    return CopyBatchResult(
      batchID: request.plan.batchID,
      succeeded: request.plan.items.map { item in
        CopyItemSuccess(
          operationID: item.operationID,
          destinationURL: request.destinationAccess.url
            .appendingPathComponent(item.destinationFilename)
        )
      },
      failed: nil,
      notAttempted: []
    )
  }

  func callCount() -> Int {
    requests.count
  }
}

private struct CopyExecutionAuthorityFixture {
  let session: GlassRuntimeSession
  let eventContinuation: AsyncStream<FileEvent>.Continuation
  let planner: CopyExecutionAuthorityDropPlanner
  let fileCopying: CopyExecutionAuthorityFileCopying
  let accessController: CopyExecutionAuthorityAccessController
  let plan: CopyBatchPlan
}

private func makeCopyExecutionAuthorityFixture() throws -> CopyExecutionAuthorityFixture {
  let root = URL(
    fileURLWithPath: "/tmp/SchneeGlassCopyExecutionAuthority",
    isDirectory: true
  )
  let configuration = try GlassConfiguration(
    title: "Copy Execution Authority",
    source: FolderSource(
      bookmarkData: Data([1]),
      lastKnownPath: root.path
    ),
    placement: GlassPlacement(x: 30, y: 40),
    createdAt: Date(timeIntervalSince1970: 1_700_000_000)
  )
  let access = FolderAccessHandle(
    glassID: configuration.id,
    url: root
  )
  let snapshot = FolderSnapshot(
    folderIdentity: FolderIdentity(
      resourceIdentifier: "copy-authority-root",
      standardizedURL: root
    ),
    items: [],
    isTruncated: false,
    observedAt: Date(timeIntervalSince1970: 1_700_000_001),
    generation: 1
  )
  let source = URL(fileURLWithPath: "/tmp/External/copy-authority.txt")
  let plan = try CopyBatchPlan(
    destination: DestinationDescriptor(
      glassID: configuration.id,
      folderIdentity: snapshot.folderIdentity,
      url: root,
      capabilities: StorageCapabilities(
        locationKind: .localFixed,
        isWritable: true,
        supportsCaseSensitiveNames: true,
        supportsSafeDestinationCommit: true
      )
    ),
    items: [
      CopyItemPlan(
        sourceURL: source,
        originalFilename: source.lastPathComponent,
        destinationFilename: source.lastPathComponent,
        expectedSize: 7
      )
    ],
    createdAt: Date(timeIntervalSince1970: 1_700_000_002)
  )
  let events = AsyncStream<FileEvent>.makeStream()
  let planner = CopyExecutionAuthorityDropPlanner(result: .copy(plan))
  let fileCopying = CopyExecutionAuthorityFileCopying()
  let accessController = CopyExecutionAuthorityAccessController()
  let session = GlassRuntimeSession(
    seed: CreatedGlassRuntimeSeed(
      configuration: configuration,
      access: access,
      snapshot: snapshot,
      eventSubscription: FileEventSubscription(events: events.stream)
    ),
    eventStreaming: CopyExecutionAuthorityEventStreaming(),
    snapshotReader: CopyExecutionAuthoritySnapshotReader(),
    accessController: accessController,
    dropPlanning: planner,
    fileCopying: fileCopying
  )

  return CopyExecutionAuthorityFixture(
    session: session,
    eventContinuation: events.continuation,
    planner: planner,
    fileCopying: fileCopying,
    accessController: accessController,
    plan: plan
  )
}

private func expectPlanNotPending(
  session: GlassRuntimeSession,
  plan: CopyBatchPlan
) async {
  do {
    _ = try await session.executeCopy(plan)
    Issue.record("Expected planNotPending")
  } catch let error as GlassCopyExecutionError {
    #expect(error == .planNotPending)
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test
func externallyConstructedPlanCannotExecuteWithoutRuntimeAuthority() async throws {
  let fixture = try makeCopyExecutionAuthorityFixture()
  _ = try await fixture.session.start()

  await expectPlanNotPending(
    session: fixture.session,
    plan: fixture.plan
  )

  #expect(await fixture.fileCopying.callCount() == 0)
  #expect(await fixture.planner.abandoned().isEmpty)

  fixture.eventContinuation.finish()
  await fixture.session.stop()
}

@Test
func explicitlyAbandonedAuthoritativePlanCannotExecute() async throws {
  let fixture = try makeCopyExecutionAuthorityFixture()
  _ = try await fixture.session.start()

  #expect(
    await fixture.session.planDrop(
      sourceURLs: fixture.plan.items.map(\.sourceURL)
    ) == .copy(fixture.plan)
  )
  await fixture.session.abandonCopyPlan(fixture.plan)

  await expectPlanNotPending(
    session: fixture.session,
    plan: fixture.plan
  )

  #expect(await fixture.fileCopying.callCount() == 0)
  #expect(await fixture.planner.abandoned().count == 1)

  fixture.eventContinuation.finish()
  await fixture.session.stop()
}

@Test
func executedAuthoritativePlanCannotBeReplayed() async throws {
  let fixture = try makeCopyExecutionAuthorityFixture()
  _ = try await fixture.session.start()

  #expect(
    await fixture.session.planDrop(
      sourceURLs: fixture.plan.items.map(\.sourceURL)
    ) == .copy(fixture.plan)
  )

  let first = try await fixture.session.executeCopy(fixture.plan)
  #expect(first.failed == nil)
  #expect(await fixture.fileCopying.callCount() == 1)

  await expectPlanNotPending(
    session: fixture.session,
    plan: fixture.plan
  )
  #expect(await fixture.fileCopying.callCount() == 1)

  fixture.eventContinuation.finish()
  await fixture.session.stop()
}

@Test
func sameBatchIDImpostorDoesNotConsumeLegitimatePendingPlan() async throws {
  let fixture = try makeCopyExecutionAuthorityFixture()
  _ = try await fixture.session.start()

  #expect(
    await fixture.session.planDrop(
      sourceURLs: fixture.plan.items.map(\.sourceURL)
    ) == .copy(fixture.plan)
  )

  let originalItem = try #require(fixture.plan.items.first)
  let impostorItem = CopyItemPlan(
    operationID: originalItem.operationID,
    sourceURL: originalItem.sourceURL,
    originalFilename: originalItem.originalFilename,
    destinationFilename: "impostor-(originalItem.destinationFilename)",
    expectedSize: originalItem.expectedSize
  )
  let impostor = try CopyBatchPlan(
    batchID: fixture.plan.batchID,
    destination: fixture.plan.destination,
    items: [impostorItem],
    createdAt: fixture.plan.createdAt
  )

  await expectPlanNotPending(
    session: fixture.session,
    plan: impostor
  )
  #expect(await fixture.fileCopying.callCount() == 0)
  #expect(await fixture.planner.abandoned().isEmpty)

  let legitimate = try await fixture.session.executeCopy(fixture.plan)
  #expect(legitimate.failed == nil)
  #expect(await fixture.fileCopying.callCount() == 1)

  fixture.eventContinuation.finish()
  await fixture.session.stop()
}

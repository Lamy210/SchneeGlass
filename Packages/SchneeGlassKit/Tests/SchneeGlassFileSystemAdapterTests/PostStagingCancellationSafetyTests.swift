import FileDomain
import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing

@testable import SchneeGlassFileSystemAdapter

private actor PostStagingCancellationEnvironment: CopyFileSystemAccessing, StagingCommitting {
  private let sourceURL: URL
  private let sourceSize: Int64
  private var stagedByURL: [URL: (size: Int64, identifier: String)] = [:]
  private var committedURLs: [URL] = []

  init(sourceURL: URL, sourceSize: Int64) {
    self.sourceURL = sourceURL.standardizedFileURL
    self.sourceSize = sourceSize
  }

  func sourceMetadata(at url: URL) async throws -> CopySourceMetadata {
    guard url.standardizedFileURL == sourceURL else {
      throw CopyFileSystemError.sourceUnavailable
    }
    return CopySourceMetadata(size: sourceSize)
  }

  func isWritableDirectory(at url: URL) async -> Bool {
    _ = url
    return true
  }

  func supportsCaseSensitiveNames(at url: URL) async -> Bool? {
    _ = url
    return true
  }

  func itemExists(at url: URL) async -> Bool {
    stagedByURL[url.standardizedFileURL] != nil
      || committedURLs.contains(url.standardizedFileURL)
  }

  func itemExists(at url: URL, operationID: UUID) async -> Bool {
    _ = operationID
    return await itemExists(at: url)
  }

  func copyItem(at sourceURL: URL, to stagingURL: URL) async throws {
    guard sourceURL.standardizedFileURL == self.sourceURL else {
      throw CopyFileSystemError.sourceUnavailable
    }

    let staging = stagingURL.standardizedFileURL
    stagedByURL[staging] = (
      size: sourceSize,
      identifier: "post-staging-cancel:\(staging.lastPathComponent)"
    )
  }

  func regularFileSize(at url: URL) async throws -> Int64 {
    guard let staged = stagedByURL[url.standardizedFileURL] else {
      throw CopyFileSystemError.verificationFailed
    }
    return staged.size
  }

  func resourceIdentifier(at url: URL) async -> String? {
    stagedByURL[url.standardizedFileURL]?.identifier
  }

  func commit(
    stagingURL: URL,
    finalURL: URL,
    authorization: StagingCommitAuthorization
  ) async throws {
    let staging = stagingURL.standardizedFileURL
    guard let staged = stagedByURL[staging],
      staged.size == authorization.expectedSize,
      staged.identifier == authorization.expectedResourceIdentifier
    else {
      throw StagingCommitError.resourceIdentityMismatch
    }

    stagedByURL.removeValue(forKey: staging)
    committedURLs.append(finalURL.standardizedFileURL)
  }

  func committed() -> [URL] {
    committedURLs
  }

  func hasStaging(_ url: URL) -> Bool {
    stagedByURL[url.standardizedFileURL] != nil
  }
}

private actor VerifyingRecordGateStore: PendingCopyRecording {
  private var stored: [UUID: PendingCopyRecord] = [:]
  private var verificationObserved = false
  private var observerContinuation: CheckedContinuation<Void, Never>?
  private var releaseContinuation: CheckedContinuation<Void, Never>?

  func records() async throws -> [PendingCopyRecord] {
    Array(stored.values)
  }

  func upsert(_ record: PendingCopyRecord) async throws {
    stored[record.operationID] = record

    guard record.state == .verifying else {
      return
    }

    verificationObserved = true
    observerContinuation?.resume()
    observerContinuation = nil

    await withCheckedContinuation { continuation in
      releaseContinuation = continuation
    }
  }

  func remove(operationID: UUID) async throws {
    stored.removeValue(forKey: operationID)
  }

  func waitUntilVerifyingRecordIsStored() async {
    guard !verificationObserved else {
      return
    }

    await withCheckedContinuation { continuation in
      observerContinuation = continuation
    }
  }

  func releaseVerifyingWrite() {
    releaseContinuation?.resume()
    releaseContinuation = nil
  }
}

private actor CancelledCommitGate {
  private var started = false
  private var observerContinuation: CheckedContinuation<Void, Never>?
  private var releaseContinuation: CheckedContinuation<Void, Never>?

  func wait() async {
    started = true
    observerContinuation?.resume()
    observerContinuation = nil

    await withCheckedContinuation { continuation in
      releaseContinuation = continuation
    }
  }

  func waitUntilStarted() async {
    guard !started else {
      return
    }

    await withCheckedContinuation { continuation in
      observerContinuation = continuation
    }
  }

  func release() {
    releaseContinuation?.resume()
    releaseContinuation = nil
  }
}

private func makePostStagingCancellationRequest(
  destination: URL,
  source: URL,
  size: Int64
) throws -> AuthorizedCopyBatchRequest {
  let destinationURL = destination.standardizedFileURL
  let glassID = GlassID()
  let descriptor = DestinationDescriptor(
    glassID: glassID,
    folderIdentity: FolderIdentity(
      resourceIdentifier: nil,
      standardizedURL: destinationURL
    ),
    url: destinationURL,
    capabilities: StorageCapabilities(
      locationKind: .localFixed,
      isWritable: true,
      supportsCaseSensitiveNames: true
    )
  )
  let item = CopyItemPlan(
    sourceURL: source.standardizedFileURL,
    originalFilename: source.lastPathComponent,
    destinationFilename: "payload.txt",
    expectedSize: size
  )

  return AuthorizedCopyBatchRequest(
    plan: try CopyBatchPlan(destination: descriptor, items: [item]),
    destinationAccess: FolderAccessHandle(
      glassID: glassID,
      url: destinationURL
    )
  )
}

private func makePinnedCancellationRequest(
  destination: URL,
  source: URL
) throws -> (request: AuthorizedCopyBatchRequest, item: CopyItemPlan) {
  let values = try destination.resourceValues(forKeys: [
    .volumeIdentifierKey,
    .fileResourceIdentifierKey,
    .volumeSupportsCaseSensitiveNamesKey,
  ])
  let resourceIdentifier = values.fileResourceIdentifier.map { String(describing: $0) }
  let glassID = GlassID()
  let access = FolderAccessHandle(
    glassID: glassID,
    url: destination,
    fingerprint: ResourceFingerprint(
      volumeIdentifier: values.volumeIdentifier.map { String(describing: $0) },
      resourceIdentifier: resourceIdentifier
    )
  )
  let descriptor = DestinationDescriptor(
    glassID: glassID,
    folderIdentity: FolderIdentity(
      resourceIdentifier: resourceIdentifier,
      standardizedURL: destination
    ),
    url: destination,
    capabilities: StorageCapabilities(
      locationKind: .localFixed,
      isWritable: true,
      supportsCaseSensitiveNames: values.volumeSupportsCaseSensitiveNames
    )
  )
  let item = CopyItemPlan(
    sourceURL: source,
    originalFilename: source.lastPathComponent,
    destinationFilename: "payload.txt",
    expectedSize: nil
  )

  return (
    AuthorizedCopyBatchRequest(
      plan: try CopyBatchPlan(destination: descriptor, items: [item]),
      destinationAccess: access
    ),
    item
  )
}

@Test
func safeCopyCancellationAfterVerificationKeepsStagingAndSkipsFinalCommit() async throws {
  let destination = URL(fileURLWithPath: "/tmp/schneeglass-post-staging-cancel", isDirectory: true)
  let source = URL(fileURLWithPath: "/tmp/schneeglass-post-staging-source.txt")
  let environment = PostStagingCancellationEnvironment(sourceURL: source, sourceSize: 17)
  let store = VerifyingRecordGateStore()
  let engine = SafeFileCopyEngine(
    fileSystem: environment,
    committer: environment,
    recoveryStore: store
  )
  let request = try makePostStagingCancellationRequest(
    destination: destination,
    source: source,
    size: 17
  )
  let item = request.plan.items[0]
  let stagingURL =
    destination
    .appendingPathComponent(
      ".schneeglass-copy-\(item.operationID.uuidString.lowercased()).partial"
    )
    .standardizedFileURL

  let copyTask = Task {
    await engine.copy(request)
  }

  await store.waitUntilVerifyingRecordIsStored()
  copyTask.cancel()
  await store.releaseVerifyingWrite()

  let result = await copyTask.value

  #expect(result.succeeded.isEmpty)
  #expect(
    result.failed
      == CopyItemFailure(
        operationID: item.operationID,
        reason: .cancelled
      )
  )
  #expect(await environment.committed().isEmpty)
  #expect(await environment.hasStaging(stagingURL))

  let records = try await store.records()
  #expect(records.count == 1)
  #expect(records.first?.operationID == item.operationID)
  #expect(records.first?.state == .verifying)
}

@Test
func cancelledPinnedCommitTaskDoesNotRenameStagingIntoFinalDestination() async throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent(
      "schneeglass-cancelled-pinned-commit-\(UUID().uuidString)",
      isDirectory: true
    )
  let destination = root.appendingPathComponent("destination", isDirectory: true)
  try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let source = root.appendingPathComponent("source.txt")
  try Data("source".utf8).write(to: source)

  let fixture = try makePinnedCancellationRequest(
    destination: destination,
    source: source
  )
  let leases = DestinationDirectoryLeaseRegistry()
  try await leases.bind(fixture.request)

  let stagingFilename = DestinationDirectoryLeaseRegistry.stagingFilename(
    operationID: fixture.item.operationID
  )
  let staging = destination.appendingPathComponent(stagingFilename)
  let payload = Data("staged-payload".utf8)
  try payload.write(to: staging)

  guard
    let token = try PendingCopyFileIdentity.createToken(
      at: staging,
      fileManager: .default
    )
  else {
    Issue.record("Expected staging ownership token")
    await leases.release(batchID: fixture.request.plan.batchID)
    return
  }

  let final = destination.appendingPathComponent(fixture.item.destinationFilename)
  let committer = PinnedDestinationStagingCommitter(destinationLeases: leases)
  let gate = CancelledCommitGate()

  let commitTask = Task {
    await gate.wait()
    try await committer.commit(
      stagingURL: staging,
      finalURL: final,
      authorization: StagingCommitAuthorization(
        expectedSize: Int64(payload.count),
        expectedResourceIdentifier: token
      )
    )
  }

  await gate.waitUntilStarted()
  commitTask.cancel()
  await gate.release()

  do {
    try await commitTask.value
    Issue.record("Expected cancelled pinned commit")
  } catch let error as CopyFileSystemError {
    #expect(error == .cancelled)
  } catch {
    Issue.record("Expected CopyFileSystemError.cancelled, got \(error)")
  }

  #expect(try Data(contentsOf: staging) == payload)
  #expect(!FileManager.default.fileExists(atPath: final.path))

  await leases.release(batchID: fixture.request.plan.batchID)
  #expect(await leases.activeLeaseCount() == 0)
}

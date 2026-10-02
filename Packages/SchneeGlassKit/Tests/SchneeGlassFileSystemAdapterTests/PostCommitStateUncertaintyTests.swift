import Darwin
import FileDomain
import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing

@testable import SchneeGlassFileSystemAdapter

private actor PostCommitUncertaintyEnvironment: CopyFileSystemAccessing, StagingCommitting {
  private let source: URL
  private let size: Int64
  private var existing: Set<URL> = []
  private var stagedIdentifier: String?

  init(source: URL, size: Int64) {
    self.source = source.standardizedFileURL
    self.size = size
  }

  func sourceMetadata(at url: URL) async throws -> CopySourceMetadata {
    guard url.standardizedFileURL == source else {
      throw CopyFileSystemError.sourceUnavailable
    }
    return CopySourceMetadata(size: size)
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
    existing.contains(url.standardizedFileURL)
  }

  func copyItem(at sourceURL: URL, to stagingURL: URL) async throws {
    guard sourceURL.standardizedFileURL == source else {
      throw CopyFileSystemError.sourceUnavailable
    }
    let staging = stagingURL.standardizedFileURL
    existing.insert(staging)
    stagedIdentifier = "post-commit-test:\(staging.path)"
  }

  func regularFileSize(at url: URL) async throws -> Int64 {
    guard existing.contains(url.standardizedFileURL) else {
      throw CopyFileSystemError.verificationFailed
    }
    return size
  }

  func resourceIdentifier(at url: URL) async -> String? {
    guard existing.contains(url.standardizedFileURL) else {
      return nil
    }
    return stagedIdentifier
  }

  func commit(
    stagingURL: URL,
    finalURL: URL,
    authorization: StagingCommitAuthorization
  ) async throws {
    let staging = stagingURL.standardizedFileURL
    let final = finalURL.standardizedFileURL
    guard existing.contains(staging),
      authorization.expectedSize == size,
      authorization.expectedResourceIdentifier == stagedIdentifier
    else {
      throw StagingCommitError.resourceIdentityMismatch
    }

    existing.remove(staging)
    existing.insert(final)
    throw StagingCommitError.postCommitVerificationFailed
  }

  func contains(_ url: URL) -> Bool {
    existing.contains(url.standardizedFileURL)
  }
}

private actor PostCommitUncertaintyStore: PendingCopyRecording {
  private var stored: [UUID: PendingCopyRecord] = [:]

  func records() async throws -> [PendingCopyRecord] {
    Array(stored.values)
  }

  func upsert(_ record: PendingCopyRecord) async throws {
    stored[record.operationID] = record
  }

  func remove(operationID: UUID) async throws {
    stored.removeValue(forKey: operationID)
  }
}

private func makePostCommitUncertaintyRequest(
  source: URL,
  destination: URL,
  size: Int64
) throws -> AuthorizedCopyBatchRequest {
  let glassID = GlassID()
  let descriptor = DestinationDescriptor(
    glassID: glassID,
    folderIdentity: FolderIdentity(
      resourceIdentifier: nil,
      standardizedURL: destination
    ),
    url: destination,
    capabilities: StorageCapabilities(
      locationKind: .localFixed,
      isWritable: true,
      supportsCaseSensitiveNames: true
    )
  )
  let plan = try CopyBatchPlan(
    destination: descriptor,
    items: [
      CopyItemPlan(
        sourceURL: source,
        originalFilename: source.lastPathComponent,
        destinationFilename: "payload.txt",
        expectedSize: size
      )
    ]
  )
  return AuthorizedCopyBatchRequest(
    plan: plan,
    destinationAccess: FolderAccessHandle(glassID: glassID, url: destination)
  )
}

@Test
func safeCopyReportsUnknownStateWhenCommitMutationAlreadyOccurred() async throws {
  let source = URL(fileURLWithPath: "/tmp/schneeglass-post-commit-source.txt")
  let destination = URL(
    fileURLWithPath: "/tmp/schneeglass-post-commit-destination",
    isDirectory: true
  )
  let environment = PostCommitUncertaintyEnvironment(source: source, size: 64)
  let store = PostCommitUncertaintyStore()
  let request = try makePostCommitUncertaintyRequest(
    source: source,
    destination: destination,
    size: 64
  )
  let engine = SafeFileCopyEngine(
    fileSystem: environment,
    committer: environment,
    recoveryStore: store
  )

  let result = await engine.copy(request)
  let finalURL = destination.appendingPathComponent("payload.txt")
  let records = try await store.records()

  #expect(result.succeeded.isEmpty)
  #expect(result.failed?.reason == .commitStateUnknown)
  #expect(await environment.contains(finalURL))
  #expect(records.count == 1)
  #expect(records.first?.state == .committing)
}

@Test
func committedEntryMismatchUsesPostCommitSpecificError() throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent(
      "schneeglass-post-commit-identity-\(UUID().uuidString)",
      isDirectory: true
    )
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let staging = root.appendingPathComponent("staging.tmp")
  let final = root.appendingPathComponent("final.txt")
  try Data("staging".utf8).write(to: staging)
  try Data("replacement".utf8).write(to: final)

  let directoryDescriptor = open(
    root.path,
    O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
  )
  let stagingDescriptor = open(
    staging.path,
    O_RDONLY | O_CLOEXEC | O_NOFOLLOW
  )
  #expect(directoryDescriptor >= 0)
  #expect(stagingDescriptor >= 0)
  guard directoryDescriptor >= 0, stagingDescriptor >= 0 else {
    return
  }
  defer {
    close(stagingDescriptor)
    close(directoryDescriptor)
  }

  do {
    try PinnedDestinationStagingCommitter.requireCommittedEntryMatches(
      stagingDescriptor: stagingDescriptor,
      directoryDescriptor: directoryDescriptor,
      filename: final.lastPathComponent
    )
    Issue.record("Expected post-commit verification failure")
  } catch let error as StagingCommitError {
    #expect(error == .postCommitVerificationFailed)
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

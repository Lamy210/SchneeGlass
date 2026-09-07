import FileDomain
import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing
@testable import SchneeGlassFileSystemAdapter

private enum SafeCopyTestError: Error, Sendable {
    case injected
}

private actor FakeCopyEnvironment: CopyFileSystemAccessing, StagingCommitting {
    private var sourceSizes: [URL: Int64]
    private var existingItems: Set<URL>
    private var stagedSizes: [URL: Int64] = [:]
    private var stagedResourceIdentifiers: [URL: String] = [:]
    private var stagingSizeOverrides: [URL: Int64]
    private var copyFailures: [URL: CopyFileSystemError]
    private var collisionOnCommit = false
    private var copyCalls: [URL] = []
    private var commitCalls: [(staging: URL, final: URL)] = []

    init(
        sources: [URL: Int64],
        existingItems: Set<URL> = [],
        stagingSizeOverrides: [URL: Int64] = [:],
        copyFailures: [URL: CopyFileSystemError] = [:]
    ) {
        self.sourceSizes = Dictionary(
            uniqueKeysWithValues: sources.map { ($0.key.standardizedFileURL, $0.value) }
        )
        self.existingItems = Set(existingItems.map(\.standardizedFileURL))
        self.stagingSizeOverrides = Dictionary(
            uniqueKeysWithValues: stagingSizeOverrides.map { ($0.key.standardizedFileURL, $0.value) }
        )
        self.copyFailures = Dictionary(
            uniqueKeysWithValues: copyFailures.map { ($0.key.standardizedFileURL, $0.value) }
        )
    }

    func sourceMetadata(at url: URL) async throws -> CopySourceMetadata {
        let source = url.standardizedFileURL
        guard let size = sourceSizes[source] else {
            throw CopyFileSystemError.sourceUnavailable
        }
        return CopySourceMetadata(size: size)
    }

    func isWritableDirectory(at url: URL) async -> Bool {
        true
    }

    func itemExists(at url: URL) async -> Bool {
        existingItems.contains(url.standardizedFileURL)
    }

    func copyItem(at sourceURL: URL, to stagingURL: URL) async throws {
        let source = sourceURL.standardizedFileURL
        let staging = stagingURL.standardizedFileURL
        copyCalls.append(source)

        if let failure = copyFailures[source] {
            throw failure
        }

        guard let sourceSize = sourceSizes[source] else {
            throw CopyFileSystemError.sourceUnavailable
        }

        guard !existingItems.contains(staging) else {
            throw CopyFileSystemError.collision
        }

        existingItems.insert(staging)
        stagedSizes[staging] = stagingSizeOverrides[source] ?? sourceSize
        stagedResourceIdentifiers[staging] = "fake-resource:\(staging.path)"
    }

    func regularFileSize(at url: URL) async throws -> Int64 {
        let target = url.standardizedFileURL
        guard let size = stagedSizes[target] else {
            throw CopyFileSystemError.verificationFailed
        }
        return size
    }

    func resourceIdentifier(at url: URL) async -> String? {
        stagedResourceIdentifiers[url.standardizedFileURL]
    }

    func commit(stagingURL: URL, finalURL: URL) async throws {
        let staging = stagingURL.standardizedFileURL
        let final = finalURL.standardizedFileURL
        commitCalls.append((staging, final))

        guard existingItems.contains(staging) else {
            throw StagingCommitError.stagingMissing
        }

        if collisionOnCommit {
            existingItems.insert(final)
            throw StagingCommitError.collision
        }

        guard !existingItems.contains(final) else {
            throw StagingCommitError.collision
        }

        existingItems.remove(staging)
        stagedSizes.removeValue(forKey: staging)
        stagedResourceIdentifiers.removeValue(forKey: staging)
        existingItems.insert(final)
    }

    func enableCollisionOnCommit() {
        collisionOnCommit = true
    }

    func copyCallCount() -> Int {
        copyCalls.count
    }

    func commitCallCount() -> Int {
        commitCalls.count
    }

    func exists(_ url: URL) -> Bool {
        existingItems.contains(url.standardizedFileURL)
    }
}

private actor FakePendingCopyStore: PendingCopyRecording {
    private var stored: [UUID: PendingCopyRecord] = [:]
    private let failRemoval: Bool

    init(failRemoval: Bool = false) {
        self.failRemoval = failRemoval
    }

    func records() async throws -> [PendingCopyRecord] {
        stored.values.sorted { $0.operationID.uuidString < $1.operationID.uuidString }
    }

    func upsert(_ record: PendingCopyRecord) async throws {
        stored[record.operationID] = record
    }

    func remove(operationID: UUID) async throws {
        if failRemoval {
            throw SafeCopyTestError.injected
        }
        stored.removeValue(forKey: operationID)
    }
}

private func makeCopyRequest(
    destination: URL,
    sources: [(URL, String, Int64?)]
) throws -> AuthorizedCopyBatchRequest {
    let glassID = GlassID()
    let destinationURL = destination.standardizedFileURL
    let descriptor = DestinationDescriptor(
        glassID: glassID,
        folderIdentity: FolderIdentity(
            resourceIdentifier: nil,
            standardizedURL: destinationURL
        ),
        url: destinationURL,
        capabilities: StorageCapabilities(
            locationKind: .localFixed,
            isWritable: true
        )
    )
    let items = sources.map { source, filename, size in
        CopyItemPlan(
            sourceURL: source.standardizedFileURL,
            originalFilename: source.lastPathComponent,
            destinationFilename: filename,
            expectedSize: size
        )
    }
    let plan = try CopyBatchPlan(destination: descriptor, items: items)
    return AuthorizedCopyBatchRequest(
        plan: plan,
        destinationAccess: FolderAccessHandle(
            glassID: glassID,
            url: destinationURL
        )
    )
}

@Test
func preflightCollisionPreventsEntireBatchMutation() async throws {
    let destination = URL(fileURLWithPath: "/tmp/schneeglass-copy-preflight", isDirectory: true)
    let first = URL(fileURLWithPath: "/tmp/source-a.txt")
    let second = URL(fileURLWithPath: "/tmp/source-b.txt")
    let collisionURL = destination.appendingPathComponent("source-b.txt")
    let environment = FakeCopyEnvironment(
        sources: [first: 10, second: 20],
        existingItems: [collisionURL]
    )
    let recovery = FakePendingCopyStore()
    let request = try makeCopyRequest(
        destination: destination,
        sources: [
            (first, "source-a.txt", 10),
            (second, "source-b.txt", 20),
        ]
    )
    let engine = SafeFileCopyEngine(
        fileSystem: environment,
        committer: environment,
        recoveryStore: recovery
    )

    let result = await engine.copy(request)
    let copyCallCount = await environment.copyCallCount()
    let pending = try await recovery.records()

    #expect(result.succeeded.isEmpty)
    #expect(result.failed?.operationID == request.plan.items[1].operationID)
    #expect(result.failed?.reason == .collision)
    #expect(result.notAttempted.count == 1)
    #expect(copyCallCount == 0)
    #expect(pending.isEmpty)
}

@Test
func midBatchFailureKeepsEarlierSuccessAndDoesNotRollback() async throws {
    let destination = URL(fileURLWithPath: "/tmp/schneeglass-copy-midbatch", isDirectory: true)
    let first = URL(fileURLWithPath: "/tmp/first-success.txt")
    let second = URL(fileURLWithPath: "/tmp/second-failure.txt")
    let environment = FakeCopyEnvironment(
        sources: [first: 11, second: 22],
        copyFailures: [second: .insufficientSpace]
    )
    let recovery = FakePendingCopyStore()
    let request = try makeCopyRequest(
        destination: destination,
        sources: [
            (first, "first-success.txt", 11),
            (second, "second-failure.txt", 22),
        ]
    )
    let engine = SafeFileCopyEngine(
        fileSystem: environment,
        committer: environment,
        recoveryStore: recovery
    )

    let result = await engine.copy(request)
    let firstFinal = destination.appendingPathComponent("first-success.txt")
    let firstExists = await environment.exists(firstFinal)
    let firstSourceStillExists = try await environment.sourceMetadata(at: first)
    let pending = try await recovery.records()

    #expect(result.succeeded.map(\.operationID) == [request.plan.items[0].operationID])
    #expect(result.failed?.operationID == request.plan.items[1].operationID)
    #expect(result.failed?.reason == .insufficientSpace)
    #expect(result.notAttempted.isEmpty)
    #expect(firstExists)
    #expect(firstSourceStillExists.size == 11)
    #expect(pending.isEmpty)
}

@Test
func verificationFailurePreservesStagingIdentityAndRecoveryRecord() async throws {
    let destination = URL(fileURLWithPath: "/tmp/schneeglass-copy-verify", isDirectory: true)
    let source = URL(fileURLWithPath: "/tmp/verify-source.txt")
    let environment = FakeCopyEnvironment(
        sources: [source: 100],
        stagingSizeOverrides: [source: 99]
    )
    let recovery = FakePendingCopyStore()
    let request = try makeCopyRequest(
        destination: destination,
        sources: [(source, "verify-source.txt", 100)]
    )
    let engine = SafeFileCopyEngine(
        fileSystem: environment,
        committer: environment,
        recoveryStore: recovery
    )

    let result = await engine.copy(request)
    let operationID = request.plan.items[0].operationID
    let staging = destination.appendingPathComponent(
        ".schneeglass-copy-\(operationID.uuidString.lowercased()).partial"
    )
    let stagingExists = await environment.exists(staging)
    let pending = try await recovery.records()

    #expect(result.failed?.reason == .verificationFailed)
    #expect(stagingExists)
    #expect(pending.count == 1)
    #expect(pending.first?.operationID == operationID)
    #expect(pending.first?.state == .verifying)
    #expect(pending.first?.stagingResourceIdentifier == "fake-resource:\(staging.path)")
}

@Test
func commitCollisionRacePreservesStagingIdentityForRecovery() async throws {
    let destination = URL(fileURLWithPath: "/tmp/schneeglass-copy-race", isDirectory: true)
    let source = URL(fileURLWithPath: "/tmp/race-source.txt")
    let environment = FakeCopyEnvironment(sources: [source: 30])
    await environment.enableCollisionOnCommit()
    let recovery = FakePendingCopyStore()
    let request = try makeCopyRequest(
        destination: destination,
        sources: [(source, "race-source.txt", 30)]
    )
    let engine = SafeFileCopyEngine(
        fileSystem: environment,
        committer: environment,
        recoveryStore: recovery
    )

    let result = await engine.copy(request)
    let operationID = request.plan.items[0].operationID
    let staging = destination.appendingPathComponent(
        ".schneeglass-copy-\(operationID.uuidString.lowercased()).partial"
    )
    let stagingExists = await environment.exists(staging)
    let pending = try await recovery.records()

    #expect(result.failed?.reason == .collision)
    #expect(stagingExists)
    #expect(pending.count == 1)
    #expect(pending.first?.state == .committing)
    #expect(pending.first?.stagingResourceIdentifier == "fake-resource:\(staging.path)")
}

@Test
func recoveryMetadataCleanupFailureKeepsCommittedIdentityMetadata() async throws {
    let destination = URL(fileURLWithPath: "/tmp/schneeglass-copy-cleanup", isDirectory: true)
    let source = URL(fileURLWithPath: "/tmp/cleanup-source.txt")
    let environment = FakeCopyEnvironment(sources: [source: 50])
    let recovery = FakePendingCopyStore(failRemoval: true)
    let request = try makeCopyRequest(
        destination: destination,
        sources: [(source, "cleanup-source.txt", 50)]
    )
    let engine = SafeFileCopyEngine(
        fileSystem: environment,
        committer: environment,
        recoveryStore: recovery
    )

    let result = await engine.copy(request)
    let operationID = request.plan.items[0].operationID
    let staging = destination.appendingPathComponent(
        ".schneeglass-copy-\(operationID.uuidString.lowercased()).partial"
    )
    let finalURL = destination.appendingPathComponent("cleanup-source.txt")
    let finalExists = await environment.exists(finalURL)
    let pending = try await recovery.records()

    #expect(result.failed == nil)
    #expect(result.succeeded.count == 1)
    #expect(result.succeeded.first?.recoveryMetadataCleanupPending == true)
    #expect(finalExists)
    #expect(pending.count == 1)
    #expect(pending.first?.state == .committing)
    #expect(pending.first?.stagingResourceIdentifier == "fake-resource:\(staging.path)")
}

@Test
func internalCommitterRejectsStagingNameWithoutOperationUUID() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("schneeglass-committer-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let staging = root.appendingPathComponent(".schneeglass-copy-not-a-uuid.partial")
    let final = root.appendingPathComponent("final.txt")
    try Data("staging".utf8).write(to: staging)
    let committer = InternalStagingCommitter()

    do {
        try await committer.commit(stagingURL: staging, finalURL: final)
        Issue.record("Expected invalid staging filename rejection")
    } catch let error as StagingCommitError {
        #expect(error == .invalidStagingFile)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(FileManager.default.fileExists(atPath: staging.path))
    #expect(!FileManager.default.fileExists(atPath: final.path))
}

@Test
func realFilesystemCopyLeavesSourceUntouchedAndRemovesOwnedPartial() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("schneeglass-real-copy-\(UUID().uuidString)", isDirectory: true)
    let sourceDirectory = root.appendingPathComponent("source", isDirectory: true)
    let destinationDirectory = root.appendingPathComponent("destination", isDirectory: true)
    let recoveryDirectory = root.appendingPathComponent("recovery", isDirectory: true)
    try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let sourceURL = sourceDirectory.appendingPathComponent("payload.txt")
    let payload = Data("SchneeGlass safe copy payload".utf8)
    try payload.write(to: sourceURL, options: .atomic)

    let recoveryStore = JSONPendingCopyStore(baseDirectory: recoveryDirectory)
    let request = try makeCopyRequest(
        destination: destinationDirectory,
        sources: [(sourceURL, "payload.txt", Int64(payload.count))]
    )
    let engine = SafeFileCopyEngine(recoveryStore: recoveryStore)

    let result = await engine.copy(request)
    let finalURL = destinationDirectory.appendingPathComponent("payload.txt")
    let finalPayload = try Data(contentsOf: finalURL)
    let sourcePayload = try Data(contentsOf: sourceURL)
    let destinationEntries = try FileManager.default.contentsOfDirectory(atPath: destinationDirectory.path)
    let pending = try await recoveryStore.records()

    #expect(result.failed == nil)
    #expect(result.succeeded.count == 1)
    #expect(result.succeeded.first?.recoveryMetadataCleanupPending == false)
    #expect(sourcePayload == payload)
    #expect(finalPayload == payload)
    #expect(destinationEntries == ["payload.txt"])
    #expect(pending.isEmpty)
}

import FileDomain
import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing
@testable import SchneeGlassFileSystemAdapter

private actor IdentityUnavailableCopyEnvironment: CopyFileSystemAccessing, StagingCommitting {
    private let source: URL
    private let sourceSize: Int64
    private var stagingExists = false
    private var commitCalls = 0

    init(source: URL, sourceSize: Int64) {
        self.source = source.standardizedFileURL
        self.sourceSize = sourceSize
    }

    func sourceMetadata(at url: URL) async throws -> CopySourceMetadata {
        guard url.standardizedFileURL == source else {
            throw CopyFileSystemError.sourceUnavailable
        }
        return CopySourceMetadata(size: sourceSize)
    }

    func isWritableDirectory(at url: URL) async -> Bool { true }
    func supportsCaseSensitiveNames(at url: URL) async -> Bool? { true }

    func itemExists(at url: URL) async -> Bool {
        url.lastPathComponent.hasPrefix(".schneeglass-copy-") && stagingExists
    }

    func copyItem(at sourceURL: URL, to stagingURL: URL) async throws {
        stagingExists = true
    }

    func regularFileSize(at url: URL) async throws -> Int64 {
        sourceSize
    }

    func resourceIdentifier(at url: URL) async -> String? {
        nil
    }

    func commit(stagingURL: URL, finalURL: URL) async throws {
        commitCalls += 1
    }

    func commitCallCount() -> Int { commitCalls }
}

private actor IdentityPendingStore: PendingCopyRecording {
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

private func makeIdentityCopyRequest(
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
                destinationFilename: source.lastPathComponent,
                expectedSize: size
            )
        ]
    )
    return AuthorizedCopyBatchRequest(
        plan: plan,
        destinationAccess: FolderAccessHandle(
            glassID: glassID,
            url: destination
        )
    )
}

@Test
func copyFailsClosedWhenStagingResourceIdentityIsUnavailable() async throws {
    let source = URL(fileURLWithPath: "/tmp/schneeglass-identity-source.txt")
    let destination = URL(fileURLWithPath: "/tmp/schneeglass-identity-destination", isDirectory: true)
    let environment = IdentityUnavailableCopyEnvironment(source: source, sourceSize: 32)
    let pendingStore = IdentityPendingStore()
    let request = try makeIdentityCopyRequest(
        source: source,
        destination: destination,
        size: 32
    )
    let engine = SafeFileCopyEngine(
        fileSystem: environment,
        committer: environment,
        recoveryStore: pendingStore
    )

    let result = await engine.copy(request)
    let records = try await pendingStore.records()

    #expect(result.succeeded.isEmpty)
    #expect(result.failed?.reason == .verificationFailed)
    #expect(await environment.commitCallCount() == 0)
    #expect(records.count == 1)
    #expect(records.first?.state == .verifying)
    #expect(records.first?.stagingResourceIdentifier == nil)
}

@Test
func internalCommitterRejectsSameSizeStagingIdentityReplacement() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("schneeglass-staging-identity-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let operationID = UUID()
    let staging = root.appendingPathComponent(
        ".schneeglass-copy-\(operationID.uuidString.lowercased()).partial"
    )
    let final = root.appendingPathComponent("payload.txt")
    let original = Data("original".utf8)
    let replacement = Data("replaced".utf8)
    #expect(original.count == replacement.count)

    try original.write(to: staging)
    let originalValues = try staging.resourceValues(forKeys: [.fileResourceIdentifierKey])
    let originalIdentity = try #require(
        originalValues.fileResourceIdentifier.map { String(describing: $0) }
    )
    let authorization = StagingCommitAuthorization(
        expectedSize: Int64(original.count),
        expectedResourceIdentifier: originalIdentity
    )

    try FileManager.default.removeItem(at: staging)
    try replacement.write(to: staging)

    let committer = InternalStagingCommitter()
    do {
        try await committer.commit(
            stagingURL: staging,
            finalURL: final,
            authorization: authorization
        )
        Issue.record("Expected staging identity replacement to be rejected")
    } catch let error as StagingCommitError {
        #expect(error == .resourceIdentityMismatch)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(FileManager.default.fileExists(atPath: staging.path))
    #expect(!FileManager.default.fileExists(atPath: final.path))
    #expect(try Data(contentsOf: staging) == replacement)
}

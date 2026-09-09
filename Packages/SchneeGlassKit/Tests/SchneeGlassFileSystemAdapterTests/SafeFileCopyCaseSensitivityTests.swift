import FileDomain
import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing
@testable import SchneeGlassFileSystemAdapter

private actor CaseSensitivityCopyEnvironment: CopyFileSystemAccessing, StagingCommitting {
    private let sources: [URL: Int64]
    private let caseSensitive: Bool?
    private var copyCalls = 0

    init(sources: [URL: Int64], caseSensitive: Bool?) {
        self.sources = Dictionary(
            uniqueKeysWithValues: sources.map { ($0.key.standardizedFileURL, $0.value) }
        )
        self.caseSensitive = caseSensitive
    }

    func sourceMetadata(at url: URL) async throws -> CopySourceMetadata {
        guard let size = sources[url.standardizedFileURL] else {
            throw CopyFileSystemError.sourceUnavailable
        }
        return CopySourceMetadata(size: size)
    }

    func isWritableDirectory(at url: URL) async -> Bool { true }

    func supportsCaseSensitiveNames(at url: URL) async -> Bool? {
        caseSensitive
    }

    func itemExists(at url: URL) async -> Bool { false }

    func copyItem(at sourceURL: URL, to stagingURL: URL) async throws {
        copyCalls += 1
    }

    func regularFileSize(at url: URL) async throws -> Int64 {
        throw CopyFileSystemError.verificationFailed
    }

    func resourceIdentifier(at url: URL) async -> String? { nil }

    func commit(
        stagingURL: URL,
        finalURL: URL,
        authorization: StagingCommitAuthorization
    ) async throws {
        _ = authorization
        throw StagingCommitError.commitFailed
    }

    func copyCallCount() -> Int { copyCalls }
}

private actor CaseSensitivityPendingStore: PendingCopyRecording {
    func records() async throws -> [PendingCopyRecord] { [] }
    func upsert(_ record: PendingCopyRecord) async throws {}
    func remove(operationID: UUID) async throws {}
}

private func caseSensitivityCopyRequest() throws -> AuthorizedCopyBatchRequest {
    let destination = URL(fileURLWithPath: "/tmp/CaseInsensitiveDestination", isDirectory: true)
    let glassID = GlassID()
    let descriptor = DestinationDescriptor(
        glassID: glassID,
        folderIdentity: FolderIdentity(resourceIdentifier: nil, standardizedURL: destination),
        url: destination,
        capabilities: StorageCapabilities(
            locationKind: .localFixed,
            isWritable: true,
            supportsCaseSensitiveNames: false
        )
    )
    let first = URL(fileURLWithPath: "/tmp/A/Report.txt")
    let second = URL(fileURLWithPath: "/tmp/B/report.txt")
    let plan = try CopyBatchPlan(
        destination: descriptor,
        items: [
            CopyItemPlan(
                sourceURL: first,
                originalFilename: "Report.txt",
                destinationFilename: "Report.txt",
                expectedSize: 1
            ),
            CopyItemPlan(
                sourceURL: second,
                originalFilename: "report.txt",
                destinationFilename: "report.txt",
                expectedSize: 1
            ),
        ]
    )
    return AuthorizedCopyBatchRequest(
        plan: plan,
        destinationAccess: FolderAccessHandle(glassID: glassID, url: destination)
    )
}

@Test
func safeCopyRejectsCaseInsensitiveBatchCollisionBeforeMutation() async throws {
    let request = try caseSensitivityCopyRequest()
    let first = request.plan.items[0].sourceURL
    let second = request.plan.items[1].sourceURL
    let environment = CaseSensitivityCopyEnvironment(
        sources: [first: 1, second: 1],
        caseSensitive: false
    )
    let engine = SafeFileCopyEngine(
        fileSystem: environment,
        committer: environment,
        recoveryStore: CaseSensitivityPendingStore()
    )

    let result = await engine.copy(request)

    #expect(result.succeeded.isEmpty)
    #expect(result.failed?.reason == .collision)
    #expect(await environment.copyCallCount() == 0)
}

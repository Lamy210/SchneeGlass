import FileDomain
import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing
@testable import SchneeGlassFileSystemAdapter

private actor CancellationCopyEnvironment: CopyFileSystemAccessing, StagingCommitting {
    private let sourceSizes: [URL: Int64]
    private var stagedSizes: [URL: Int64] = [:]
    private var stagedIdentifiers: [URL: String] = [:]
    private var committedFilenames: [String] = []

    init(sources: [URL: Int64]) {
        self.sourceSizes = Dictionary(
            uniqueKeysWithValues: sources.map { ($0.key.standardizedFileURL, $0.value) }
        )
    }

    func sourceMetadata(at url: URL) async throws -> CopySourceMetadata {
        guard let size = sourceSizes[url.standardizedFileURL] else {
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
        return false
    }

    func itemExists(at url: URL) async -> Bool {
        _ = url
        return false
    }

    func copyItem(at sourceURL: URL, to stagingURL: URL) async throws {
        guard let size = sourceSizes[sourceURL.standardizedFileURL] else {
            throw CopyFileSystemError.sourceUnavailable
        }
        let staging = stagingURL.standardizedFileURL
        stagedSizes[staging] = size
        stagedIdentifiers[staging] = "cancellation-test:\(staging.lastPathComponent)"
    }

    func regularFileSize(at url: URL) async throws -> Int64 {
        guard let size = stagedSizes[url.standardizedFileURL] else {
            throw CopyFileSystemError.verificationFailed
        }
        return size
    }

    func resourceIdentifier(at url: URL) async -> String? {
        stagedIdentifiers[url.standardizedFileURL]
    }

    func commit(
        stagingURL: URL,
        finalURL: URL,
        authorization: StagingCommitAuthorization
    ) async throws {
        let staging = stagingURL.standardizedFileURL
        guard stagedSizes[staging] == authorization.expectedSize,
              stagedIdentifiers[staging] == authorization.expectedResourceIdentifier
        else {
            throw StagingCommitError.resourceIdentityMismatch
        }
        stagedSizes.removeValue(forKey: staging)
        stagedIdentifiers.removeValue(forKey: staging)
        committedFilenames.append(finalURL.lastPathComponent)
    }

    func committedFiles() -> [String] {
        committedFilenames
    }
}

private actor CancellationPendingCopyStore: PendingCopyRecording {
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

private actor SecondItemProgressGate {
    private var secondItemObserved = false
    private var observerContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func blockWhenSecondItemStarts(_ progress: CopyProgress) async {
        guard progress.currentIndex == 2 else {
            return
        }

        secondItemObserved = true
        observerContinuation?.resume()
        observerContinuation = nil

        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilSecondItemIsObserved() async {
        guard !secondItemObserved else {
            return
        }
        await withCheckedContinuation { continuation in
            observerContinuation = continuation
        }
    }

    func releaseSecondItem() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private func makeCancellationCopyRequest(
    destination: URL,
    sources: [(URL, String, Int64)]
) throws -> AuthorizedCopyBatchRequest {
    let glassID = GlassID()
    let destinationURL = destination.standardizedFileURL
    let destinationDescriptor = DestinationDescriptor(
        glassID: glassID,
        folderIdentity: FolderIdentity(
            resourceIdentifier: nil,
            standardizedURL: destinationURL
        ),
        url: destinationURL,
        capabilities: StorageCapabilities(
            locationKind: .localFixed,
            isWritable: true,
            supportsCaseSensitiveNames: false
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
    return AuthorizedCopyBatchRequest(
        plan: try CopyBatchPlan(destination: destinationDescriptor, items: items),
        destinationAccess: FolderAccessHandle(
            glassID: glassID,
            url: destinationURL
        )
    )
}

@Test
func safeCopyCancellationStopsBeforeTheNextItemMutationBoundary() async throws {
    let destination = URL(fileURLWithPath: "/tmp/schneeglass-cancel", isDirectory: true)
    let first = URL(fileURLWithPath: "/tmp/cancel-first.txt")
    let second = URL(fileURLWithPath: "/tmp/cancel-second.txt")
    let third = URL(fileURLWithPath: "/tmp/cancel-third.txt")
    let environment = CancellationCopyEnvironment(
        sources: [first: 10, second: 20, third: 30]
    )
    let engine = SafeFileCopyEngine(
        fileSystem: environment,
        committer: environment,
        recoveryStore: CancellationPendingCopyStore()
    )
    let request = try makeCancellationCopyRequest(
        destination: destination,
        sources: [
            (first, "first.txt", 10),
            (second, "second.txt", 20),
            (third, "third.txt", 30),
        ]
    )
    let gate = SecondItemProgressGate()

    let copyTask = Task {
        await engine.copy(request) { progress in
            await gate.blockWhenSecondItemStarts(progress)
        }
    }

    await gate.waitUntilSecondItemIsObserved()
    copyTask.cancel()
    await gate.releaseSecondItem()

    let result = await copyTask.value

    #expect(result.succeeded.map(\.operationID) == [request.plan.items[0].operationID])
    #expect(
        result.failed == CopyItemFailure(
            operationID: request.plan.items[1].operationID,
            reason: .cancelled
        )
    )
    #expect(result.notAttempted == [request.plan.items[2]])
    #expect(await environment.committedFiles() == ["first.txt"])
}

import FileDomain
import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing
@testable import SchneeGlassFileSystemAdapter

private actor PinnedCopyProgressRecorder {
    private var values: [CopyProgress] = []

    func record(_ progress: CopyProgress) {
        values.append(progress)
    }

    func snapshot() -> [CopyProgress] {
        values
    }
}

@Test
func pinnedSourceCopyForwardsItemProgressWithoutChangingCopySafety() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("schneeglass-pinned-progress-\(UUID().uuidString)", isDirectory: true)
    let sourceDirectory = root.appendingPathComponent("source", isDirectory: true)
    let destinationDirectory = root.appendingPathComponent("destination", isDirectory: true)
    let operationsDirectory = root.appendingPathComponent("operations", isDirectory: true)
    try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let first = sourceDirectory.appendingPathComponent("first.txt", isDirectory: false)
    let second = sourceDirectory.appendingPathComponent("second.txt", isDirectory: false)
    let firstPayload = Data("first".utf8)
    let secondPayload = Data("second".utf8)
    try firstPayload.write(to: first)
    try secondPayload.write(to: second)

    let glassID = GlassID()
    let access = FolderAccessHandle(
        glassID: glassID,
        url: destinationDirectory,
        runtimeDirectoryIdentity: try testRuntimeDirectoryIdentity(for: destinationDirectory)
    )
    let leases = SourceFileLeaseRegistry()
    let planner = NativeDropPlanningAdapter(sourceLeases: leases)
    let copier = PinnedSourceFileCopying(
        recoveryStore: JSONPendingCopyStore(baseDirectory: operationsDirectory),
        sourceLeases: leases
    )
    let drop = await planner.plan(
        sourceURLs: [first, second],
        destinationAccess: access
    )
    guard case let .copy(plan) = drop else {
        Issue.record("Expected copy plan, got \(drop)")
        return
    }
    let recorder = PinnedCopyProgressRecorder()

    let result = await copier.copy(
        AuthorizedCopyBatchRequest(plan: plan, destinationAccess: access)
    ) { progress in
        await recorder.record(progress)
    }

    #expect(result.failed == nil)
    #expect(result.succeeded.count == 2)
    #expect(try Data(contentsOf: destinationDirectory.appendingPathComponent("first.txt")) == firstPayload)
    #expect(try Data(contentsOf: destinationDirectory.appendingPathComponent("second.txt")) == secondPayload)
    #expect(try Data(contentsOf: first) == firstPayload)
    #expect(try Data(contentsOf: second) == secondPayload)
    #expect(await leases.activeLeaseCount() == 0)
    #expect(
        await recorder.snapshot() == [
            CopyProgress(currentIndex: 1, totalCount: 2, currentFilename: "first.txt"),
            CopyProgress(currentIndex: 2, totalCount: 2, currentFilename: "second.txt"),
        ]
    )
}

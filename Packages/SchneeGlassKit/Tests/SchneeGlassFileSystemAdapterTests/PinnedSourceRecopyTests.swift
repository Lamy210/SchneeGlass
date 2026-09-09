import FileDomain
import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing
@testable import SchneeGlassFileSystemAdapter

@Test
func pinnedSourceCopyCanCopyPreviouslyCommittedOutputAgain() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("schneeglass-pinned-recopy-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let sourceDirectory = root.appendingPathComponent("source", isDirectory: true)
    let firstDestination = root.appendingPathComponent("first", isDirectory: true)
    let secondDestination = root.appendingPathComponent("second", isDirectory: true)
    let operationsDirectory = root.appendingPathComponent("operations", isDirectory: true)

    try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: firstDestination, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: secondDestination, withIntermediateDirectories: true)

    let leases = SourceFileLeaseRegistry()
    let planner = NativeDropPlanningAdapter(sourceLeases: leases)
    let recoveryStore = JSONPendingCopyStore(baseDirectory: operationsDirectory)
    let copier = PinnedSourceFileCopying(
        recoveryStore: recoveryStore,
        sourceLeases: leases
    )

    let source = sourceDirectory.appendingPathComponent("payload.txt", isDirectory: false)
    let payload = Data("copy-me-twice".utf8)
    try payload.write(to: source)

    let firstAccess = FolderAccessHandle(glassID: GlassID(), url: firstDestination)
    let firstDrop = await planner.plan(
        sourceURLs: [source],
        destinationAccess: firstAccess
    )
    guard case let .copy(firstPlan) = firstDrop else {
        Issue.record("Expected first copy plan, got \(firstDrop)")
        return
    }

    let firstResult = await copier.copy(
        AuthorizedCopyBatchRequest(plan: firstPlan, destinationAccess: firstAccess)
    )
    #expect(firstResult.failed == nil)
    #expect(firstResult.succeeded.count == 1)

    let firstOutput = firstDestination.appendingPathComponent("payload.txt", isDirectory: false)
    #expect(try Data(contentsOf: firstOutput) == payload)

    let secondAccess = FolderAccessHandle(glassID: GlassID(), url: secondDestination)
    let secondDrop = await planner.plan(
        sourceURLs: [firstOutput],
        destinationAccess: secondAccess
    )
    guard case let .copy(secondPlan) = secondDrop else {
        Issue.record("Expected second copy plan, got \(secondDrop)")
        return
    }

    let secondResult = await copier.copy(
        AuthorizedCopyBatchRequest(plan: secondPlan, destinationAccess: secondAccess)
    )

    #expect(secondResult.failed == nil)
    #expect(secondResult.succeeded.count == 1)
    let secondOutput = secondDestination.appendingPathComponent("payload.txt", isDirectory: false)
    #expect(try Data(contentsOf: secondOutput) == payload)
    #expect(await leases.activeLeaseCount() == 0)
}

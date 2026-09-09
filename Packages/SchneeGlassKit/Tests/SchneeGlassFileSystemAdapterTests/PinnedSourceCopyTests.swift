import FileDomain
import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing
@testable import SchneeGlassFileSystemAdapter

private func makePinnedCopyRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("schneeglass-pinned-copy-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func makePinnedCopySystem(
    root: URL
) -> (
    sourceDirectory: URL,
    destinationDirectory: URL,
    operationsDirectory: URL,
    access: FolderAccessHandle,
    leases: SourceFileLeaseRegistry,
    planner: NativeDropPlanningAdapter,
    copier: PinnedSourceFileCopying
) {
    let sourceDirectory = root.appendingPathComponent("source", isDirectory: true)
    let destinationDirectory = root.appendingPathComponent("destination", isDirectory: true)
    let operationsDirectory = root.appendingPathComponent("operations", isDirectory: true)
    let glassID = GlassID()
    let access = FolderAccessHandle(glassID: glassID, url: destinationDirectory)
    let leases = SourceFileLeaseRegistry()
    let planner = NativeDropPlanningAdapter(sourceLeases: leases)
    let recoveryStore = JSONPendingCopyStore(baseDirectory: operationsDirectory)
    let copier = PinnedSourceFileCopying(
        recoveryStore: recoveryStore,
        sourceLeases: leases
    )
    return (
        sourceDirectory,
        destinationDirectory,
        operationsDirectory,
        access,
        leases,
        planner,
        copier
    )
}

private func preparePinnedCopyDirectories(
    sourceDirectory: URL,
    destinationDirectory: URL
) throws {
    try FileManager.default.createDirectory(
        at: sourceDirectory,
        withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
        at: destinationDirectory,
        withIntermediateDirectories: true
    )
}

@Test
func pinnedSourceCopyCopiesUnchangedSourceAndReleasesLease() async throws {
    let root = try makePinnedCopyRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let system = makePinnedCopySystem(root: root)
    try preparePinnedCopyDirectories(
        sourceDirectory: system.sourceDirectory,
        destinationDirectory: system.destinationDirectory
    )

    let source = system.sourceDirectory.appendingPathComponent("payload.txt", isDirectory: false)
    let payload = Data("unchanged-payload".utf8)
    try payload.write(to: source)

    let drop = await system.planner.plan(
        sourceURLs: [source],
        destinationAccess: system.access
    )
    guard case let .copy(plan) = drop else {
        Issue.record("Expected copy plan, got \(drop)")
        return
    }
    #expect(await system.leases.activeLeaseCount() == 1)

    let result = await system.copier.copy(
        AuthorizedCopyBatchRequest(plan: plan, destinationAccess: system.access)
    )

    #expect(result.failed == nil)
    #expect(result.succeeded.count == 1)
    let final = system.destinationDirectory.appendingPathComponent("payload.txt", isDirectory: false)
    #expect(try Data(contentsOf: final) == payload)
    #expect(try Data(contentsOf: source) == payload)
    #expect(await system.leases.activeLeaseCount() == 0)
}

@Test
func pinnedSourceCopyRejectsSamePathSameSizeReplacement() async throws {
    let root = try makePinnedCopyRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let system = makePinnedCopySystem(root: root)
    try preparePinnedCopyDirectories(
        sourceDirectory: system.sourceDirectory,
        destinationDirectory: system.destinationDirectory
    )

    let source = system.sourceDirectory.appendingPathComponent("payload.txt", isDirectory: false)
    let original = Data("ORIGINAL".utf8)
    let replacement = Data("REPLACED".utf8)
    #expect(original.count == replacement.count)
    try original.write(to: source)

    let drop = await system.planner.plan(
        sourceURLs: [source],
        destinationAccess: system.access
    )
    guard case let .copy(plan) = drop else {
        Issue.record("Expected copy plan, got \(drop)")
        return
    }
    #expect(await system.leases.activeLeaseCount() == 1)

    try FileManager.default.removeItem(at: source)
    try replacement.write(to: source)

    let result = await system.copier.copy(
        AuthorizedCopyBatchRequest(plan: plan, destinationAccess: system.access)
    )

    #expect(result.succeeded.isEmpty)
    #expect(result.failed?.reason == .verificationFailed)
    let final = system.destinationDirectory.appendingPathComponent("payload.txt", isDirectory: false)
    #expect(!FileManager.default.fileExists(atPath: final.path))
    #expect(try Data(contentsOf: source) == replacement)
    #expect(await system.leases.activeLeaseCount() == 0)
}

@Test
func pinnedSourceCopyRejectsInPlaceEditAfterPlanning() async throws {
    let root = try makePinnedCopyRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let system = makePinnedCopySystem(root: root)
    try preparePinnedCopyDirectories(
        sourceDirectory: system.sourceDirectory,
        destinationDirectory: system.destinationDirectory
    )

    let source = system.sourceDirectory.appendingPathComponent("payload.txt", isDirectory: false)
    let original = Data("ORIGINAL".utf8)
    let changed = Data("CHANGED!".utf8)
    #expect(original.count == changed.count)
    try original.write(to: source)

    let drop = await system.planner.plan(
        sourceURLs: [source],
        destinationAccess: system.access
    )
    guard case let .copy(plan) = drop else {
        Issue.record("Expected copy plan, got \(drop)")
        return
    }

    try changed.write(to: source, options: [])

    let result = await system.copier.copy(
        AuthorizedCopyBatchRequest(plan: plan, destinationAccess: system.access)
    )

    #expect(result.succeeded.isEmpty)
    #expect(result.failed?.reason == .verificationFailed)
    let final = system.destinationDirectory.appendingPathComponent("payload.txt", isDirectory: false)
    #expect(!FileManager.default.fileExists(atPath: final.path))
    #expect(await system.leases.activeLeaseCount() == 0)
}

@Test
func rejectedDropPlanReleasesPreparedSourceLease() async throws {
    let root = try makePinnedCopyRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let system = makePinnedCopySystem(root: root)
    try preparePinnedCopyDirectories(
        sourceDirectory: system.sourceDirectory,
        destinationDirectory: system.destinationDirectory
    )

    let source = system.sourceDirectory.appendingPathComponent("payload.txt", isDirectory: false)
    try Data("payload".utf8).write(to: source)
    let collision = system.destinationDirectory.appendingPathComponent("payload.txt", isDirectory: false)
    try Data("existing".utf8).write(to: collision)

    let result = await system.planner.plan(
        sourceURLs: [source],
        destinationAccess: system.access
    )

    #expect(result == .reject(.collision))
    #expect(await system.leases.activeLeaseCount() == 0)
}

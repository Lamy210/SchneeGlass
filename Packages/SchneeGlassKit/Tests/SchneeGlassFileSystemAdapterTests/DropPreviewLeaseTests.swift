import FileDomain
import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing
@testable import SchneeGlassFileSystemAdapter

@Test
func nativeDropPreviewDoesNotAcquireSourceLeaseAuthority() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("schneeglass-drop-preview-\(UUID().uuidString)", isDirectory: true)
    let sourceDirectory = root.appendingPathComponent("source", isDirectory: true)
    let destinationDirectory = root.appendingPathComponent("destination", isDirectory: true)
    try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let source = sourceDirectory.appendingPathComponent("payload.txt", isDirectory: false)
    try Data("preview-payload".utf8).write(to: source)

    let leases = SourceFileLeaseRegistry()
    let planner = NativeDropPlanningAdapter(sourceLeases: leases)
    let access = FolderAccessHandle(
        glassID: GlassID(),
        url: destinationDirectory,
        runtimeDirectoryIdentity: try testRuntimeDirectoryIdentity(for: destinationDirectory)
    )

    let preview = await planner.preview(
        sourceURLs: [source],
        destinationAccess: access
    )
    guard case let .copy(previewPlan) = preview else {
        Issue.record("Expected lease-free preview to accept the regular local file")
        return
    }

    #expect(previewPlan.items.count == 1)
    #expect(previewPlan.items[0].destinationFilename == "payload.txt")
    #expect(await leases.activeLeaseCount() == 0)

    let authoritative = await planner.plan(
        sourceURLs: [source],
        destinationAccess: access
    )
    guard case let .copy(authoritativePlan) = authoritative else {
        Issue.record("Expected authoritative planning to accept the same source")
        return
    }

    #expect(authoritativePlan.items.count == 1)
    #expect(authoritativePlan.items[0].destinationFilename == previewPlan.items[0].destinationFilename)
    #expect(await leases.activeLeaseCount() == 1)

    await leases.releaseBound(operationIDs: authoritativePlan.items.map(\.operationID))
    #expect(await leases.activeLeaseCount() == 0)
}

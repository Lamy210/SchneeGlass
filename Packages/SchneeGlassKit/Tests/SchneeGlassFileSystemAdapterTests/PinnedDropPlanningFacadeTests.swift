import FileDomain
import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing
@testable import SchneeGlassFileSystemAdapter

private struct FixedPreviewDropPlanning: DropPlanning {
    let result: DropPlan

    func preview(
        sourceURLs: [URL],
        destinationAccess: FolderAccessHandle
    ) async -> DropPlan {
        _ = sourceURLs
        _ = destinationAccess
        return result
    }

    func plan(
        sourceURLs: [URL],
        destinationAccess: FolderAccessHandle
    ) async -> DropPlan {
        _ = sourceURLs
        _ = destinationAccess
        return result
    }
}

@Test
func pinnedDropPreviewReflectsSharedCapacityWithoutAcquiringAnotherLease() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("schneeglass-preview-capacity-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let maximum = 2
    let leases = SourceFileLeaseRegistry(maximumActiveLeases: maximum)
    let firstHeldSource = root.appendingPathComponent("held-first.txt", isDirectory: false)
    try Data("held-first".utf8).write(to: firstHeldSource)
    let firstPrepared = try await leases.prepareSource(at: firstHeldSource)

    let previewSource = root.appendingPathComponent("preview.txt", isDirectory: false)
    try Data("preview".utf8).write(to: previewSource)
    let destinationURL = root.appendingPathComponent("destination", isDirectory: true)
    try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
    let glassID = GlassID()
    let destination = DestinationDescriptor(
        glassID: glassID,
        folderIdentity: FolderIdentity(resourceIdentifier: "preview-destination", standardizedURL: destinationURL),
        url: destinationURL,
        capabilities: StorageCapabilities(
            locationKind: .localFixed,
            isWritable: true,
            supportsCaseSensitiveNames: true,
            supportsSafeDestinationCommit: true
        )
    )
    let item = CopyItemPlan(
        sourceURL: previewSource,
        originalFilename: previewSource.lastPathComponent,
        destinationFilename: previewSource.lastPathComponent,
        expectedSize: 7
    )
    let copyPlan = try CopyBatchPlan(destination: destination, items: [item])
    let facade = PinnedDropPlanningFacade(
        delegate: FixedPreviewDropPlanning(result: .copy(copyPlan)),
        sourceLeases: leases,
        maximumActiveLeases: maximum
    )
    let access = FolderAccessHandle(glassID: glassID, url: destinationURL)

    let availableResult = await facade.preview(
        sourceURLs: [previewSource],
        destinationAccess: access
    )
    #expect(availableResult == .copy(copyPlan))
    #expect(await leases.activeLeaseCount() == 1)

    let secondHeldSource = root.appendingPathComponent("held-second.txt", isDirectory: false)
    try Data("held-second".utf8).write(to: secondHeldSource)
    let secondPrepared = try await leases.prepareSource(at: secondHeldSource)
    #expect(await leases.activeLeaseCount() == maximum)

    let saturatedResult = await facade.preview(
        sourceURLs: [previewSource],
        destinationAccess: access
    )
    #expect(saturatedResult == .reject(.sourceCapacityReached(maximum: maximum)))
    #expect(await leases.activeLeaseCount() == maximum)

    await leases.releasePrepared(tokens: [firstPrepared.token, secondPrepared.token])
    #expect(await leases.activeLeaseCount() == 0)

    let recoveredResult = await facade.preview(
        sourceURLs: [previewSource],
        destinationAccess: access
    )
    #expect(recoveredResult == .copy(copyPlan))
    #expect(await leases.activeLeaseCount() == 0)
}

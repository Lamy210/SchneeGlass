import FileDomain
import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing
@testable import SchneeGlassFileSystemAdapter

@Test
func nativeDropPlannerAbandonReleasesBoundSourceAuthority() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("schneeglass-native-plan-abandon-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let source = root.appendingPathComponent("source.txt", isDirectory: false)
    try Data("source".utf8).write(to: source)

    let destinationURL = root.appendingPathComponent("destination", isDirectory: true)
    try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)

    let sourceLeases = SourceFileLeaseRegistry()
    let prepared = try await sourceLeases.prepareSource(at: source)
    let operationID = UUID()
    try await sourceLeases.bind(token: prepared.token, operationID: operationID)
    #expect(await sourceLeases.activeLeaseCount() == 1)

    let glassID = GlassID()
    let destination = DestinationDescriptor(
        glassID: glassID,
        folderIdentity: FolderIdentity(
            resourceIdentifier: "destination-resource",
            standardizedURL: destinationURL
        ),
        url: destinationURL,
        capabilities: StorageCapabilities(
            locationKind: .localFixed,
            isWritable: true,
            supportsCaseSensitiveNames: true,
            supportsSafeDestinationCommit: true
        )
    )
    let plan = try CopyBatchPlan(
        destination: destination,
        items: [
            CopyItemPlan(
                operationID: operationID,
                sourceURL: source,
                originalFilename: source.lastPathComponent,
                destinationFilename: source.lastPathComponent,
                expectedSize: prepared.size
            )
        ]
    )
    let request = AuthorizedCopyBatchRequest(
        plan: plan,
        destinationAccess: FolderAccessHandle(
            glassID: glassID,
            url: destinationURL
        )
    )
    let planner = NativeDropPlanningAdapter(sourceLeases: sourceLeases)

    await planner.abandon(request)
    #expect(await sourceLeases.activeLeaseCount() == 0)

    // Abandonment must remain safe if an outer lifecycle path observes the same stale plan twice.
    await planner.abandon(request)
    #expect(await sourceLeases.activeLeaseCount() == 0)
}

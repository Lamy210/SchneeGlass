import FileDomain
import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing
@testable import SchneeGlassFileSystemAdapter

@Test
func pinnedDropCopyPipelineSharesPlanningAndExecutionLeaseAuthority() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("schneeglass-pipeline-\(UUID().uuidString)", isDirectory: true)
    let sourceDirectory = root.appendingPathComponent("source", isDirectory: true)
    let destinationDirectory = root.appendingPathComponent("destination", isDirectory: true)
    let operationsDirectory = root.appendingPathComponent("operations", isDirectory: true)

    try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let source = sourceDirectory.appendingPathComponent("payload.txt", isDirectory: false)
    let payload = Data("pipeline-payload".utf8)
    try payload.write(to: source)

    let recoveryStore = JSONPendingCopyStore(baseDirectory: operationsDirectory)
    let pipeline = PinnedDropCopyPipeline(recoveryStore: recoveryStore)
    let glassID = GlassID()
    let destinationAccess = FolderAccessHandle(
        glassID: glassID,
        url: destinationDirectory
    )

    let drop = await pipeline.dropPlanning.plan(
        sourceURLs: [source],
        destinationAccess: destinationAccess
    )
    let plan: CopyBatchPlan
    switch drop {
    case let .copy(copyPlan):
        plan = copyPlan
    default:
        Issue.record("Expected the canonical pipeline to produce an executable copy plan")
        return
    }

    let result = await pipeline.fileCopying.copy(
        AuthorizedCopyBatchRequest(
            plan: plan,
            destinationAccess: destinationAccess
        )
    )

    let finalURL = destinationDirectory.appendingPathComponent("payload.txt", isDirectory: false)
    #expect(result.failed == nil)
    #expect(result.succeeded.map(\.operationID) == plan.items.map(\.operationID))
    #expect(try Data(contentsOf: finalURL) == payload)
    #expect(try await recoveryStore.records().isEmpty)
}

import FileDomain
import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing
@testable import SchneeGlassFileSystemAdapter

private func makeGlobalSourceBudgetRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("schneeglass-global-source-budget-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func writeGlobalSourceBudgetFile(_ name: String, in root: URL) throws -> URL {
    let url = root.appendingPathComponent(name, isDirectory: false)
    try Data(name.utf8).write(to: url)
    return url
}

@Test
func sourceLeaseRegistryRejectsBeforeExceedingGlobalCapacityAndRecoversAfterRelease() async throws {
    let root = try makeGlobalSourceBudgetRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let firstURL = try writeGlobalSourceBudgetFile("first.txt", in: root)
    let secondURL = try writeGlobalSourceBudgetFile("second.txt", in: root)
    let thirdURL = try writeGlobalSourceBudgetFile("third.txt", in: root)
    let leases = SourceFileLeaseRegistry(maximumActiveLeases: 2)

    let first = try await leases.prepareSource(at: firstURL)
    let second = try await leases.prepareSource(at: secondURL)
    #expect(await leases.activeLeaseCount() == 2)

    do {
        _ = try await leases.prepareSource(at: thirdURL)
        Issue.record("Expected the shared source lease budget to reject a third descriptor")
    } catch let error as SourceFileLeaseError {
        #expect(error == .capacityExceeded(maximum: 2))
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(await leases.activeLeaseCount() == 2)

    await leases.releasePrepared(tokens: [first.token])
    let third = try await leases.prepareSource(at: thirdURL)
    #expect(await leases.activeLeaseCount() == 2)

    await leases.releasePrepared(tokens: [second.token, third.token])
    #expect(await leases.activeLeaseCount() == 0)
}

@Test
func authoritativePlanningRollsBackOnlyItsPreparedSourcesWhenGlobalBudgetFills() async throws {
    let root = try makeGlobalSourceBudgetRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let destinationURL = root.appendingPathComponent("destination", isDirectory: true)
    try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)

    let existingURL = try writeGlobalSourceBudgetFile("existing.txt", in: root)
    let firstDropURL = try writeGlobalSourceBudgetFile("drop-a.txt", in: root)
    let secondDropURL = try writeGlobalSourceBudgetFile("drop-b.txt", in: root)

    let leases = SourceFileLeaseRegistry(maximumActiveLeases: 2)
    let existing = try await leases.prepareSource(at: existingURL)
    let existingOperationID = UUID()
    try await leases.bind(token: existing.token, operationID: existingOperationID)

    let planner = NativeDropPlanningAdapter(sourceLeases: leases)
    let destination = FolderAccessHandle(
        glassID: GlassID(),
        url: destinationURL
    )

    let result = await planner.plan(
        sourceURLs: [firstDropURL, secondDropURL],
        destinationAccess: destination
    )

    #expect(result == .reject(.sourceCapacityReached(maximum: 2)))
    #expect(await leases.activeLeaseCount() == 1)
    #expect(await leases.boundSourceSize(at: existingURL) == Int64("existing.txt".utf8.count))

    await leases.releaseBound(operationIDs: [existingOperationID])
    #expect(await leases.activeLeaseCount() == 0)
}

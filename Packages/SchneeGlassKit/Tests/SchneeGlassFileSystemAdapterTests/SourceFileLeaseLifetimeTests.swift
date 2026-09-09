import Foundation
import Testing
@testable import SchneeGlassFileSystemAdapter

private func makeLeaseLifetimeRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("schneeglass-lease-lifetime-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

@Test
func unconsumedBoundSourceLeaseStillExpires() async throws {
    let root = try makeLeaseLifetimeRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let source = root.appendingPathComponent("payload.txt", isDirectory: false)
    try Data("payload".utf8).write(to: source)

    let leases = SourceFileLeaseRegistry(expirationNanoseconds: 10_000_000)
    let prepared = try await leases.prepareSource(at: source)
    let operationID = UUID()
    try await leases.bind(token: prepared.token, operationID: operationID)

    try await Task.sleep(nanoseconds: 100_000_000)

    #expect(await leases.activeLeaseCount() == 0)
}

@Test
func executionActiveSourceLeaseDoesNotExpire() async throws {
    let root = try makeLeaseLifetimeRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let source = root.appendingPathComponent("payload.txt", isDirectory: false)
    try Data("payload".utf8).write(to: source)

    let leases = SourceFileLeaseRegistry(expirationNanoseconds: 10_000_000)
    let prepared = try await leases.prepareSource(at: source)
    let operationID = UUID()
    try await leases.bind(token: prepared.token, operationID: operationID)
    await leases.beginExecution(operationIDs: [operationID])

    try await Task.sleep(nanoseconds: 100_000_000)

    #expect(await leases.activeLeaseCount() == 1)
    await leases.releaseBound(operationIDs: [operationID])
    #expect(await leases.activeLeaseCount() == 0)
}

@Test
func newerPlanCannotSupersedeExecutionActiveSourceLease() async throws {
    let root = try makeLeaseLifetimeRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let source = root.appendingPathComponent("payload.txt", isDirectory: false)
    try Data("payload".utf8).write(to: source)

    let leases = SourceFileLeaseRegistry()
    let first = try await leases.prepareSource(at: source)
    let firstOperationID = UUID()
    try await leases.bind(token: first.token, operationID: firstOperationID)
    await leases.beginExecution(operationIDs: [firstOperationID])

    let second = try await leases.prepareSource(at: source)
    let secondOperationID = UUID()
    do {
        try await leases.bind(token: second.token, operationID: secondOperationID)
        Issue.record("Expected an active source lease to reject a newer plan")
    } catch let error as SourceFileLeaseError {
        #expect(error == .sourceUnavailable)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    await leases.releasePrepared(tokens: [second.token])
    #expect(await leases.activeLeaseCount() == 1)
    #expect(await leases.boundSourceSize(at: source) == first.size)

    await leases.releaseBound(operationIDs: [firstOperationID])
    #expect(await leases.activeLeaseCount() == 0)
}

@Test
func newerPlanStillSupersedesUnconsumedSourceLease() async throws {
    let root = try makeLeaseLifetimeRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let source = root.appendingPathComponent("payload.txt", isDirectory: false)
    try Data("payload".utf8).write(to: source)

    let leases = SourceFileLeaseRegistry()
    let first = try await leases.prepareSource(at: source)
    let firstOperationID = UUID()
    try await leases.bind(token: first.token, operationID: firstOperationID)

    let second = try await leases.prepareSource(at: source)
    let secondOperationID = UUID()
    try await leases.bind(token: second.token, operationID: secondOperationID)

    #expect(await leases.activeLeaseCount() == 1)
    #expect(await leases.boundSourceSize(at: source) == second.size)

    await leases.releaseBound(operationIDs: [secondOperationID])
    #expect(await leases.activeLeaseCount() == 0)
}

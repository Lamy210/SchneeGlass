import Foundation
import SchneeGlassApplication
@testable import SchneeGlassFileSystemAdapter
import SchneeGlassDomain
import Testing

@Test("pending copy records persist across store instances")
func pendingCopyRecordsPersist() async throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appendingPathComponent("SchneeGlass-Recovery-\(UUID().uuidString)", isDirectory: true)
    defer { try? fileManager.removeItem(at: root) }

    let operationID = UUID()
    let record = PendingCopyRecord(
        operationID: operationID,
        batchID: UUID(),
        destinationGlassID: GlassID(),
        stagingFilename: ".schneeglass-copy-\(operationID.uuidString).partial",
        finalFilename: "sample.txt",
        expectedSize: 4,
        state: .recorded
    )

    let writer = JSONPendingCopyStore(baseDirectory: root)
    try await writer.upsert(record)

    let reader = JSONPendingCopyStore(baseDirectory: root)
    let loaded = try await reader.records()

    #expect(loaded == [record])
}

@Test("upsert replaces state for the same operation")
func pendingCopyUpsertReplacesState() async throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appendingPathComponent("SchneeGlass-Recovery-\(UUID().uuidString)", isDirectory: true)
    defer { try? fileManager.removeItem(at: root) }

    let operationID = UUID()
    let original = PendingCopyRecord(
        operationID: operationID,
        batchID: UUID(),
        destinationGlassID: GlassID(),
        stagingFilename: ".schneeglass-copy-\(operationID.uuidString).partial",
        finalFilename: "sample.txt",
        expectedSize: nil,
        state: .recorded
    )

    let store = JSONPendingCopyStore(baseDirectory: root)
    try await store.upsert(original)
    try await store.upsert(original.updating(state: .verifying))

    let loaded = try await store.records()
    #expect(loaded.count == 1)
    #expect(loaded.first?.state == .verifying)
}

@Test("remove deletes only metadata for the specified operation")
func pendingCopyRemoveIsScoped() async throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appendingPathComponent("SchneeGlass-Recovery-\(UUID().uuidString)", isDirectory: true)
    defer { try? fileManager.removeItem(at: root) }

    let first = PendingCopyRecord(
        operationID: UUID(),
        batchID: UUID(),
        destinationGlassID: GlassID(),
        stagingFilename: ".schneeglass-copy-first.partial",
        finalFilename: "first.txt",
        expectedSize: nil,
        state: .recorded
    )
    let second = PendingCopyRecord(
        operationID: UUID(),
        batchID: UUID(),
        destinationGlassID: GlassID(),
        stagingFilename: ".schneeglass-copy-second.partial",
        finalFilename: "second.txt",
        expectedSize: nil,
        state: .recorded
    )

    let store = JSONPendingCopyStore(baseDirectory: root)
    try await store.upsert(first)
    try await store.upsert(second)
    try await store.remove(operationID: first.operationID)

    #expect(try await store.records() == [second])
}

@Test("metadata operations never delete an unrelated partial-looking file")
func unknownPartialIsUntouched() async throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appendingPathComponent("SchneeGlass-Recovery-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: root) }

    let unknown = root.appendingPathComponent(".schneeglass-copy-unknown.partial")
    try Data("user-data".utf8).write(to: unknown)

    let store = JSONPendingCopyStore(baseDirectory: root)
    _ = try await store.records()
    try await store.remove(operationID: UUID())

    #expect(fileManager.fileExists(atPath: unknown.path))
    #expect(try Data(contentsOf: unknown) == Data("user-data".utf8))
}

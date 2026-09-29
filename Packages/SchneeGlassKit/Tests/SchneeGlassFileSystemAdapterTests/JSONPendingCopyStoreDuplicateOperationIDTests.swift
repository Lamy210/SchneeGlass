import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing

@testable import SchneeGlassFileSystemAdapter

private func makeDuplicatePendingCopyRoot() throws -> URL {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "schneeglass-duplicate-pending-copy-\(UUID().uuidString)",
    isDirectory: true
  )
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  return root
}

private func duplicatePendingCopyRecords() -> [PendingCopyRecord] {
  let operationID = UUID()
  return [
    PendingCopyRecord(
      operationID: operationID,
      batchID: UUID(),
      destinationGlassID: GlassID(),
      stagingFilename: ".schneeglass-copy-\(operationID.uuidString.lowercased()).partial",
      finalFilename: "first.txt",
      expectedSize: 5,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      state: .staging
    ),
    PendingCopyRecord(
      operationID: operationID,
      batchID: UUID(),
      destinationGlassID: GlassID(),
      stagingFilename: ".schneeglass-copy-\(operationID.uuidString.lowercased()).partial",
      finalFilename: "second.txt",
      expectedSize: 6,
      createdAt: Date(timeIntervalSince1970: 1_700_000_001),
      state: .verifying
    ),
  ]
}

private func writeDuplicatePendingCopyRecords(
  _ records: [PendingCopyRecord],
  root: URL
) throws -> URL {
  let data = try JSONEncoder().encode(records)
  let url = root.appendingPathComponent(JSONPendingCopyStore.filename)
  try data.write(to: url)
  return url
}

@Test
func duplicatePendingCopyOperationIDsAreRejectedOnRead() async throws {
  let root = try makeDuplicatePendingCopyRoot()
  defer { try? FileManager.default.removeItem(at: root) }

  let records = duplicatePendingCopyRecords()
  _ = try writeDuplicatePendingCopyRecords(records, root: root)
  let store = JSONPendingCopyStore(baseDirectory: root)

  do {
    _ = try await store.records()
    Issue.record("Expected duplicate Pending Copy operation IDs to be rejected")
  } catch {
    // Any persisted-state validation failure is fail-closed at this adapter boundary.
  }
}

@Test
func duplicatePendingCopyOperationIDsCannotBeMutatedThroughUpsert() async throws {
  let root = try makeDuplicatePendingCopyRoot()
  defer { try? FileManager.default.removeItem(at: root) }

  let records = duplicatePendingCopyRecords()
  let metadataURL = try writeDuplicatePendingCopyRecords(records, root: root)
  let originalData = try Data(contentsOf: metadataURL)
  let store = JSONPendingCopyStore(baseDirectory: root)

  let replacement = PendingCopyRecord(
    operationID: records[0].operationID,
    batchID: UUID(),
    destinationGlassID: GlassID(),
    stagingFilename: records[0].stagingFilename,
    finalFilename: "replacement.txt",
    expectedSize: 11,
    state: .committing
  )

  do {
    try await store.upsert(replacement)
    Issue.record("Expected ambiguous Pending Copy metadata to block upsert")
  } catch {
  }

  #expect(try Data(contentsOf: metadataURL) == originalData)
}

@Test
func duplicatePendingCopyOperationIDsCannotBeMutatedThroughRemove() async throws {
  let root = try makeDuplicatePendingCopyRoot()
  defer { try? FileManager.default.removeItem(at: root) }

  let records = duplicatePendingCopyRecords()
  let metadataURL = try writeDuplicatePendingCopyRecords(records, root: root)
  let originalData = try Data(contentsOf: metadataURL)
  let store = JSONPendingCopyStore(baseDirectory: root)

  do {
    try await store.remove(operationID: records[0].operationID)
    Issue.record("Expected ambiguous Pending Copy metadata to block removal")
  } catch {
  }

  #expect(try Data(contentsOf: metadataURL) == originalData)
}

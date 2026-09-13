import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing
@testable import SchneeGlassFileSystemAdapter

private struct FixedStagingSemanticMetadataReader: SourceSemanticMetadataReading {
    let value: SourceSemanticMetadata

    func metadata(at url: URL) throws -> SourceSemanticMetadata {
        _ = url
        return value
    }
}

private func unknownStagingSemanticMetadataReader() -> FixedStagingSemanticMetadataReader {
    FixedStagingSemanticMetadataReader(
        value: SourceSemanticMetadata(isAlias: nil, isPackage: false)
    )
}

private func makeStagingSemanticRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("schneeglass-staging-semantics-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func createStagingOwnershipToken(at url: URL) throws -> String {
    let identity = try PendingCopyFileIdentity.createToken(
        at: url,
        fileManager: .default
    )
    return try #require(identity)
}

private func makeStagingSemanticRecord(
    glassID: GlassID,
    operationID: UUID,
    expectedSize: Int64,
    stagingResourceIdentifier: String
) -> PendingCopyRecord {
    PendingCopyRecord(
        operationID: operationID,
        batchID: UUID(),
        destinationGlassID: glassID,
        stagingFilename: ".schneeglass-copy-\(operationID.uuidString.lowercased()).partial",
        finalFilename: "payload.txt",
        expectedSize: expectedSize,
        stagingResourceIdentifier: stagingResourceIdentifier,
        state: .staging
    )
}

@Test
func internalCommitterRejectsUnknownStagingSemanticMetadataBeforeRename() async throws {
    let root = try makeStagingSemanticRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let operationID = UUID()
    let staging = root.appendingPathComponent(
        ".schneeglass-copy-\(operationID.uuidString.lowercased()).partial"
    )
    let final = root.appendingPathComponent("payload.txt")
    let payload = Data("payload".utf8)
    try payload.write(to: staging)
    let identity = try createStagingOwnershipToken(at: staging)

    let committer = InternalStagingCommitter(
        fileManager: .default,
        semanticMetadataReader: unknownStagingSemanticMetadataReader()
    )

    do {
        try await committer.commit(
            stagingURL: staging,
            finalURL: final,
            authorization: StagingCommitAuthorization(
                expectedSize: Int64(payload.count),
                expectedResourceIdentifier: identity
            )
        )
        Issue.record("Expected unknown staging semantic metadata to fail closed")
    } catch let error as StagingCommitError {
        #expect(error == .unexpectedFileType)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(FileManager.default.fileExists(atPath: staging.path))
    #expect(!FileManager.default.fileExists(atPath: final.path))
}

@Test
func recoveryInspectorClassifiesUnknownStagingSemanticMetadataAsUnexpectedType() async throws {
    let root = try makeStagingSemanticRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let glassID = GlassID()
    let operationID = UUID()
    let staging = root.appendingPathComponent(
        ".schneeglass-copy-\(operationID.uuidString.lowercased()).partial"
    )
    let payload = Data("payload".utf8)
    try payload.write(to: staging)
    let identity = try createStagingOwnershipToken(at: staging)
    let record = makeStagingSemanticRecord(
        glassID: glassID,
        operationID: operationID,
        expectedSize: Int64(payload.count),
        stagingResourceIdentifier: identity
    )

    let inspector = PendingCopyRecoveryInspector(
        fileManager: .default,
        semanticMetadataReader: unknownStagingSemanticMetadataReader()
    )
    let assessment = await inspector.assess(
        record,
        destinationAccess: FolderAccessHandle(glassID: glassID, url: root)
    )

    #expect(
        assessment.disposition == PendingCopyRecoveryDisposition.unexpectedFileType
    )
}

@Test
func ownedStagingCleanerRejectsUnknownSemanticMetadataWithoutDeletion() async throws {
    let root = try makeStagingSemanticRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let glassID = GlassID()
    let operationID = UUID()
    let staging = root.appendingPathComponent(
        ".schneeglass-copy-\(operationID.uuidString.lowercased()).partial"
    )
    let payload = Data("payload".utf8)
    try payload.write(to: staging)
    let identity = try createStagingOwnershipToken(at: staging)
    let record = makeStagingSemanticRecord(
        glassID: glassID,
        operationID: operationID,
        expectedSize: Int64(payload.count),
        stagingResourceIdentifier: identity
    )

    let cleaner = OwnedStagingRecoveryCleaner(
        fileManager: .default,
        semanticMetadataReader: unknownStagingSemanticMetadataReader()
    )

    do {
        try await cleaner.removeOwnedStaging(
            record: record,
            destinationAccess: FolderAccessHandle(glassID: glassID, url: root)
        )
        Issue.record("Expected unknown staging semantic metadata to fail closed")
    } catch let error as OwnedStagingRecoveryCleanupError {
        #expect(error == .unexpectedFileType)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(FileManager.default.fileExists(atPath: staging.path))
}

import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing
@testable import SchneeGlassFileSystemAdapter

private enum OwnedStagingCleanerTestError: Error {
    case missingResourceIdentifier
}

private func makeRecoveryCleanupRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("schneeglass-owned-staging-cleaner-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func makeOwnedStagingRecord(
    glassID: GlassID,
    operationID: UUID = UUID(),
    finalFilename: String = "report.txt",
    stagingResourceIdentifier: String?
) -> PendingCopyRecord {
    PendingCopyRecord(
        operationID: operationID,
        batchID: UUID(),
        destinationGlassID: glassID,
        stagingFilename: ".schneeglass-copy-\(operationID.uuidString.lowercased()).partial",
        finalFilename: finalFilename,
        expectedSize: 7,
        stagingResourceIdentifier: stagingResourceIdentifier,
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        state: .staging
    )
}

private func resourceIdentifier(of url: URL) throws -> String {
    guard let identifier = try PendingCopyFileIdentity.token(
        at: url,
        fileManager: .default
    ) else {
        throw OwnedStagingCleanerTestError.missingResourceIdentifier
    }
    return identifier
}

@Test
func ownedStagingCleanerDeletesOnlyIdentityMatchedStaging() async throws {
    let root = try makeRecoveryCleanupRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let glassID = GlassID()
    let operationID = UUID()
    let stagingURL = root.appendingPathComponent(
        ".schneeglass-copy-\(operationID.uuidString.lowercased()).partial"
    )
    let finalURL = root.appendingPathComponent("report.txt")
    try Data("staging".utf8).write(to: stagingURL)
    try Data("final".utf8).write(to: finalURL)

    let record = makeOwnedStagingRecord(
        glassID: glassID,
        operationID: operationID,
        stagingResourceIdentifier: try resourceIdentifier(of: stagingURL)
    )
    let access = FolderAccessHandle(glassID: glassID, url: root)
    let cleaner = OwnedStagingRecoveryCleaner()

    try await cleaner.removeOwnedStaging(record: record, destinationAccess: access)

    #expect(!FileManager.default.fileExists(atPath: stagingURL.path))
    #expect(FileManager.default.fileExists(atPath: finalURL.path))
    #expect(try Data(contentsOf: finalURL) == Data("final".utf8))
}

@Test
func ownedStagingCleanerRejectsResourceIdentityMismatchWithoutMutation() async throws {
    let root = try makeRecoveryCleanupRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let glassID = GlassID()
    let operationID = UUID()
    let stagingURL = root.appendingPathComponent(
        ".schneeglass-copy-\(operationID.uuidString.lowercased()).partial"
    )
    try Data("staging".utf8).write(to: stagingURL)

    let record = makeOwnedStagingRecord(
        glassID: glassID,
        operationID: operationID,
        stagingResourceIdentifier: "different-resource"
    )
    let cleaner = OwnedStagingRecoveryCleaner()

    do {
        try await cleaner.removeOwnedStaging(
            record: record,
            destinationAccess: FolderAccessHandle(glassID: glassID, url: root)
        )
        Issue.record("Expected resourceIdentityMismatch")
    } catch let error as OwnedStagingRecoveryCleanupError {
        #expect(error == .resourceIdentityMismatch)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(FileManager.default.fileExists(atPath: stagingURL.path))
}

@Test
func ownedStagingCleanerRejectsMissingRecordedIdentityWithoutMutation() async throws {
    let root = try makeRecoveryCleanupRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let glassID = GlassID()
    let operationID = UUID()
    let stagingURL = root.appendingPathComponent(
        ".schneeglass-copy-\(operationID.uuidString.lowercased()).partial"
    )
    try Data("staging".utf8).write(to: stagingURL)

    let record = makeOwnedStagingRecord(
        glassID: glassID,
        operationID: operationID,
        stagingResourceIdentifier: nil
    )
    let cleaner = OwnedStagingRecoveryCleaner()

    do {
        try await cleaner.removeOwnedStaging(
            record: record,
            destinationAccess: FolderAccessHandle(glassID: glassID, url: root)
        )
        Issue.record("Expected resourceIdentityUnavailable")
    } catch let error as OwnedStagingRecoveryCleanupError {
        #expect(error == .resourceIdentityUnavailable)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(FileManager.default.fileExists(atPath: stagingURL.path))
}

@Test
func ownedStagingCleanerRejectsSymlinkReplacementWithoutMutation() async throws {
    let root = try makeRecoveryCleanupRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let glassID = GlassID()
    let operationID = UUID()
    let targetURL = root.appendingPathComponent("target.txt")
    let stagingURL = root.appendingPathComponent(
        ".schneeglass-copy-\(operationID.uuidString.lowercased()).partial"
    )
    try Data("target".utf8).write(to: targetURL)
    try FileManager.default.createSymbolicLink(at: stagingURL, withDestinationURL: targetURL)

    let record = makeOwnedStagingRecord(
        glassID: glassID,
        operationID: operationID,
        stagingResourceIdentifier: try resourceIdentifier(of: targetURL)
    )
    let cleaner = OwnedStagingRecoveryCleaner()

    do {
        try await cleaner.removeOwnedStaging(
            record: record,
            destinationAccess: FolderAccessHandle(glassID: glassID, url: root)
        )
        Issue.record("Expected unexpectedFileType")
    } catch let error as OwnedStagingRecoveryCleanupError {
        #expect(error == .unexpectedFileType)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(FileManager.default.fileExists(atPath: stagingURL.path))
    #expect(FileManager.default.fileExists(atPath: targetURL.path))
}

@Test
func ownedStagingCleanerRejectsInvalidRecordAndDifferentGlass() async throws {
    let root = try makeRecoveryCleanupRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let glassID = GlassID()
    let operationID = UUID()
    let stagingURL = root.appendingPathComponent(
        ".schneeglass-copy-\(operationID.uuidString.lowercased()).partial"
    )
    try Data("staging".utf8).write(to: stagingURL)
    let identity = try resourceIdentifier(of: stagingURL)
    let cleaner = OwnedStagingRecoveryCleaner()

    let invalidRecord = PendingCopyRecord(
        operationID: operationID,
        batchID: UUID(),
        destinationGlassID: glassID,
        stagingFilename: ".schneeglass-copy-wrong.partial",
        finalFilename: "report.txt",
        expectedSize: 7,
        stagingResourceIdentifier: identity,
        state: .staging
    )

    do {
        try await cleaner.removeOwnedStaging(
            record: invalidRecord,
            destinationAccess: FolderAccessHandle(glassID: glassID, url: root)
        )
        Issue.record("Expected invalidRecord")
    } catch let error as OwnedStagingRecoveryCleanupError {
        #expect(error == .invalidRecord)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    let validRecord = makeOwnedStagingRecord(
        glassID: glassID,
        operationID: operationID,
        stagingResourceIdentifier: identity
    )

    do {
        try await cleaner.removeOwnedStaging(
            record: validRecord,
            destinationAccess: FolderAccessHandle(glassID: GlassID(), url: root)
        )
        Issue.record("Expected destinationMismatch")
    } catch let error as OwnedStagingRecoveryCleanupError {
        #expect(error == .destinationMismatch)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(FileManager.default.fileExists(atPath: stagingURL.path))
}

import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import SchneeGlassPOSIXSupport
import Testing
@testable import SchneeGlassFileSystemAdapter

private func makeRecoveryDestinationIdentityRoot() throws -> (workspace: URL, destination: URL) {
    let workspace = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "schneeglass-recovery-destination-identity-\(UUID().uuidString)",
            isDirectory: true
        )
    let destination = workspace.appendingPathComponent("destination", isDirectory: true)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    return (workspace, destination)
}

private func acquiredRecoveryRuntimeIdentity(for url: URL) throws -> RuntimeDirectoryIdentity {
    let identity = try #require(POSIXDirectoryIdentityReader.identity(at: url))
    return RuntimeDirectoryIdentity(
        deviceIdentifier: identity.device,
        objectIdentifier: identity.inode
    )
}

private func recoveryDestinationIdentityRecord(
    glassID: GlassID,
    operationID: UUID = UUID(),
    stagingResourceIdentifier: String? = nil
) -> PendingCopyRecord {
    PendingCopyRecord(
        operationID: operationID,
        batchID: UUID(),
        destinationGlassID: glassID,
        stagingFilename: ".schneeglass-copy-\(operationID.uuidString.lowercased()).partial",
        finalFilename: "report.txt",
        expectedSize: 7,
        stagingResourceIdentifier: stagingResourceIdentifier,
        state: .staging
    )
}

@Test
func recoveryInspectorRejectsDestinationPathReplacementAfterAccessAcquisition() async throws {
    let roots = try makeRecoveryDestinationIdentityRoot()
    defer { try? FileManager.default.removeItem(at: roots.workspace) }

    let glassID = GlassID()
    let handle = FolderAccessHandle(
        glassID: glassID,
        url: roots.destination,
        runtimeDirectoryIdentity: try acquiredRecoveryRuntimeIdentity(for: roots.destination)
    )
    let movedDestination = roots.workspace.appendingPathComponent("original-destination", isDirectory: true)
    try FileManager.default.moveItem(at: roots.destination, to: movedDestination)
    try FileManager.default.createDirectory(at: roots.destination, withIntermediateDirectories: true)

    let assessment = await PendingCopyRecoveryInspector().assess(
        recoveryDestinationIdentityRecord(glassID: glassID),
        destinationAccess: handle
    )

    #expect(assessment.disposition == .destinationUnavailable)
}

@Test
func recoveryCleanerRejectsDestinationPathReplacementBeforeDeletion() async throws {
    let roots = try makeRecoveryDestinationIdentityRoot()
    defer { try? FileManager.default.removeItem(at: roots.workspace) }

    let glassID = GlassID()
    let operationID = UUID()
    let stagingFilename = ".schneeglass-copy-\(operationID.uuidString.lowercased()).partial"
    let stagingURL = roots.destination.appendingPathComponent(stagingFilename, isDirectory: false)
    try Data("staging".utf8).write(to: stagingURL)
    let stagingIdentity = try #require(
        PendingCopyFileIdentity.createToken(at: stagingURL, fileManager: .default)
    )
    let handle = FolderAccessHandle(
        glassID: glassID,
        url: roots.destination,
        runtimeDirectoryIdentity: try acquiredRecoveryRuntimeIdentity(for: roots.destination)
    )
    let record = recoveryDestinationIdentityRecord(
        glassID: glassID,
        operationID: operationID,
        stagingResourceIdentifier: stagingIdentity
    )

    let movedDestination = roots.workspace.appendingPathComponent("original-destination", isDirectory: true)
    try FileManager.default.moveItem(at: roots.destination, to: movedDestination)
    try FileManager.default.createDirectory(at: roots.destination, withIntermediateDirectories: true)
    try FileManager.default.moveItem(
        at: movedDestination.appendingPathComponent(stagingFilename, isDirectory: false),
        to: stagingURL
    )

    let cleaner = OwnedStagingRecoveryCleaner()
    var rejectedReplacement = false
    do {
        try await cleaner.removeOwnedStaging(record: record, destinationAccess: handle)
    } catch let error as OwnedStagingRecoveryCleanupError {
        rejectedReplacement = error == .destinationMismatch
    }

    #expect(rejectedReplacement && FileManager.default.fileExists(atPath: stagingURL.path))
}

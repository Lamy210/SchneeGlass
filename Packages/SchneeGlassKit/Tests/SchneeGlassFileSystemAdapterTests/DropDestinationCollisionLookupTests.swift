import Foundation
import Testing
@testable import SchneeGlassFileSystemAdapter

@Test
func dropInspectorTreatsDanglingDestinationSymlinkAsExistingEntry() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "schneeglass-drop-collision-lookup-\(UUID().uuidString)",
            isDirectory: true
        )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let missingTarget = root.appendingPathComponent("missing-target.txt", isDirectory: false)
    let collision = root.appendingPathComponent("report.txt", isDirectory: false)
    try FileManager.default.createSymbolicLink(at: collision, withDestinationURL: missingTarget)

    let inspector = FoundationDropFileSystemInspector()

    #expect(await inspector.itemExists(at: collision))
    #expect(!(await inspector.itemExists(at: missingTarget)))
}

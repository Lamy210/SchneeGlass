import Foundation
import SchneeGlassPOSIXSupport
import Testing

private func makePOSIXIdentityRoot(_ name: String) throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "SchneeGlassPOSIXIdentity-\(name)-\(UUID().uuidString)",
            isDirectory: true
        )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

@Test
func directoryIdentityRemainsStableAcrossRename() throws {
    let root = try makePOSIXIdentityRoot("rename")
    let renamed = root.deletingLastPathComponent()
        .appendingPathComponent("\(root.lastPathComponent)-renamed", isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: renamed)
    }

    let before = try #require(POSIXDirectoryIdentityReader.identity(at: root))
    try FileManager.default.moveItem(at: root, to: renamed)
    let after = try #require(POSIXDirectoryIdentityReader.identity(at: renamed))

    #expect(after == before)
}

@Test
func directoryIdentityDetectsReplacementAtSamePath() throws {
    let parent = try makePOSIXIdentityRoot("replacement-parent")
    defer { try? FileManager.default.removeItem(at: parent) }

    let target = parent.appendingPathComponent("target", isDirectory: true)
    let replacement = parent.appendingPathComponent("replacement", isDirectory: true)
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
    try FileManager.default.createDirectory(at: replacement, withIntermediateDirectories: false)

    let originalIdentity = try #require(POSIXDirectoryIdentityReader.identity(at: target))
    let replacementIdentity = try #require(POSIXDirectoryIdentityReader.identity(at: replacement))
    #expect(originalIdentity != replacementIdentity)

    try FileManager.default.removeItem(at: target)
    try FileManager.default.moveItem(at: replacement, to: target)

    let currentIdentity = try #require(POSIXDirectoryIdentityReader.identity(at: target))
    #expect(currentIdentity == replacementIdentity)
    #expect(currentIdentity != originalIdentity)
}

@Test
func directoryIdentityRejectsRegularFiles() throws {
    let root = try makePOSIXIdentityRoot("regular-file")
    defer { try? FileManager.default.removeItem(at: root) }

    let file = root.appendingPathComponent("not-a-directory.txt", isDirectory: false)
    try Data("test".utf8).write(to: file)

    #expect(POSIXDirectoryIdentityReader.identity(at: file) == nil)
}

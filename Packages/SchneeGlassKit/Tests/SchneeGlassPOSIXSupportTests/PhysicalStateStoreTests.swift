import Foundation
import SchneeGlassPOSIXSupport
import Testing

private func makeStateRoot() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("schneeglass-physical-state-\(UUID().uuidString)", isDirectory: true)
}

@Test
func physicalStateStoreRoundTripsAtomicRegularFile() throws {
    let root = makeStateRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let store = PhysicalStateStore(rootURL: root)
    let first = Data("first".utf8)
    let second = Data("second".utf8)

    try store.writeAtomically(first, in: ["Configuration"], named: "config.json")
    #expect(try store.readRegularFile(in: ["Configuration"], named: "config.json") == first)

    try store.writeAtomically(second, in: ["Configuration"], named: "config.json")
    #expect(try store.readRegularFile(in: ["Configuration"], named: "config.json") == second)
}

@Test
func physicalStateStoreRejectsRootSymlinkWithoutTouchingTarget() throws {
    let fileManager = FileManager.default
    let parent = makeStateRoot()
    let target = parent.appendingPathComponent("target", isDirectory: true)
    let root = parent.appendingPathComponent("root", isDirectory: true)
    try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
    try fileManager.createSymbolicLink(at: root, withDestinationURL: target)
    defer { try? fileManager.removeItem(at: parent) }

    let store = PhysicalStateStore(rootURL: root)
    #expect(throws: PhysicalStateStoreError.unsafeTopology) {
        try store.writeAtomically(Data("payload".utf8), named: "state.json")
    }
    #expect(!fileManager.fileExists(atPath: target.appendingPathComponent("state.json").path))
}

@Test
func physicalStateStoreRejectsDescendantDirectorySymlinkWithoutTouchingTarget() throws {
    let fileManager = FileManager.default
    let root = makeStateRoot()
    let target = root.appendingPathComponent("target", isDirectory: true)
    let configuration = root.appendingPathComponent("Configuration", isDirectory: true)
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
    try fileManager.createSymbolicLink(at: configuration, withDestinationURL: target)
    defer { try? fileManager.removeItem(at: root) }

    let store = PhysicalStateStore(rootURL: root)
    #expect(throws: PhysicalStateStoreError.unsafeTopology) {
        try store.writeAtomically(
            Data("payload".utf8),
            in: ["Configuration"],
            named: "config.json"
        )
    }
    #expect(!fileManager.fileExists(atPath: target.appendingPathComponent("config.json").path))
}

@Test
func physicalStateStoreRejectsLeafSymlinkForReadAndWrite() throws {
    let fileManager = FileManager.default
    let root = makeStateRoot()
    let directory = root.appendingPathComponent("Configuration", isDirectory: true)
    let external = root.appendingPathComponent("external.json", isDirectory: false)
    let leaf = directory.appendingPathComponent("config.json", isDirectory: false)
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    let original = Data("external".utf8)
    try original.write(to: external)
    try fileManager.createSymbolicLink(at: leaf, withDestinationURL: external)
    defer { try? fileManager.removeItem(at: root) }

    let store = PhysicalStateStore(rootURL: root)
    #expect(throws: PhysicalStateStoreError.unsafeTopology) {
        _ = try store.readRegularFile(in: ["Configuration"], named: "config.json")
    }
    #expect(throws: PhysicalStateStoreError.unsafeTopology) {
        try store.writeAtomically(
            Data("replacement".utf8),
            in: ["Configuration"],
            named: "config.json"
        )
    }
    #expect(try Data(contentsOf: external) == original)
}

@Test
func regularFileListingExcludesSymlinkAndDirectoryEntries() throws {
    let fileManager = FileManager.default
    let root = makeStateRoot()
    let directory = root.appendingPathComponent("Backups", isDirectory: true)
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: root) }

    try Data("a".utf8).write(to: directory.appendingPathComponent("a.json"))
    try fileManager.createDirectory(
        at: directory.appendingPathComponent("directory.json", isDirectory: true),
        withIntermediateDirectories: true
    )
    try fileManager.createSymbolicLink(
        at: directory.appendingPathComponent("link.json"),
        withDestinationURL: directory.appendingPathComponent("a.json")
    )

    let store = PhysicalStateStore(rootURL: root)
    #expect(try store.regularFileNames(in: ["Backups"]) == ["a.json"])
}

@Test
func physicalStateStoreRemovesOnlyPhysicalRegularEntry() throws {
    let fileManager = FileManager.default
    let root = makeStateRoot()
    let directory = root.appendingPathComponent("Backups", isDirectory: true)
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: root) }

    let regular = directory.appendingPathComponent("backup.json")
    try Data("backup".utf8).write(to: regular)
    let store = PhysicalStateStore(rootURL: root)

    try store.removeRegularFile(in: ["Backups"], named: "backup.json")
    #expect(!fileManager.fileExists(atPath: regular.path))
}

import FileDomain
import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing
@testable import SchneeGlassFileSystemAdapter

private func makeTemporaryDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("SchneeGlassTests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
        at: root,
        withIntermediateDirectories: true
    )
    return root
}

private func makeAccessHandle(for url: URL) -> FolderAccessHandle {
    FolderAccessHandle(
        glassID: GlassID(),
        url: url,
        fingerprint: nil
    )
}

@Test
func snapshotReadsOnlyDirectChildrenAndSkipsHiddenFiles() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }

    let visibleFile = root.appendingPathComponent("visible.txt")
    try Data("visible".utf8).write(to: visibleFile)

    let hiddenFile = root.appendingPathComponent(".hidden.txt")
    try Data("hidden".utf8).write(to: hiddenFile)

    let nestedDirectory = root.appendingPathComponent("Nested", isDirectory: true)
    try FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
    try Data("nested".utf8).write(
        to: nestedDirectory.appendingPathComponent("nested.txt")
    )

    let reader = NativeFolderSnapshotReader()
    let snapshot = try await reader.snapshot(
        for: makeAccessHandle(for: root),
        generation: 7
    )

    let names = Set(snapshot.items.map(\.displayName))
    #expect(names.contains("visible.txt"))
    #expect(names.contains("Nested"))
    #expect(!names.contains(".hidden.txt"))
    #expect(!names.contains("nested.txt"))
    #expect(snapshot.generation == 7)
    #expect(!snapshot.isTruncated)
}

@Test
func snapshotClassifiesPackagesAndSymbolicLinksBeforeDirectories() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }

    let target = root.appendingPathComponent("target.txt")
    try Data("target".utf8).write(to: target)

    let symbolicLink = root.appendingPathComponent("target-link")
    try FileManager.default.createSymbolicLink(
        at: symbolicLink,
        withDestinationURL: target
    )

    let package = root.appendingPathComponent("Demo.app", isDirectory: true)
    try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)

    let reader = NativeFolderSnapshotReader()
    let snapshot = try await reader.snapshot(
        for: makeAccessHandle(for: root),
        generation: 1
    )

    let kinds = Dictionary(
        uniqueKeysWithValues: snapshot.items.map { ($0.displayName, $0.kind) }
    )

    #expect(kinds["target.txt"] == .regular)
    #expect(kinds["target-link"] == .symbolicLink)
    #expect(kinds["Demo.app"] == .package)
}

@Test
func snapshotStopsAfterDisplayLimitAndMarksTruncation() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }

    for index in 0...NativeFolderSnapshotReader.maximumDisplayedItems {
        let file = root.appendingPathComponent("file-\(index).txt")
        try Data().write(to: file)
    }

    let reader = NativeFolderSnapshotReader()
    let snapshot = try await reader.snapshot(
        for: makeAccessHandle(for: root),
        generation: 2
    )

    #expect(snapshot.items.count == NativeFolderSnapshotReader.maximumDisplayedItems)
    #expect(snapshot.isTruncated)
}

@Test
func snapshotPreservesUnicodeFilenames() async throws {
    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }

    let filenames = [
        "設計書.md",
        "雪❄️.png",
        "file #1 [final].txt",
    ]

    for filename in filenames {
        try Data(filename.utf8).write(to: root.appendingPathComponent(filename))
    }

    let reader = NativeFolderSnapshotReader()
    let snapshot = try await reader.snapshot(
        for: makeAccessHandle(for: root),
        generation: 3
    )

    let actual = Set(snapshot.items.map(\.displayName))
    for filename in filenames {
        #expect(actual.contains(filename))
    }
}

@Test
func snapshotPerformanceBaselineAtDisplayLimit() async throws {
    guard ProcessInfo.processInfo.environment["SCHNEEGLASS_PERFORMANCE_BASELINE"] == "1" else {
        return
    }

    let root = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }

    for index in 0...NativeFolderSnapshotReader.maximumDisplayedItems {
        let file = root.appendingPathComponent(String(format: "file-%04d.txt", index))
        let created = FileManager.default.createFile(atPath: file.path, contents: Data())
        #expect(created)
    }

    let reader = NativeFolderSnapshotReader()
    let access = makeAccessHandle(for: root)
    let processInfo = ProcessInfo.processInfo
    var durations: [TimeInterval] = []

    for generation in 1...3 {
        let startedAt = processInfo.systemUptime
        let snapshot = try await reader.snapshot(
            for: access,
            generation: UInt64(generation)
        )
        let duration = processInfo.systemUptime - startedAt
        durations.append(duration)

        #expect(snapshot.items.count == NativeFolderSnapshotReader.maximumDisplayedItems)
        #expect(snapshot.isTruncated)
    }

    let worst = durations.max() ?? .infinity
    let average = durations.reduce(0, +) / Double(durations.count)
    print(
        String(
            format: "SCHNEEGLASS_PERF_RESULT snapshot_500 average=%.6fs worst=%.6fs limit=0.500000s",
            average,
            worst
        )
    )

    #expect(worst < 0.5)
}

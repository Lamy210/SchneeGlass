import CoreServices
import Foundation
import SchneeGlassApplication
@testable import SchneeGlassFileSystemAdapter
import SchneeGlassDomain
import Testing

@Test("ordinary FSEvents flags map to a change notification")
func ordinaryFileEventMapsToChanged() {
    let flags = FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated)
    #expect(FileEventFlagMapper.map(flags) == .changed)
}

@Test(
    "dropped FSEvents flags require a full rescan",
    arguments: [
        FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs),
        FSEventStreamEventFlags(kFSEventStreamEventFlagKernelDropped),
        FSEventStreamEventFlags(kFSEventStreamEventFlagUserDropped),
    ]
)
func droppedFileEventRequiresFullRescan(flags: FSEventStreamEventFlags) {
    #expect(FileEventFlagMapper.map(flags) == .requiresFullRescan)
}

@Test("root changes take precedence over ordinary or dropped events")
func rootChangeMapsToRootChanged() {
    let flags =
        FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged)
        | FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs)

    #expect(FileEventFlagMapper.map(flags) == .rootChanged)
}

@Test("FSEvents stream eventually reports a direct filesystem change")
func fileEventHubReportsFilesystemChange() async throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appendingPathComponent("SchneeGlass-FSEvents-\(UUID().uuidString)", isDirectory: true)

    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    defer {
        try? fileManager.removeItem(at: root)
    }

    let glassID = GlassID()
    let access = FolderAccessHandle(glassID: glassID, url: root)
    let hub = FileEventHub(latency: 0.05)
    let stream = try await hub.events(for: access)

    try await Task.sleep(for: .milliseconds(100))
    try Data("changed".utf8).write(to: root.appendingPathComponent("event.txt"))

    let event = await firstEvent(from: stream, timeout: .seconds(5))
    #expect(event != nil)

    await hub.stopAll()
}

private func firstEvent(
    from stream: AsyncStream<FileEvent>,
    timeout: Duration
) async -> FileEvent? {
    await withTaskGroup(of: FileEvent?.self) { group in
        group.addTask {
            var iterator = stream.makeAsyncIterator()
            return await iterator.next()
        }
        group.addTask {
            try? await Task.sleep(for: timeout)
            return nil
        }

        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
}

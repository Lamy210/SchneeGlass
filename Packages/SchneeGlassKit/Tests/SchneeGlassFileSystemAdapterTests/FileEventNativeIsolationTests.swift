import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing

@testable import SchneeGlassFileSystemAdapter

@Test("stopping a native watcher does not disable another watched folder")
func nativeWatcherSiblingStopPreservesOtherFolderEvents() async throws {
  let manager = FileManager.default
  let root = manager.temporaryDirectory
    .appendingPathComponent("SchneeGlass-native-watchers-\(UUID().uuidString)", isDirectory: true)
  try manager.createDirectory(at: root, withIntermediateDirectories: false)
  defer {
    do {
      try manager.removeItem(at: root)
    } catch {
      Issue.record("Could not remove disposable multi-watcher test directory")
    }
  }

  let firstFolder = root.appendingPathComponent("first", isDirectory: true)
  let secondFolder = root.appendingPathComponent("second", isDirectory: true)
  try manager.createDirectory(at: firstFolder, withIntermediateDirectories: false)
  try manager.createDirectory(at: secondFolder, withIntermediateDirectories: false)

  let hub = FileEventHub(latency: 0.05)
  do {
    let first = try await hub.subscribe(
      for: FolderAccessHandle(glassID: GlassID(), url: firstFolder)
    )
    let second = try await hub.subscribe(
      for: FolderAccessHandle(glassID: GlassID(), url: secondFolder)
    )
    #expect(first.id != second.id)
    #expect(await hub.activeSubscriptionCount == 2)

    // Both native FSEvent streams are active before changes are made.
    try await Task.sleep(for: .milliseconds(100))
    try Data("first change".utf8).write(
      to: firstFolder.appendingPathComponent("first.txt")
    )
    #expect(await firstNativeEvent(from: first.events, timeout: .seconds(5)) != nil)

    await hub.stop(subscriptionID: first.id)
    #expect(await hub.activeSubscriptionCount == 1)

    // A stopped sibling must not dispose the callback context or event
    // delivery of the other real, distinct directory subscription.
    try Data("second change".utf8).write(
      to: secondFolder.appendingPathComponent("second.txt")
    )
    #expect(await firstNativeEvent(from: second.events, timeout: .seconds(5)) != nil)

    await hub.stopAll()
    #expect(await hub.activeSubscriptionCount == 0)
  } catch {
    await hub.stopAll()
    throw error
  }
}

private func firstNativeEvent(
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

    let event = await group.next() ?? nil
    group.cancelAll()
    return event
  }
}

@Test("a native watcher can restart after stopAll without stale state")
func nativeWatcherCanRestartAfterStopAll() async throws {
  let manager = FileManager.default
  let folder = manager.temporaryDirectory
    .appendingPathComponent("SchneeGlass-watch-restart-\(UUID().uuidString)", isDirectory: true)
  try manager.createDirectory(at: folder, withIntermediateDirectories: false)
  defer {
    do {
      try manager.removeItem(at: folder)
    } catch {
      Issue.record("Could not remove disposable restart test folder")
    }
  }

  let hub = FileEventHub(latency: 0.05)
  let access = FolderAccessHandle(glassID: GlassID(), url: folder)
  do {
    let first = try await hub.subscribe(for: access)
    #expect(await hub.activeSubscriptionCount == 1)
    try await Task.sleep(for: .milliseconds(100))
    try Data("before restart".utf8).write(to: folder.appendingPathComponent("before.txt"))
    #expect(await firstNativeEvent(from: first.events, timeout: .seconds(5)) != nil)

    await hub.stopAll()
    await hub.stopAll()
    #expect(await hub.activeSubscriptionCount == 0)

    // A finished AsyncStream may still contain one buffered event.
    var firstIterator = first.events.makeAsyncIterator()
    if await firstIterator.next() != nil {
      #expect(await firstIterator.next() == nil)
    }

    let replacement = try await hub.subscribe(for: access)
    #expect(first.id != replacement.id)
    #expect(await hub.activeSubscriptionCount == 1)
    try await Task.sleep(for: .milliseconds(100))
    try Data("after restart".utf8).write(to: folder.appendingPathComponent("after.txt"))
    #expect(await firstNativeEvent(from: replacement.events, timeout: .seconds(5)) != nil)

    await hub.stop(subscriptionID: first.id)
    #expect(await hub.activeSubscriptionCount == 1)
    await hub.stopAll()
    #expect(await hub.activeSubscriptionCount == 0)
  } catch {
    await hub.stopAll()
    throw error
  }
}

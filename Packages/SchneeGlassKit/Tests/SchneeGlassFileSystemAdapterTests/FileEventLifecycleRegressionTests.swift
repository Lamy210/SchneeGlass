import Foundation
import os
import SchneeGlassApplication
import SchneeGlassDomain
import Testing

@testable import SchneeGlassFileSystemAdapter

@Test
func repeatedMultiGlassWatcherLifecycleReleasesEverySubscription() async throws {
  let manager = FileManager.default
  let root = manager.temporaryDirectory
    .appendingPathComponent("SchneeGlass-watcher-lifecycle-\(UUID().uuidString)", isDirectory: true)
  try manager.createDirectory(at: root, withIntermediateDirectories: false)
  defer {
    do {
      try manager.removeItem(at: root)
    } catch {
      Issue.record("Could not remove disposable watcher test directory")
    }
  }

  let hub = FileEventHub(latency: 0.05)
  let folders = (0..<4).map {
    root.appendingPathComponent("folder-\($0)", isDirectory: true)
  }
  for folder in folders {
    try manager.createDirectory(at: folder, withIntermediateDirectories: false)
  }

  do {
    for _ in 0..<8 {
      var subscriptions: [FileEventSubscription] = []
      for folder in folders {
        let access = FolderAccessHandle(glassID: GlassID(), url: folder)
        subscriptions.append(try await hub.subscribe(for: access))
      }
      #expect(await hub.activeSubscriptionCount == folders.count)
      #expect(Set(subscriptions.map(\.id)).count == folders.count)

      // Stopping one watcher must not unregister any other watcher.
      let first = subscriptions[0]
      await hub.stop(subscriptionID: first.id)
      #expect(await hub.activeSubscriptionCount == folders.count - 1)
      await hub.stop(subscriptionID: first.id)
      #expect(await hub.activeSubscriptionCount == folders.count - 1)

      await hub.stopAll()
      await hub.stopAll()
      #expect(await hub.activeSubscriptionCount == 0)
      for subscription in subscriptions {
        // A finished bufferingNewest(1) stream can retain at most one event.
        var iterator = subscription.events.makeAsyncIterator()
        if await iterator.next() != nil {
          #expect(await iterator.next() == nil)
        }
      }
    }
  } catch {
    await hub.stopAll()
    throw error
  }
}

@Test
func fileEventBurstKeepsStrongestEventAcrossIndependentBuffers() async {
  let pairs = (0..<4).map { _ in
    AsyncStream<FileEvent>.makeStream(bufferingPolicy: .bufferingNewest(1))
  }
  let boxes = pairs.map { FSEventCallbackBox(continuation: $0.continuation) }
  boxes[1].yield(.requiresFullRescan)
  boxes[2].yield(.rootChanged)
  boxes[3].yield(.requiresFullRescan)
  for _ in 0..<10_000 {
    for box in boxes {
      box.yield(.changed)
    }
  }
  boxes[3].yield(.rootChanged)
  let expected: [FileEvent] = [.changed, .requiresFullRescan, .rootChanged, .rootChanged]
  for (index, pair) in pairs.enumerated() {
    pair.continuation.finish()
    var iterator = pair.stream.makeAsyncIterator()
    #expect(await iterator.next() == expected[index])
    #expect(await iterator.next() == nil)
  }
}

@Test
func cancelledWatcherConsumerDoesNotStopSiblingOrReplacementSubscription() async throws {
  let manager = FileManager.default
  let root = manager.temporaryDirectory
    .appendingPathComponent("SchneeGlass-watcher-cancel-\(UUID().uuidString)", isDirectory: true)
  try manager.createDirectory(at: root, withIntermediateDirectories: false)
  defer {
    do {
      try manager.removeItem(at: root)
    } catch {
      Issue.record("Could not remove disposable watcher test directory")
    }
  }

  let hub = FileEventHub(latency: 0.05)
  let access = FolderAccessHandle(glassID: GlassID(), url: root)
  do {
    let old = try await hub.subscribe(for: access)
    let sibling = try await hub.subscribe(
      for: FolderAccessHandle(glassID: GlassID(), url: root)
    )
    #expect(await hub.activeSubscriptionCount == 2)

    let consumer = Task {
      for await _ in old.events {}
    }
    consumer.cancel()
    await consumer.value

    // AsyncStream termination schedules an actor job, so cancellation alone
    // does not synchronously guarantee that the native subscription is gone.
    let clock = ContinuousClock()
    let deadline = clock.now + .seconds(5)
    while await hub.activeSubscriptionCount != 1 && clock.now < deadline {
      try await Task.sleep(for: .milliseconds(10))
    }
    try #require(await hub.activeSubscriptionCount == 1)

    let replacement = try await hub.subscribe(for: access)
    #expect(replacement.id != old.id)
    #expect(replacement.id != sibling.id)
    #expect(await hub.activeSubscriptionCount == 2)

    // Late cleanup of the old subscription ID must not affect the replacement.
    await hub.stop(subscriptionID: old.id)
    #expect(await hub.activeSubscriptionCount == 2)
    await hub.stop(subscriptionID: sibling.id)
    #expect(await hub.activeSubscriptionCount == 1)
    await hub.stop(subscriptionID: replacement.id)
    #expect(await hub.activeSubscriptionCount == 0)
  } catch {
    await hub.stopAll()
    throw error
  }
}

@Test
func cancelledWatcherSubscriptionNeverReplacesOrLeaksActiveSibling() async throws {
  let manager = FileManager.default
  let folderName = "SchneeGlass-watcher-pre-cancel-\(UUID().uuidString)"
  let root = manager.temporaryDirectory.appendingPathComponent(folderName, isDirectory: true)
  try manager.createDirectory(at: root, withIntermediateDirectories: false)
  defer {
    do {
      try manager.removeItem(at: root)
    } catch {
      Issue.record("Could not remove disposable watcher test directory")
    }
  }

  let hub = FileEventHub(latency: 0.05)
  let first = try await hub.subscribe(for: FolderAccessHandle(glassID: GlassID(), url: root))
  let rejected = Task {
    withUnsafeCurrentTask { current in
      current?.cancel()
    }
    do {
      _ = try await hub.subscribe(for: FolderAccessHandle(glassID: GlassID(), url: root))
      return false
    } catch is CancellationError {
      return true
    } catch {
      return false
    }
  }
  #expect(await rejected.value)
  #expect(await hub.activeSubscriptionCount == 1)
  await hub.stop(subscriptionID: first.id)
  #expect(await hub.activeSubscriptionCount == 0)
}

@Test
func watcherLifecycleReportsOnlyCommittedSubscriptionCountChanges() async throws {
  let manager = FileManager.default
  let root = manager.temporaryDirectory
    .appendingPathComponent("SchneeGlass-watcher-count-\(UUID().uuidString)", isDirectory: true)
  try manager.createDirectory(at: root, withIntermediateDirectories: false)
  defer {
    do {
      try manager.removeItem(at: root)
    } catch {
      Issue.record("Could not remove disposable watcher diagnostic directory")
    }
  }

  let counts = OSAllocatedUnfairLock(initialState: [Int]())
  let hub = FileEventHub(latency: 0.05) { count in
    counts.withLock { $0.append(count) }
  }
  let access = FolderAccessHandle(glassID: GlassID(), url: root)
  do {
    let first = try await hub.subscribe(for: access)
    let second = try await hub.subscribe(for: access)
    await hub.stop(subscriptionID: first.id)
    await hub.stop(subscriptionID: first.id)
    await hub.stopAll()
    await hub.stopAll()
    #expect(await hub.activeSubscriptionCount == 0)
    #expect(counts.withLock { $0 } == [0, 1, 2, 1, 0])

    let replacement = try await hub.subscribe(for: access)
    await hub.stop(subscriptionID: second.id)
    await hub.stop(subscriptionID: replacement.id)
    #expect(counts.withLock { $0 } == [0, 1, 2, 1, 0, 1, 0])
  } catch {
    await hub.stopAll()
    throw error
  }
}

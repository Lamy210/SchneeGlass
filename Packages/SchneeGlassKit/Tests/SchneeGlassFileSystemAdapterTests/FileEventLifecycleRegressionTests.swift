import Foundation
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

import AppKit
import Foundation
import Testing

@testable import SchneeGlassMacOSAdapter

@MainActor
private final class FolderSelectionCancellationTestPanel: NativeFolderSelectionPanel {
  let selectedURL: URL?
  let started = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
  private(set) var beginCount = 0
  private(set) var cancelCount = 0
  private var completionHandler: ((NSApplication.ModalResponse) -> Void)?

  init(selectedURL: URL?) {
    self.selectedURL = selectedURL
  }

  var url: URL? {
    selectedURL
  }

  func begin(completionHandler handler: @escaping (NSApplication.ModalResponse) -> Void) {
    beginCount += 1
    completionHandler = handler
    started.continuation.yield(())
  }

  func cancel(_ sender: Any?) {
    _ = sender
    cancelCount += 1
    let completionHandler = completionHandler
    self.completionHandler = nil
    completionHandler?(.cancel)
  }

  func complete(_ response: NSApplication.ModalResponse) {
    let completionHandler = completionHandler
    self.completionHandler = nil
    completionHandler?(response)
  }
}

@Test
@MainActor
func preCancelledFolderSelectionDoesNotOpenPanel() async {
  let panel = FolderSelectionCancellationTestPanel(
    selectedURL: URL(fileURLWithPath: "/tmp/selected", isDirectory: true)
  )

  let task = Task { @MainActor in
    withUnsafeCurrentTask { current in
      current?.cancel()
    }
    return await awaitNativeFolderSelection(using: panel)
  }

  let result = await task.value

  #expect(result == nil)
  #expect(panel.beginCount == 0)
  #expect(panel.cancelCount == 0)
}

@Test
@MainActor
func cancellingFolderSelectionClosesPanelAndReturnsNil() async {
  let panel = FolderSelectionCancellationTestPanel(
    selectedURL: URL(fileURLWithPath: "/tmp/selected", isDirectory: true)
  )
  let task = Task { @MainActor in
    await awaitNativeFolderSelection(using: panel)
  }

  var iterator = panel.started.stream.makeAsyncIterator()
  _ = await iterator.next()
  task.cancel()
  let result = await task.value

  #expect(result == nil)
  #expect(panel.beginCount == 1)
  #expect(panel.cancelCount == 1)
}

@Test
@MainActor
func successfulFolderSelectionReturnsSelectedURLWithoutCancellation() async {
  let selectedURL = URL(fileURLWithPath: "/tmp/selected", isDirectory: true)
  let panel = FolderSelectionCancellationTestPanel(selectedURL: selectedURL)
  let task = Task { @MainActor in
    await awaitNativeFolderSelection(using: panel)
  }

  var iterator = panel.started.stream.makeAsyncIterator()
  _ = await iterator.next()
  panel.complete(.OK)

  #expect(await task.value == selectedURL)
  #expect(panel.beginCount == 1)
  #expect(panel.cancelCount == 0)
}

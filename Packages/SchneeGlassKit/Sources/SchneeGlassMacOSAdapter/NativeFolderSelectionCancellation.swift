import AppKit

@MainActor
protocol NativeFolderSelectionPanel: AnyObject {
  var url: URL? { get }
  func begin(completionHandler handler: @escaping (NSApplication.ModalResponse) -> Void)
  func cancel(_ sender: Any?)
}

extension NSOpenPanel: NativeFolderSelectionPanel {}

@MainActor
private final class NativeFolderSelectionCancellationState {
  private let panel: any NativeFolderSelectionPanel
  private var continuation: CheckedContinuation<URL?, Never>?
  private var isCancelled = false
  private var isFinished = false

  init(panel: any NativeFolderSelectionPanel) {
    self.panel = panel
  }

  func begin() async -> URL? {
    await withCheckedContinuation { continuation in
      guard !isFinished else {
        continuation.resume(returning: nil)
        return
      }
      guard !isCancelled else {
        isFinished = true
        continuation.resume(returning: nil)
        return
      }

      self.continuation = continuation
      panel.begin { [weak self] response in
        let didAccept = response == .OK
        Task { @MainActor [weak self, didAccept] in
          self?.finish(didAccept: didAccept)
        }
      }
    }
  }

  func cancel() {
    guard !isFinished else {
      return
    }

    isCancelled = true
    guard continuation != nil else {
      return
    }

    // Resume ourselves instead of depending on AppKit to invoke the panel completion after cancel.
    // Any late completion is ignored by finish(), which prevents a double resume.
    panel.cancel(nil)
    finish(nil)
  }

  private func finish(_ result: URL?) {
    guard !isFinished else {
      return
    }

    isFinished = true
    let continuation = continuation
    self.continuation = nil
    continuation?.resume(returning: result)
  }

  private func finish(didAccept: Bool) {
    finish(didAccept ? panel.url : nil)
  }
}

@MainActor
func awaitNativeFolderSelection(
  using panel: any NativeFolderSelectionPanel
) async -> URL? {
  guard !Task.isCancelled else {
    return nil
  }

  let state = NativeFolderSelectionCancellationState(panel: panel)

  return await withTaskCancellationHandler {
    await state.begin()
  } onCancel: {
    Task { @MainActor in
      state.cancel()
    }
  }
}

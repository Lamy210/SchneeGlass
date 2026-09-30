import AppKit

@MainActor
protocol NativeFolderSelectionPanel: AnyObject {
  var url: URL? { get }
  func begin(completionHandler handler: @escaping (NSApplication.ModalResponse) -> Void)
  func cancel(_ sender: Any?)
}

extension NSOpenPanel: NativeFolderSelectionPanel {}

@MainActor
func awaitNativeFolderSelection(
  using panel: any NativeFolderSelectionPanel
) async -> URL? {
  guard !Task.isCancelled else {
    return nil
  }

  return await withTaskCancellationHandler {
    await withCheckedContinuation { continuation in
      panel.begin { response in
        continuation.resume(returning: response == .OK ? panel.url : nil)
      }
    }
  } onCancel: {
    Task { @MainActor [weak panel] in
      panel?.cancel(nil)
    }
  }
}

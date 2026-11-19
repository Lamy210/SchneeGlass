import AppKit
import SchneeGlassApplication

@MainActor
public final class NativeFolderReconnectSelector: FolderSelecting {
  private let prompt: String
  private let message: String

  public init() {
    prompt = "Reconnect"
    message =
      "Choose the original folder for this Glass. SchneeGlass will verify its persistent identity before reconnecting."
  }

  public init(prompt: String, message: String) {
    self.prompt = prompt
    self.message = message
  }

  public func selectFolder() async -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = false
    panel.resolvesAliases = true
    panel.prompt = prompt
    panel.message = message

    return await awaitNativeFolderSelection(using: panel)
  }
}

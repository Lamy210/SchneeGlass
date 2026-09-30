import AppKit
import SchneeGlassApplication

@MainActor
public final class NativeFolderReconnectSelector: FolderSelecting {
  public init() {}

  public func selectFolder() async -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = false
    panel.resolvesAliases = true
    panel.prompt = "Reconnect"
    panel.message =
      "Choose the original folder for this Glass. SchneeGlass will verify its persistent identity before reconnecting."

    return await awaitNativeFolderSelection(using: panel)
  }
}

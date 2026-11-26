import AppKit
import KeyboardShortcuts

public enum DesktopGlassVisibilityMode: Hashable, Sendable {
  case shown
  case hidden

  public var presentsPanels: Bool {
    self == .shown
  }

  public func toggled(hasGlasses: Bool) -> DesktopGlassVisibilityMode {
    guard hasGlasses else {
      return self
    }
    return self == .shown ? .hidden : .shown
  }
}

@MainActor
public final class SchneeGlassGlobalVisibilityShortcutController: NSObject {
  private static let shortcutName = KeyboardShortcuts.Name("toggleGlassVisibility")
  private static weak var activeController: SchneeGlassGlobalVisibilityShortcutController?

  private var isStopped = false
  private let onToggle: @MainActor @Sendable () -> Void

  public init(
    onToggle: @escaping @MainActor @Sendable () -> Void
  ) {
    self.onToggle = onToggle
    super.init()

    // Previews/tests can replace this controller. Stop the old owner as well as
    // its handler so previously queued key-up tasks cannot fire afterward.
    Self.activeController?.stop()
    Self.activeController = self
    KeyboardShortcuts.removeHandler(for: Self.shortcutName)
    KeyboardShortcuts.onKeyUp(for: Self.shortcutName) { [weak self] in
      Task { @MainActor [weak self] in
        self?.deliverToggleIfActive()
      }
    }

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(applicationWillTerminate(_:)),
      name: NSApplication.willTerminateNotification,
      object: nil
    )
  }

  public static func makeRecorderView() -> NSView {
    makeRecorderView(accessibilityLabel: "Show or hide all Glasses global shortcut")
  }

  public static func makeRecorderView(accessibilityLabel: String) -> NSView {
    let recorder = KeyboardShortcuts.RecorderCocoa(for: shortcutName)
    recorder.setAccessibilityLabel(accessibilityLabel)
    return recorder
  }

  // A queued key-up Task may run after stop() removes the keyboard handler.
  // Check state at delivery time, not only when the event was scheduled.
  func deliverToggleIfActive() {
    guard !isStopped else { return }
    onToggle()
  }

  public func stop() {
    guard !isStopped else {
      return
    }
    isStopped = true
    NotificationCenter.default.removeObserver(self)
    // An older controller must not remove the newer owner's handler.
    if Self.activeController === self {
      Self.activeController = nil
      KeyboardShortcuts.removeHandler(for: Self.shortcutName)
    }
  }

  @objc
  private func applicationWillTerminate(_ notification: Notification) {
    stop()
  }
}

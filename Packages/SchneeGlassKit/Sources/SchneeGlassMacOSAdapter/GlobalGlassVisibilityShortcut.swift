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

    private var isStopped = false

    public init(
        onToggle: @escaping @MainActor @Sendable () -> Void
    ) {
        super.init()

        // App initialization can be repeated by previews/tests. Replace an existing legacy
        // handler instead of accumulating callbacks for the same persisted shortcut name.
        KeyboardShortcuts.removeHandler(for: Self.shortcutName)
        KeyboardShortcuts.onKeyUp(for: Self.shortcutName) {
            Task { @MainActor in
                onToggle()
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
        let recorder = KeyboardShortcuts.RecorderCocoa(for: shortcutName)
        recorder.setAccessibilityLabel("Show or hide all Glasses global shortcut")
        return recorder
    }

    public func stop() {
        guard !isStopped else {
            return
        }
        isStopped = true
        NotificationCenter.default.removeObserver(self)
        KeyboardShortcuts.removeHandler(for: Self.shortcutName)
    }

    @objc
    private func applicationWillTerminate(_ notification: Notification) {
        stop()
    }
}

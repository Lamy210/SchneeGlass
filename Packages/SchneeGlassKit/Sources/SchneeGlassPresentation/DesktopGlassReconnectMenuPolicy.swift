import SchneeGlassApplication

/// Desktop reconnect command must only appear for a disconnected source.
/// Authoritative configuration/copy-operation checks remain in the workspace model.
enum DesktopGlassReconnectMenuPolicy {
  static func isVisible(for state: GlassContentState) -> Bool {
    if case .unavailable = state {
      return true
    }
    return false
  }

  static func isEnabled(
    for state: GlassContentState,
    canReconnectSource: Bool
  ) -> Bool {
    isVisible(for: state) && canReconnectSource
  }
}

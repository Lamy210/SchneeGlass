import SchneeGlassApplication

enum GlassInteractionPolicy {
  static func allowsRemoval(
    during state: InteractionState,
    isDropBusy: Bool = false
  ) -> Bool {
    // The execution reservation precedes the copying UI. A stale idle or
    // invalid state must not offer removal while a Drop is being re-planned.
    guard !isDropBusy else { return false }
    switch state {
    case .idle, .dropInvalid:
      return true
    case .hovered, .dropValid, .copying:
      return false
    }
  }

  static func allowsCopyCancellation(during state: InteractionState) -> Bool {
    switch state {
    case .copying:
      return true
    case .idle, .hovered, .dropValid, .dropInvalid:
      return false
    }
  }

  /// A rejected overlapping Drop must not replace live copy progress or its
  /// cancellation control. The execution gate covers the re-planning window
  /// before the UI has transitioned to .copying.
  static func allowsRejectedDropFeedback(
    during state: InteractionState,
    hasActiveExecution: Bool
  ) -> Bool {
    !hasActiveExecution && !allowsCopyCancellation(during: state)
  }
}

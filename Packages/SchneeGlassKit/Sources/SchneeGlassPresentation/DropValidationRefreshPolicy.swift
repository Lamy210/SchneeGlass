import Foundation

struct DropValidationRefreshPolicy {
  enum Decision: Hashable, Sendable {
    case start(isNewSignature: Bool)
    case skip
  }

  private(set) var currentSignature: String?
  private(set) var approvedSignature: String?
  private var lastStartedAt: TimeInterval?
  private let minimumInterval: TimeInterval

  init(minimumInterval: TimeInterval = 0.5) {
    self.minimumInterval = minimumInterval
  }

  mutating func decision(
    for signature: String,
    now: TimeInterval,
    validationInFlight: Bool
  ) -> Decision {
    if currentSignature != signature {
      currentSignature = signature
      approvedSignature = nil
      lastStartedAt = now
      return .start(isNewSignature: true)
    }

    guard
      !validationInFlight,
      let lastStartedAt,
      now - lastStartedAt >= minimumInterval
    else {
      return .skip
    }

    // A refresh must never reuse the previous successful hover approval.
    // Until the fresh asynchronous plan resolves, the drag advertises no copy.
    approvedSignature = nil
    self.lastStartedAt = now
    return .start(isNewSignature: false)
  }

  mutating func resolve(signature: String, accepted: Bool) {
    guard currentSignature == signature else {
      return
    }
    approvedSignature = accepted ? signature : nil
  }

  mutating func reset() {
    currentSignature = nil
    approvedSignature = nil
    lastStartedAt = nil
  }
}

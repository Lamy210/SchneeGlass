import Foundation

struct DropValidationRefreshPolicy {
    enum Decision: Hashable, Sendable {
        case start(isNewSignature: Bool)
        case skip
    }

    private(set) var currentSignature: String?
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
            lastStartedAt = now
            return .start(isNewSignature: true)
        }

        guard !validationInFlight,
              let lastStartedAt,
              now - lastStartedAt >= minimumInterval
        else {
            return .skip
        }

        self.lastStartedAt = now
        return .start(isNewSignature: false)
    }

    mutating func reset() {
        currentSignature = nil
        lastStartedAt = nil
    }
}

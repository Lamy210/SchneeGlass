import SchneeGlassApplication

enum GlassInteractionPolicy {
    static func allowsRemoval(during state: InteractionState) -> Bool {
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
}

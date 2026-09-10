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
}

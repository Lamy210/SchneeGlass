import SchneeGlassApplication

struct GlassContentStatusPresentation: Equatable {
    let label: String
    let systemImage: String

    static func make(for state: GlassContentState) -> Self? {
        switch state {
        case .loading:
            return nil
        case .ready:
            return Self(label: "Connected", systemImage: "checkmark.circle")
        case .empty:
            return Self(label: "Empty", systemImage: "tray")
        case .unavailable:
            return Self(label: "Unavailable", systemImage: "exclamationmark.circle")
        case let .failed(error):
            return Self(
                label: GlassContentFailurePresentation.make(for: error).status,
                systemImage: "arrow.clockwise.circle"
            )
        }
    }
}

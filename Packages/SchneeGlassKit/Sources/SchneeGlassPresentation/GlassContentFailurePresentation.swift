import SchneeGlassApplication

struct GlassContentFailurePresentation: Equatable {
    let status: String
    let title: String
    let detail: String

    static func make(for error: GlassContentError) -> Self {
        switch error {
        case .enumerationFailed, .metadataFailed:
            return Self(
                status: "Refresh failed",
                title: "Couldn't refresh this folder",
                detail: "SchneeGlass will retry when the folder changes."
            )
        case .unexpected:
            return Self(
                status: "Needs reconnect",
                title: "This Glass needs to reconnect",
                detail: "Restart SchneeGlass to retry. If it still fails, use Recovery."
            )
        }
    }
}

struct GlassUnavailablePresentation: Equatable {
    let title: String
    let detail: String

    static let current = Self(
        title: "Folder unavailable",
        detail: "Restart SchneeGlass to retry access. If it remains unavailable, remove this Glass and add the folder again. If removal is blocked by an interrupted copy, resolve it in Settings > Pending Copy Recovery first."
    )
}

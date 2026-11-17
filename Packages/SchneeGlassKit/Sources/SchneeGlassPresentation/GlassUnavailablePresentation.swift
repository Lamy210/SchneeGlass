struct GlassUnavailablePresentation: Equatable {
  let title: String
  let detail: String

  static let current = Self(
    title: "Folder unavailable",
    detail:
      "Reconnect the original folder to restore access without removing this Glass. If Reconnect is disabled, wait for the current operation to finish or restart SchneeGlass. Pending Copy Recovery in Settings is for interrupted copies."
  )
}

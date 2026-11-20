import Foundation

/// Empty Glass onboarding strings; explicit locale keeps tests and snapshots deterministic.
struct DesktopGlassEmptyPresentation: Equatable {
  let title: String
  let detail: String

  static func make(locale: Locale = Locale(identifier: "en")) -> Self {
    Self(
      title: GlassLocalizedText.desktopEmptyDropTitle.resolve(locale: locale),
      detail: GlassLocalizedText.desktopEmptyDropDetail.resolve(locale: locale)
    )
  }
}

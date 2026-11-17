import Foundation
import SchneeGlassApplication

struct GlassContentFailurePresentation: Equatable {
  let status: String
  let title: String
  let detail: String

  static func make(
    for error: GlassContentError,
    locale: Locale = Locale(identifier: "en")
  ) -> Self {
    switch error {
    case .enumerationFailed, .metadataFailed:
      return Self(
        status: GlassLocalizedText.refreshFailed.resolve(locale: locale),
        title: GlassLocalizedText.refreshFailedTitle.resolve(locale: locale),
        detail: GlassLocalizedText.refreshFailedDetail.resolve(locale: locale)
      )
    case .unexpected:
      return Self(
        status: GlassLocalizedText.needsAttention.resolve(locale: locale),
        title: GlassLocalizedText.unexpectedTitle.resolve(locale: locale),
        detail: GlassLocalizedText.unexpectedDetail.resolve(locale: locale)
      )
    }
  }
}

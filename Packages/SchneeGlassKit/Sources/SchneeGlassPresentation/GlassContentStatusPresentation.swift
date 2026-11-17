import Foundation
import SchneeGlassApplication

struct GlassContentStatusPresentation: Equatable {
  let label: String
  let systemImage: String

  static func make(
    for state: GlassContentState,
    locale: Locale = Locale(identifier: "en")
  ) -> Self? {
    switch state {
    case .loading:
      return nil
    case .ready:
      return Self(
        label: GlassLocalizedText.connected.resolve(locale: locale), systemImage: "checkmark.circle"
      )
    case .empty:
      return Self(label: GlassLocalizedText.empty.resolve(locale: locale), systemImage: "tray")
    case .unavailable:
      return Self(
        label: GlassLocalizedText.unavailable.resolve(locale: locale),
        systemImage: "exclamationmark.circle"
      )
    case .failed(let error):
      return Self(
        label: GlassContentFailurePresentation.make(for: error, locale: locale).status,
        systemImage: "arrow.clockwise.circle"
      )
    }
  }
}

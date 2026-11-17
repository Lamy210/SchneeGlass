import Foundation

struct GlassUnavailablePresentation: Equatable {
  let title: String
  let detail: String

  static var current: Self {
    make(locale: Locale(identifier: "en"))
  }

  static func make(locale: Locale) -> Self {
    Self(
      title: GlassLocalizedText.unavailableTitle.resolve(locale: locale),
      detail: GlassLocalizedText.unavailableDetail.resolve(locale: locale)
    )
  }
}

import Foundation
import SchneeGlassApplication

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

  static func make(for reason: UnavailableReason, locale: Locale) -> Self {
    let detail: GlassLocalizedText
    switch reason {
    case .permissionLost:
      detail = .unavailablePermissionDetail
    case .sourceMissing:
      detail = .unavailableMissingDetail
    case .volumeUnavailable:
      detail = .unavailableVolumeDetail
    case .bookmarkResolutionFailed:
      detail = .unavailableBookmarkDetail
    case .replacementDetected:
      detail = .unavailableReplacementDetail
    case .unsupportedLocation:
      detail = .unavailableUnsupportedDetail
    }

    return Self(
      title: GlassLocalizedText.unavailableTitle.resolve(locale: locale),
      detail: detail.resolve(locale: locale)
    )
  }
}

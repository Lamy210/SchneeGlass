import FileDomain
import Foundation
import SchneeGlassApplication

enum GlassInteractionPresentationSurface: Equatable {
  case workspace
  case desktop
}

struct GlassInteractionPresentation: Equatable {
  enum Indicator: Equatable {
    case symbol(String)
    case progress
  }

  let indicator: Indicator
  let title: String
  let detail: String?

  static func hovered(
    surface: GlassInteractionPresentationSurface,
    locale: Locale = Locale(identifier: "en")
  ) -> Self {
    Self(
      indicator: surface == .workspace ? .progress : .symbol("ellipsis"),
      title: GlassLocalizedText.checkingFiles.resolve(locale: locale),
      detail: nil
    )
  }

  static func dropValid(
    plan: DropPlan,
    glassTitle: String,
    surface: GlassInteractionPresentationSurface
  ) -> Self? {
    guard case .copy(let batch) = plan else {
      guard surface == .workspace else {
        return nil
      }
      return Self(
        indicator: .symbol("plus.circle.fill"),
        title: "Copy to \(glassTitle)",
        detail: "Original files stay where they are."
      )
    }

    let title: String
    if batch.items.count == 1, let item = batch.items.first {
      title = "Copy \(item.destinationFilename) to \(glassTitle)"
    } else {
      title = "Copy \(batch.items.count) files to \(glassTitle)"
    }

    return Self(
      indicator: .symbol(surface == .workspace ? "plus.circle.fill" : "doc.on.doc"),
      title: title,
      detail: "Original files stay where they are."
    )
  }

  static func dropInvalid(
    reason: DropRejection,
    glassTitle: String,
    surface: GlassInteractionPresentationSurface,
    locale: Locale = Locale(identifier: "en")
  ) -> Self {
    Self(
      indicator: .symbol("nosign"),
      title: rejectionTitle(
        reason,
        glassTitle: glassTitle,
        surface: surface,
        locale: locale
      ),
      detail: rejectionDetail(reason, surface: surface, locale: locale)
    )
  }

  static func copying(
    progress: CopyProgress,
    glassTitle: String,
    surface: GlassInteractionPresentationSurface,
    locale: Locale = Locale(identifier: "en")
  ) -> Self {
    switch surface {
    case .workspace:
      let detail: String
      if progress.totalCount <= 1 {
        detail = progress.currentFilename
      } else {
        detail = String(
          format: GlassLocalizedText.copyProgressWithFilename.resolve(locale: locale),
          locale: locale,
          Int64(progress.currentIndex), Int64(progress.totalCount), progress.currentFilename
        )
      }
      return Self(
        indicator: .progress,
        title: String(
          format: GlassLocalizedText.copyingToGlass.resolve(locale: locale),
          locale: locale,
          glassTitle
        ),
        detail: detail
      )

    case .desktop:
      let title: String
      if progress.totalCount == 1 {
        title = String(
          format: GlassLocalizedText.copyingFilename.resolve(locale: locale),
          locale: locale,
          progress.currentFilename
        )
      } else {
        title = String(
          format: GlassLocalizedText.copyingCount.resolve(locale: locale),
          locale: locale,
          Int64(progress.currentIndex), Int64(progress.totalCount)
        )
      }
      return Self(
        indicator: .progress,
        title: title,
        detail: GlassLocalizedText.originalFilesStay.resolve(locale: locale)
      )
    }
  }

  private static func rejectionTitle(
    _ reason: DropRejection,
    glassTitle: String,
    surface: GlassInteractionPresentationSurface,
    locale: Locale
  ) -> String {
    let key: GlassLocalizedText
    switch reason {
    case .unsupportedFolder:
      key = .dropUnsupportedFolder
    case .unsupportedPackage:
      key = .dropUnsupportedPackage
    case .unsupportedSymbolicLink:
      key = .dropUnsupportedLink
    case .unsupportedItem:
      key = surface == .workspace ? .dropUnsupportedItem : .dropUnsupportedItemDesktop
    case .tooManyItems:
      key = .dropTooMany
    case .collision:
      key = .dropCollision
    case .containsSameDirectoryItem:
      return String(
        format: GlassLocalizedText.dropAlreadyInGlass.resolve(locale: locale),
        locale: locale,
        glassTitle
      )
    case .destinationUnavailable:
      key = .unavailableTitle
    case .destinationReadOnly:
      key = .dropReadOnly
    case .destinationCopySafetyUnsupported:
      key = .dropUnsafeDestination
    case .networkDestinationUnsupported:
      key = surface == .workspace ? .dropNetworkWorkspace : .dropNetworkDesktop
    case .sourceUnavailable:
      key = .dropSourceUnavailable
    case .sourceCapacityReached:
      key = .dropCapacityBusy
    case .cloudPlaceholderUnavailable:
      key = .dropCloudPlaceholder
    }
    return key.resolve(locale: locale)
  }

  private static func rejectionDetail(
    _ reason: DropRejection,
    surface: GlassInteractionPresentationSurface,
    locale: Locale
  ) -> String? {
    let key: GlassLocalizedText?
    switch reason {
    case .tooManyItems(let maximum):
      return String(
        format: GlassLocalizedText.dropTooManyDetail.resolve(locale: locale),
        locale: locale,
        Int64(maximum)
      )
    case .sourceCapacityReached(let maximum):
      return String(
        format: GlassLocalizedText.dropCapacityDetail.resolve(locale: locale),
        locale: locale,
        Int64(maximum)
      )
    case .collision:
      key = .dropNoOverwrite
    case .unsupportedFolder:
      key = surface == .workspace ? .dropRegularOnlyWorkspace : .dropRegularOnlyDesktop
    case .unsupportedPackage, .unsupportedSymbolicLink, .unsupportedItem:
      key = surface == .workspace ? .dropItemUnchanged : nil
    case .containsSameDirectoryItem:
      key = surface == .workspace ? .dropNoCopyNeeded : nil
    case .destinationUnavailable:
      key = surface == .workspace ? .dropUnavailableDetail : nil
    case .destinationReadOnly:
      key = surface == .workspace ? .dropReadOnlyDetail : nil
    case .destinationCopySafetyUnsupported:
      key = .dropUnsafeDetail
    case .networkDestinationUnsupported:
      key = surface == .workspace ? .dropUseFinder : nil
    case .sourceUnavailable:
      key = surface == .workspace ? .dropSourceDetail : nil
    case .cloudPlaceholderUnavailable:
      key = .dropCloudDetail
    }
    return key?.resolve(locale: locale)
  }
}

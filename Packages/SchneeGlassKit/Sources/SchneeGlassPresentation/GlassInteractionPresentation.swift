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
    surface: GlassInteractionPresentationSurface
  ) -> Self {
    Self(
      indicator: .symbol("nosign"),
      title: rejectionTitle(
        reason,
        glassTitle: glassTitle,
        surface: surface
      ),
      detail: rejectionDetail(reason, surface: surface)
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
    surface: GlassInteractionPresentationSurface
  ) -> String {
    switch reason {
    case .unsupportedFolder:
      return "Folders aren't supported yet"
    case .unsupportedPackage:
      return "Packages aren't supported yet"
    case .unsupportedSymbolicLink:
      return "Symbolic links aren't supported"
    case .unsupportedItem:
      return surface == .workspace
        ? "This item can't be copied"
        : "This item can't be copied by SchneeGlass"
    case .tooManyItems:
      return "Too many files to copy at once"
    case .collision:
      return "A file with this name already exists"
    case .containsSameDirectoryItem:
      return "Already in \(glassTitle)"
    case .destinationUnavailable:
      return "Folder unavailable"
    case .destinationReadOnly:
      return "Folder is read-only"
    case .destinationCopySafetyUnsupported:
      return "Copy isn't supported for this folder"
    case .networkDestinationUnsupported:
      return surface == .workspace
        ? "Network folders aren't supported for copy yet"
        : "Network destinations aren't supported yet"
    case .sourceUnavailable:
      return "A source file is unavailable"
    case .sourceCapacityReached:
      return "Copy capacity is busy"
    case .cloudPlaceholderUnavailable:
      return "Download the cloud file first"
    }
  }

  private static func rejectionDetail(
    _ reason: DropRejection,
    surface: GlassInteractionPresentationSurface
  ) -> String? {
    switch reason {
    case .tooManyItems(let maximum):
      return
        "SchneeGlass copies up to \(maximum) files per drop. Split this selection into smaller drops."
    case .sourceCapacityReached(let maximum):
      return
        "SchneeGlass keeps up to \(maximum) source files ready across active drops. Finish another copy and try again."
    case .collision:
      return "Nothing will be overwritten."
    case .unsupportedFolder:
      return surface == .workspace
        ? "v0.1 accepts regular files only."
        : "v0.1 copies regular files only."
    case .unsupportedPackage, .unsupportedSymbolicLink, .unsupportedItem:
      return surface == .workspace ? "The dropped item was not changed." : nil
    case .containsSameDirectoryItem:
      return surface == .workspace ? "No copy is needed." : nil
    case .destinationUnavailable:
      return surface == .workspace
        ? "End this drop. If the Glass shows Folder unavailable, reconnect the original folder. Otherwise, refresh the files and try again."
        : nil
    case .destinationReadOnly:
      return surface == .workspace
        ? "SchneeGlass can't write to this folder."
        : nil
    case .destinationCopySafetyUnsupported:
      return "This filesystem doesn't provide the no-overwrite guarantees SchneeGlass requires."
    case .networkDestinationUnsupported:
      return surface == .workspace ? "Open the folder in Finder instead." : nil
    case .sourceUnavailable:
      return surface == .workspace
        ? "The source may have moved or become inaccessible."
        : nil
    case .cloudPlaceholderUnavailable:
      return "SchneeGlass won't start an unexpected cloud download."
    }
  }
}

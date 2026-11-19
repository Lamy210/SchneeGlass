import Foundation
import SchneeGlassApplication

/// Presentation-only notice state; resolving a locale does not grant operation authority.
enum WorkspaceNotification {
  case text(GlassLocalizedText)
  case openFailed(String)
  case copyFailure(CopyItemFailure.Reason, succeededCount: Int)

  func resolve(locale: Locale) -> String {
    switch self {
    case .text(let key):
      return key.resolve(locale: locale)
    case .openFailed(let name):
      let format = GlassLocalizedText.workspaceMessageOpenFailed.resolve(locale: locale)
      return String(format: format, locale: locale, name)
    case .copyFailure(let reason, let succeededCount):
      return Self.copyFailureText(reason, succeededCount: succeededCount, locale: locale)
    }
  }

  private static func copyFailureText(
    _ reason: CopyItemFailure.Reason, succeededCount: Int, locale: Locale
  ) -> String {
    let detail: GlassLocalizedText
    switch reason {
    case .sourceUnavailable:
      detail = .workspaceMessageCopyReasonSourceUnavailable
    case .unsupportedItem:
      detail = .workspaceMessageCopyReasonUnsupportedItem
    case .destinationUnavailable:
      detail = .workspaceMessageCopyReasonDestinationUnavailable
    case .permissionDenied:
      detail = .workspaceMessageCopyReasonPermissionDenied
    case .insufficientSpace:
      detail = .workspaceMessageCopyReasonInsufficientSpace
    case .collision:
      detail = .workspaceMessageCopyReasonCollision
    case .verificationFailed:
      detail = .workspaceMessageCopyReasonVerificationFailed
    case .commitStateUnknown:
      detail = .workspaceMessageCopyReasonCommitUnknown
    case .cancelled:
      detail = .workspaceMessageCopyReasonCancelled
    case .unexpected:
      detail = .workspaceMessageCopyReasonUnexpected
    }
    let message = detail.resolve(locale: locale)
    if succeededCount > 0 {
      let format = GlassLocalizedText.workspaceMessageCopyCompletedPrefix.resolve(locale: locale)
      let prefix = String(format: format, locale: locale, Int64(succeededCount))
      return prefix + " " + message
    }
    // Unknown commit state must never claim that no destination file was created.
    if reason == .commitStateUnknown {
      return message
    }
    let prefix = GlassLocalizedText.workspaceMessageCopyNothingPrefix.resolve(locale: locale)
    return prefix + " " + message
  }
}

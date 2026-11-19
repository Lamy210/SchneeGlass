import Foundation
import SchneeGlassApplication

/// Presentation-only mapping. Action eligibility remains in the application use case.
public enum CopyRecoveryStatePresentation {
  public static func description(
    for state: PendingCopyRecoveryCenterItemState,
    locale: Locale
  ) -> String {
    let key: GlassLocalizedText
    switch state {
    case .configurationMissing:
      key = .recoveryConfigurationMissing
    case .destinationUnavailable:
      key = .recoveryDestinationReconnect
    case .assessed(let disposition):
      switch disposition {
      case .metadataOnly:
        key = .recoveryMetadataOnly
      case .stagingPresent(let verification):
        if verification.resourceIdentity == .matchesRecordedIdentity {
          key = .recoveryOwnedStaging
        } else {
          key = .recoveryUnprovenStaging
        }
      case .finalPresent:
        key = .recoveryFinalPresent
      case .stagingAndFinalPresent(let staging, _):
        if staging.resourceIdentity == .matchesRecordedIdentity {
          key = .recoveryOwnedStagingAndFinal
        } else {
          key = .recoveryUnprovenStagingAndFinal
        }
      case .invalidRecord:
        key = .recoveryInvalidRecord
      case .destinationMismatch:
        key = .recoveryDestinationMismatch
      case .destinationUnavailable:
        key = .recoveryCannotInspect
      case .unexpectedFileType:
        key = .recoveryUnexpectedFileType
      }
    }
    return key.resolve(locale: locale)
  }
}

import Foundation
import SchneeGlassApplication
import Testing

@testable import SchneeGlassPresentation

@Test
func copyRecoveryStateLocalizationPreservesAllStateDistinctions() {
  let owned = PendingCopyFileVerification(
    size: .matchesExpectedSize, resourceIdentity: .matchesRecordedIdentity)
  let unproven = PendingCopyFileVerification(
    size: .matchesExpectedSize, resourceIdentity: .recordedIdentityUnavailable)
  let states: [PendingCopyRecoveryCenterItemState] = [
    .configurationMissing, .destinationUnavailable, .assessed(.metadataOnly),
    .assessed(.stagingPresent(owned)), .assessed(.stagingPresent(unproven)),
    .assessed(.finalPresent(owned)),
    .assessed(.stagingAndFinalPresent(staging: owned, final: owned)),
    .assessed(.stagingAndFinalPresent(staging: unproven, final: owned)),
    .assessed(.invalidRecord), .assessed(.destinationMismatch),
    .assessed(.destinationUnavailable), .assessed(.unexpectedFileType),
  ]
  let en = Locale(identifier: "en")
  let ja = Locale(identifier: "ja_JP")
  let fallback = Locale(identifier: "fr_FR")
  let english = states.map { CopyRecoveryStatePresentation.description(for: $0, locale: en) }
  let japanese = states.map { CopyRecoveryStatePresentation.description(for: $0, locale: ja) }
  #expect(Set(english).count == states.count)
  #expect(Set(japanese).count == states.count)
  for (index, state) in states.enumerated() {
    #expect(japanese[index] != english[index])
    #expect(
      CopyRecoveryStatePresentation.description(for: state, locale: fallback) == english[index])
  }
}

@Test
func copyRecoveryUnprovenOwnershipNeverPromisesDeletion() {
  let ja = Locale(identifier: "ja_JP")
  let en = Locale(identifier: "en")
  let identities: [PendingCopyResourceIdentityVerification] = [
    .mismatchesRecordedIdentity, .recordedIdentityUnavailable, .observedIdentityUnavailable,
  ]
  for identity in identities {
    let staging = PendingCopyFileVerification(
      size: .matchesExpectedSize, resourceIdentity: identity)
    let state = PendingCopyRecoveryCenterItemState.assessed(.stagingPresent(staging))
    #expect(
      CopyRecoveryStatePresentation.description(for: state, locale: ja).contains("削除しません"))
    #expect(
      CopyRecoveryStatePresentation.description(for: state, locale: en).contains("will not delete"))
    let both = PendingCopyRecoveryCenterItemState.assessed(
      .stagingAndFinalPresent(staging: staging, final: staging))
    #expect(
      CopyRecoveryStatePresentation.description(for: both, locale: ja).contains("いずれも削除しません"))
    #expect(
      CopyRecoveryStatePresentation.description(for: both, locale: en).contains("not delete either"))
  }
}

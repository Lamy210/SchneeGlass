import Foundation
import SchneeGlassApplication
import Testing

@testable import SchneeGlassPresentation

@Test
func transientContentFailuresKeepAutomaticRetryGuidance() {
  let enumeration = GlassContentFailurePresentation.make(for: .enumerationFailed)
  let metadata = GlassContentFailurePresentation.make(for: .metadataFailed)

  #expect(enumeration.status == "Refresh failed")
  #expect(enumeration.title == "Couldn't refresh this folder")
  #expect(enumeration.detail.contains("retry when the folder changes"))
  #expect(metadata == enumeration)
}

@Test
func unexpectedContentFailureUsesImplementedRecoveryPath() {
  let presentation = GlassContentFailurePresentation.make(for: .unexpected)

  #expect(presentation.status == "Needs attention")
  #expect(presentation.title == "This Glass couldn't continue")
  #expect(presentation.detail.contains("Restart SchneeGlass"))
  #expect(presentation.detail.contains("remove this Glass"))
  #expect(presentation.detail.contains("add the folder again"))
  #expect(!presentation.detail.contains("Recovery"))
  #expect(!presentation.detail.contains("reconnect"))
  #expect(!presentation.detail.contains("folder changes"))
}

@Test
func unavailableFolderGuidanceDoesNotPresentPendingCopyRecoveryAsSourceReconnect() {
  let presentation = GlassUnavailablePresentation.current

  #expect(presentation.title == "Folder unavailable")
  #expect(presentation.detail.contains("Reconnect the original folder"))
  #expect(presentation.detail.contains("without removing this Glass"))
  #expect(presentation.detail.contains("restart SchneeGlass"))
  #expect(
    presentation.detail.contains("Pending Copy Recovery in Settings is for interrupted copies"))
  #expect(!presentation.detail.contains("add the folder again"))
}
 
@Test
func inlineRefreshIsOfferedOnlyForAuthorizedTransientReadFailures() {
  #expect(
    GlassInlineRefreshPolicy.isVisible(for: .failed(.enumerationFailed), canRefresh: true))
  #expect(
    GlassInlineRefreshPolicy.isVisible(for: .failed(.metadataFailed), canRefresh: true))

  for error in [GlassContentError.enumerationFailed, .metadataFailed, .unexpected] {
    #expect(!GlassInlineRefreshPolicy.isVisible(for: .failed(error), canRefresh: false))
  }
  #expect(!GlassInlineRefreshPolicy.isVisible(for: .failed(.unexpected), canRefresh: true))
  #expect(!GlassInlineRefreshPolicy.isVisible(for: .loading, canRefresh: true))
  #expect(
    !GlassInlineRefreshPolicy.isVisible(for: .unavailable(.sourceMissing), canRefresh: true))
}

@Test
func inlineRefreshUsesExistingLocalizedNonDestructiveAction() {
  #expect(
    GlassLocalizedText.refreshFiles.resolve(locale: Locale(identifier: "en_US"))
      == "Refresh Files")
  #expect(
    GlassLocalizedText.refreshFiles.resolve(locale: Locale(identifier: "ja_JP"))
      == "ファイル一覧を更新")
  #expect(
    GlassLocalizedText.refreshFiles.resolve(locale: Locale(identifier: "fr_FR"))
      == "Refresh Files")
}

import Foundation
import SchneeGlassApplication
import Testing

@testable import SchneeGlassPresentation

@Test
func workspaceNotificationTextResolvesEveryStaticKeyInBothLanguages() {
  let en = Locale(identifier: "en")
  let ja = Locale(identifier: "ja_JP")
  let fallback = Locale(identifier: "fr_FR")
  let keys = GlassLocalizedText.allCases.filter {
    $0.rawValue.hasPrefix("workspaceMessage")
  }
  #expect(keys.count == 61)
  for key in keys {
    let notice = WorkspaceNotification.text(key)
    #expect(notice.resolve(locale: ja) != notice.resolve(locale: en))
    #expect(notice.resolve(locale: fallback) == notice.resolve(locale: en))
  }
}

@Test
func workspaceOpenFailurePreservesUntrustedDisplayName() {
  let name = "資料 %1$@.txt"
  let notice = WorkspaceNotification.openFailed(name)
  #expect(notice.resolve(locale: Locale(identifier: "en")) == "macOS couldn't open " + name + ".")
  #expect(notice.resolve(locale: Locale(identifier: "ja_JP")) == "macOSで" + name + "を開けませんでした。")
}

@Test
func workspaceUnknownCommitNoticeNeverClaimsNothingWasCopied() {
  let ja = Locale(identifier: "ja_JP")
  let en = Locale(identifier: "en")
  for count in [0, 1, 2] {
    let notice = WorkspaceNotification.copyFailure(.commitStateUnknown, succeededCount: count)
    let japanese = notice.resolve(locale: ja)
    let english = notice.resolve(locale: en)
    #expect(!japanese.contains("何もコピーされていません"))
    #expect(!english.contains("Nothing was copied"))
    #expect(japanese.contains("作成された可能性"))
    #expect(japanese.contains("再試行する前に復旧センター"))
    #expect(japanese.contains("元のファイルは移動・削除されていません"))
    if count > 0 {
      #expect(japanese.contains("\(count)件のファイル"))
      #expect(english.contains("\(count) file(s) were copied"))
    }
  }
}

@Test
func workspaceKnownCopyFailuresKeepCountAndReasonDistinct() {
  let ja = Locale(identifier: "ja_JP")
  let en = Locale(identifier: "en")
  let reasons: [CopyItemFailure.Reason] = [
    .sourceUnavailable, .unsupportedItem, .destinationUnavailable, .permissionDenied,
    .insufficientSpace, .collision, .verificationFailed, .cancelled, .unexpected,
  ]
  var translations = Set<String>()
  for reason in reasons {
    let empty = WorkspaceNotification.copyFailure(reason, succeededCount: 0)
    let partial = WorkspaceNotification.copyFailure(reason, succeededCount: 2)
    let japanese = empty.resolve(locale: ja)
    translations.insert(japanese)
    #expect(japanese.hasPrefix("何もコピーされていません。"))
    #expect(empty.resolve(locale: en).hasPrefix("Nothing was copied."))
    #expect(partial.resolve(locale: ja).hasPrefix("操作が停止するまでに2件"))
  }
  #expect(translations.count == reasons.count)
}

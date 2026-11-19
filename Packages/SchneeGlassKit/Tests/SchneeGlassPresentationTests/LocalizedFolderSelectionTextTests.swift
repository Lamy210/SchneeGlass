import Foundation
import Testing

@testable import SchneeGlassPresentation

@Test
func nativeFolderSelectionDistinguishesAddAndReconnectInBothLanguages() {
  let en = Locale(identifier: "en")
  let ja = Locale(identifier: "ja_JP")
  let fallback = Locale(identifier: "fr_FR")
  let add = SchneeGlassFolderSelectionText.add
  let reconnect = SchneeGlassFolderSelectionText.reconnect
  let recovery = SchneeGlassFolderSelectionText.recoveryDestination
  #expect(add.prompt(locale: en) == "Add Glass")
  #expect(add.prompt(locale: ja) == "Glassを追加")
  #expect(reconnect.prompt(locale: en) == "Reconnect")
  #expect(reconnect.prompt(locale: ja) == "再接続")
  #expect(recovery.prompt(locale: ja) == reconnect.prompt(locale: ja))
  #expect(recovery.prompt(locale: en) != add.prompt(locale: en))
  for text in [add, reconnect, recovery] {
    #expect(text.message(locale: ja) != text.message(locale: en))
    #expect(text.prompt(locale: fallback) == text.prompt(locale: en))
    #expect(text.message(locale: fallback) == text.message(locale: en))
  }
  #expect(reconnect.message(locale: ja).contains("元のフォルダ"))
  #expect(recovery.message(locale: ja).contains("元のコピー先フォルダ"))
  #expect(recovery.message(locale: en).contains("original copy destination"))
  #expect(reconnect.message(locale: en).contains("verify its persistent identity"))
  #expect(recovery.message(locale: en).contains("verify its persistent identity"))
  #expect(recovery.message(locale: ja).contains("永続的な同一性"))
}

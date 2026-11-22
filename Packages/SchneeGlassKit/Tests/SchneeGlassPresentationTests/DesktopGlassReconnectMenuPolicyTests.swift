import Foundation
import SchneeGlassApplication
import Testing

@testable import SchneeGlassPresentation

@Test
func desktopReconnectMenuAppearsOnlyForUnavailableSource() {
  #expect(DesktopGlassReconnectMenuPolicy.isVisible(for: .unavailable(.volumeUnavailable)))
  #expect(!DesktopGlassReconnectMenuPolicy.isVisible(for: .loading))
  #expect(!DesktopGlassReconnectMenuPolicy.isVisible(for: .failed(.enumerationFailed)))
}

@Test
func desktopReconnectMenuRespectsWorkspaceAuthority() {
  let unavailable = GlassContentState.unavailable(.volumeUnavailable)
  #expect(
    DesktopGlassReconnectMenuPolicy.isEnabled(
      for: unavailable,
      canReconnectSource: true
    )
  )
  #expect(
    !DesktopGlassReconnectMenuPolicy.isEnabled(
      for: unavailable,
      canReconnectSource: false
    )
  )
  #expect(
    !DesktopGlassReconnectMenuPolicy.isEnabled(
      for: .loading,
      canReconnectSource: true
    )
  )
}

@Test
func desktopReconnectMenuActionLabelIsLocalized() {
  #expect(
    GlassLocalizedText.reconnectOriginalFolder.resolve(locale: Locale(identifier: "ja_JP"))
      == "元のフォルダを再接続…"
  )
  #expect(
    GlassLocalizedText.reconnectOriginalFolder.resolve(locale: Locale(identifier: "en_US"))
      == "Reconnect Original Folder…"
  )
}

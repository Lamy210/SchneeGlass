import Foundation

/// The first localization slice. Callers supply a locale explicitly so tests and
/// rendered snapshots never depend on the machine's preferred language.
enum GlassLocalizedText: String, CaseIterable {
  case connected
  case empty
  case unavailable
  case refreshFailed
  case needsAttention
  case unavailableTitle
  case unavailableDetail
  case refreshFailedTitle
  case refreshFailedDetail
  case unexpectedTitle
  case unexpectedDetail
  case renameGlassMenu
  case refreshFiles
  case showConnectedFolder
  case removeGlassMenu
  case glassOptions
  case renameGlassTitle
  case glassName
  case cancelAction
  case renameAction
  case renameGlassDetail
  case removeGlassTitle
  case removeGlassAction
  case removeGlassDetail
  case reconnectOriginalFolder

  func resolve(locale: Locale) -> String {
    let language = locale.language.languageCode?.identifier == "ja" ? "ja" : "en"
    return localizedValue(language: language)
      ?? localizedValue(language: "en")
      ?? rawValue
  }

  /// No implicit use of the host application's bundle or preferred language.
  func localizedValue(language: String) -> String? {
    guard let url = Bundle.module.url(forResource: language, withExtension: "lproj"),
      let bundle = Bundle(url: url)
    else {
      return nil
    }
    let missing = "__schneeglass_missing_translation__"
    let value = bundle.localizedString(forKey: rawValue, value: missing, table: "GlassStatus")
    return value == missing ? nil : value
  }
}

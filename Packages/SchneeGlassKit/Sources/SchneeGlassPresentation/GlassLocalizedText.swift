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
  case findGlass
  case findGlassByName
  case glassStatus
  case allStates
  case loading
  case failed
  case clearSearch
  case doneSearch
  case noMatchingGlasses
  case noMatchingGlassesDetail
  case workspaceSearchCount
  case hideFileFilter
  case filterFiles
  case showAsList
  case showAsIcons
  case filterFilesByName
  case closeFileFilter
  case fileType
  case allTypes
  case files
  case folders
  case packages
  case linksAndAliases
  case otherFileTypes
  case desktopFilterMatchCount
  case desktopFilterTruncatedMatchCount
  case desktopTruncatedLoadedCount
  case checkingFiles
  case copyingToGlass
  case copyProgressWithFilename
  case copyingFilename
  case copyingCount
  case originalFilesStay
  case cancelCopy
  case copyingStatus
  case dropUnsupportedFolder
  case dropUnsupportedPackage
  case dropUnsupportedLink
  case dropUnsupportedItem
  case dropUnsupportedItemDesktop
  case dropTooMany
  case dropCollision
  case dropAlreadyInGlass
  case dropReadOnly
  case dropUnsafeDestination
  case dropNetworkWorkspace
  case dropNetworkDesktop
  case dropSourceUnavailable
  case dropCapacityBusy
  case dropCloudPlaceholder
  case dropTooManyDetail
  case dropCapacityDetail
  case dropNoOverwrite
  case dropRegularOnlyWorkspace
  case dropRegularOnlyDesktop
  case dropItemUnchanged
  case dropNoCopyNeeded
  case dropUnavailableDetail
  case dropReadOnlyDetail
  case dropUnsafeDetail
  case dropUseFinder
  case dropSourceDetail
  case dropCloudDetail
  case dropCopyToGlass
  case dropCopyFilename
  case dropCopyCount
  case workspaceTagline
  case restoringStatus
  case addGlass
  case restoringGlasses
  case configurationRecoveryTitle
  case configurationRecoveryDetail
  case firstGlassTitle
  case firstGlassDetail
  case dismissMessage

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

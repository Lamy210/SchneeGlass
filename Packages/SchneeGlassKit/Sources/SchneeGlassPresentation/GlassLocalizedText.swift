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
  case settingsRecovery
  case settingsRecoveryUnavailable
  case settingsFilesUnchanged
  case settingsGlobalShortcut
  case settingsShowHideAll
  case settingsShortcutDetail
  case settingsConfigurationRecovery
  case settingsConfigurationRecoveryDetail
  case settingsLoadingBackups
  case settingsNoBackups
  case settingsBackup
  case settingsRestore
  case settingsRefreshBackups
  case settingsRestoring
  case settingsBackupReadFailed
  case settingsConfigurationBusy
  case settingsConfigurationRestored
  case settingsRestoredNeedsRestart
  case settingsWaitForCopy
  case settingsRestoreFailed
  case settingsConfirmRestoreTitle
  case settingsConfirmRestoreDetail
  case settingsConfirmRestoreAction

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

/// Narrow app-host bridge for configuration recovery and shortcut settings.
public enum SchneeGlassSettingsText: CaseIterable, Equatable {
  case recovery
  case recoveryUnavailable
  case filesUnchanged
  case globalShortcut
  case showHideAll
  case shortcutDetail
  case configurationRecovery
  case configurationRecoveryDetail
  case loadingBackups
  case noBackups
  case backup
  case restore
  case refreshBackups
  case restoring
  case backupReadFailed
  case configurationBusy
  case configurationRestored
  case restoredNeedsRestart
  case waitForCopy
  case restoreFailed
  case confirmRestoreTitle
  case confirmRestoreDetail
  case confirmRestoreAction
  case cancel

  public func resolve(locale: Locale) -> String {
    let key: GlassLocalizedText
    switch self {
    case .recovery:
      key = .settingsRecovery
    case .recoveryUnavailable:
      key = .settingsRecoveryUnavailable
    case .filesUnchanged:
      key = .settingsFilesUnchanged
    case .globalShortcut:
      key = .settingsGlobalShortcut
    case .showHideAll:
      key = .settingsShowHideAll
    case .shortcutDetail:
      key = .settingsShortcutDetail
    case .configurationRecovery:
      key = .settingsConfigurationRecovery
    case .configurationRecoveryDetail:
      key = .settingsConfigurationRecoveryDetail
    case .loadingBackups:
      key = .settingsLoadingBackups
    case .noBackups:
      key = .settingsNoBackups
    case .backup:
      key = .settingsBackup
    case .restore:
      key = .settingsRestore
    case .refreshBackups:
      key = .settingsRefreshBackups
    case .restoring:
      key = .settingsRestoring
    case .backupReadFailed:
      key = .settingsBackupReadFailed
    case .configurationBusy:
      key = .settingsConfigurationBusy
    case .configurationRestored:
      key = .settingsConfigurationRestored
    case .restoredNeedsRestart:
      key = .settingsRestoredNeedsRestart
    case .waitForCopy:
      key = .settingsWaitForCopy
    case .restoreFailed:
      key = .settingsRestoreFailed
    case .confirmRestoreTitle:
      key = .settingsConfirmRestoreTitle
    case .confirmRestoreDetail:
      key = .settingsConfirmRestoreDetail
    case .confirmRestoreAction:
      key = .settingsConfirmRestoreAction
    case .cancel:
      key = .cancelAction
    }
    return key.resolve(locale: locale)
  }

  public static func restoreConfirmation(date: String, locale: Locale) -> String {
    String(
      format: GlassLocalizedText.settingsConfirmRestoreDetail.resolve(locale: locale),
      locale: locale,
      date
    )
  }
}

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
  case settingsShortcutRecorder
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
  case recoveryPendingRecovery
  case recoveryPendingRecoveryDetail
  case recoveryInspectingPending
  case recoveryNoPending
  case recoveryUnknownGlass
  case recoveryInspectFinder
  case recoveryShowIncomplete
  case recoveryShowFinal
  case recoveryDiscardMetadataMenu
  case recoveryRemoveIncompleteMenu
  case recoveryReconnectDestination
  case recoveryRefreshPending
  case recoverySafety
  case recoverySafetyDetail
  case recoveryDiscardMetadataTitle
  case recoveryDiscardMetadataDetail
  case recoveryDiscardMetadataAction
  case recoveryRemoveIncompleteTitle
  case recoveryRemoveIncompleteDetail
  case recoveryRemoveIncompleteAction
  case recoveryConfigurationMissing
  case recoveryDestinationReconnect
  case recoveryMetadataOnly
  case recoveryOwnedStaging
  case recoveryUnprovenStaging
  case recoveryFinalPresent
  case recoveryOwnedStagingAndFinal
  case recoveryUnprovenStagingAndFinal
  case recoveryInvalidRecord
  case recoveryDestinationMismatch
  case recoveryCannotInspect
  case recoveryUnexpectedFileType
  case recoveryMessageConfigurationBusy
  case recoveryMessageInspectFailed
  case recoveryMessageWaitForMutation
  case recoveryMessageNotMutation
  case recoveryMessageActionFailed
  case recoveryMessageWaitForReveal
  case recoveryMessageBusyReveal
  case recoveryMessageNotReveal
  case recoveryMessageRevealedStaging
  case recoveryMessageRevealedFinal
  case recoveryMessageRevealFailed
  case recoveryMessageWaitForReconnect
  case recoveryMessageBusyReconnect
  case recoveryMessageReconnected
  case recoveryMessageReconnectReloadFailed
  case recoveryMessageReconnectFailed
  case recoveryMessageMutationCompleted
  case recoveryMessageMutationReloadFailed
  case recoveryMessageUnsupportedReveal
  case recoveryMessageRevealRecordLoadFailed
  case recoveryMessageRevealConfigLoadFailed
  case recoveryMessageRecordMissing
  case recoveryMessageRevealGlassMissing
  case recoveryMessageRevealDestinationUnavailable
  case recoveryMessageRevealStaleState
  case recoveryMessageCopyInProgress
  case recoveryMessageRecoveryInProgress
  case recoveryMessageRecordsLoadFailed
  case recoveryMessageConfigurationLoadFailed
  case recoveryMessageConfigurationMissing
  case recoveryMessageDestinationUnavailable
  case recoveryMessageMutationFailed
  case recoveryMessageReconnectRecordsLoadFailed
  case recoveryMessageReconnectConfigLoadFailed
  case recoveryMessageReconnectGlassMissing
  case recoveryMessageSourceCreationFailed
  case recoveryMessageIdentityUnavailable
  case recoveryMessageIdentityMismatch
  case recoveryMessageSelectedAccessFailed
  case recoveryMessageStaleRecoveryState
  case recoveryMessageCopyStarted
  case recoveryMessageInvalidConfiguration
  case recoveryMessageConfigurationSaveFailed
  case menuGlasses
  case menuAddGlass
  case menuShowAll
  case menuHideAll
  case menuShowGlass
  case menuHideGlass
  case menuResetPositions
  case menuSettings
  case menuQuit
  case menuStartupFailed
  case menuStartupFailedDetail
  case menuResetTitle
  case menuResetDetail
  case menuResetAction
  case menuResetBusy
  case menuResetNoDisplay
  case menuResetFailed
  case menuResetFailureTitle
  case panelUnlockPosition
  case panelLockPosition
  case panelStopKeepOnTop
  case panelKeepOnTop
  case panelStopAllSpaces
  case panelShowAllSpaces
  case panelOpacity
  case panelCompactTiles
  case panelDisableCompactTiles
  case panelEnableCompactTiles
  case panelSortName
  case panelSortModified
  case panelSortSize
  case panelSortFiles
  case panelFoldersFirst
  case panelDisableFoldersFirst
  case panelEnableFoldersFirst
  case panelTopLeft
  case panelTopRight
  case panelBottomLeft
  case panelBottomRight
  case panelCenter
  case panelSnapGlass
  case panelWindowOptions
  case panelReconnectFolder
  case tileOpen
  case tileReveal
  case tileOpenHint
  case tileFolder
  case tilePackage
  case tileAlias
  case tileSymbolicLink
  case tileSize
  case tileModified
  case workspaceMessageBackupReloadFailed
  case workspaceMessageBackupRestoreFailed
  case workspaceMessageRemoveFailed
  case workspaceMessagePlacementFailed
  case workspaceMessageResetStale
  case workspaceMessageResetFailed
  case workspaceMessageCopyCleanupPending
  case workspaceMessageCopyDestinationGone
  case workspaceMessageCopyBusy
  case workspaceMessageCopyUnauthorized
  case workspaceMessageCopyFailed
  case workspaceMessageRenameStale
  case workspaceMessageRenameEmpty
  case workspaceMessageRenameTooLong
  case workspaceMessageRenameInvalid
  case workspaceMessageRenameSaveFailed
  case workspaceMessageRenameFailed
  case workspaceMessageSpacesStale
  case workspaceMessageSpacesInvalid
  case workspaceMessageSpacesSaveFailed
  case workspaceMessageSpacesFailed
  case workspaceMessageReconnectActivationFailed
  case workspaceMessageReconnectFailed
  case workspaceMessageInactiveConnection
  case workspaceMessageRestorePermissionsPending
  case workspaceMessageRestorePartial
  case workspaceMessageReconnectMissing
  case workspaceMessageReconnectAccessSaveFailed
  case workspaceMessageReconnectIdentityUnknown
  case workspaceMessageReconnectWrongFolder
  case workspaceMessageReconnectOpenFailed
  case workspaceMessageReconnectDenied
  case workspaceMessageReconnectReplaced
  case workspaceMessageReconnectWatchFailed
  case workspaceMessageReconnectReadFailed
  case workspaceMessageReconnectInvalid
  case workspaceMessageReconnectStale
  case workspaceMessageReconnectSaveFailed
  case workspaceMessageRecoveryRequired
  case workspaceMessageAddFailed
  case workspaceMessageAddAccessSaveFailed
  case workspaceMessageAddIdentityUnknown
  case workspaceMessageAddPlacementFailed
  case workspaceMessageAddInvalid
  case workspaceMessageAddAccessFailed
  case workspaceMessageAddWatchFailed
  case workspaceMessageAddReadFailed
  case workspaceMessageAddSaveFailed
  case workspaceMessageOpenFailed
  case workspaceMessageCopyCompletedPrefix
  case workspaceMessageCopyNothingPrefix
  case workspaceMessageCopyReasonSourceUnavailable
  case workspaceMessageCopyReasonUnsupportedItem
  case workspaceMessageCopyReasonDestinationUnavailable
  case workspaceMessageCopyReasonPermissionDenied
  case workspaceMessageCopyReasonInsufficientSpace
  case workspaceMessageCopyReasonCollision
  case workspaceMessageCopyReasonVerificationFailed
  case workspaceMessageCopyReasonCommitUnknown
  case workspaceMessageCopyReasonCancelled
  case workspaceMessageCopyReasonUnexpected
  case loadingFolder
  case workspaceFirst500Items
  case menuDuplicateTitle
  case folderSelectionAdd
  case folderSelectionAddDetail
  case folderSelectionReconnect
  case folderSelectionReconnectDetail
  case folderSelectionRecoveryDetail

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
  case shortcutRecorder
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
    case .shortcutRecorder:
      key = .settingsShortcutRecorder
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

/// App-host copy recovery labels; confirmation text takes filenames as data.
public enum SchneeGlassCopyRecoveryText: CaseIterable {
  case pendingRecovery
  case pendingRecoveryDetail
  case inspectingPending
  case noPending
  case unknownGlass
  case inspectFinder
  case showIncomplete
  case showFinal
  case discardMetadataMenu
  case removeIncompleteMenu
  case reconnectDestination
  case refreshPending
  case safety
  case safetyDetail
  case discardMetadataTitle
  case discardMetadataAction
  case removeIncompleteTitle
  case removeIncompleteAction

  public func resolve(locale: Locale) -> String {
    let key: GlassLocalizedText
    switch self {
    case .pendingRecovery:
      key = .recoveryPendingRecovery
    case .pendingRecoveryDetail:
      key = .recoveryPendingRecoveryDetail
    case .inspectingPending:
      key = .recoveryInspectingPending
    case .noPending:
      key = .recoveryNoPending
    case .unknownGlass:
      key = .recoveryUnknownGlass
    case .inspectFinder:
      key = .recoveryInspectFinder
    case .showIncomplete:
      key = .recoveryShowIncomplete
    case .showFinal:
      key = .recoveryShowFinal
    case .discardMetadataMenu:
      key = .recoveryDiscardMetadataMenu
    case .removeIncompleteMenu:
      key = .recoveryRemoveIncompleteMenu
    case .reconnectDestination:
      key = .recoveryReconnectDestination
    case .refreshPending:
      key = .recoveryRefreshPending
    case .safety:
      key = .recoverySafety
    case .safetyDetail:
      key = .recoverySafetyDetail
    case .discardMetadataTitle:
      key = .recoveryDiscardMetadataTitle
    case .discardMetadataAction:
      key = .recoveryDiscardMetadataAction
    case .removeIncompleteTitle:
      key = .recoveryRemoveIncompleteTitle
    case .removeIncompleteAction:
      key = .recoveryRemoveIncompleteAction
    }
    return key.resolve(locale: locale)
  }

  public static func discardConfirmation(filename: String, locale: Locale) -> String {
    String(
      format: GlassLocalizedText.recoveryDiscardMetadataDetail.resolve(locale: locale),
      locale: locale,
      filename
    )
  }

  public static func removeConfirmation(filename: String, locale: Locale) -> String {
    String(
      format: GlassLocalizedText.recoveryRemoveIncompleteDetail.resolve(locale: locale),
      locale: locale,
      filename
    )
  }
}

/// App-host commands and position-reset notifications.
public enum SchneeGlassMenuText: CaseIterable {
  case glasses
  case addGlass
  case showAll
  case hideAll
  case showGlass
  case hideGlass
  case resetPositions
  case settings
  case quit
  case startupFailed
  case startupFailedDetail
  case resetTitle
  case resetDetail
  case resetAction
  case resetBusy
  case resetNoDisplay
  case resetFailed
  case resetFailureTitle
  case addGlassCommand
  case cancel

  public func resolve(locale: Locale) -> String {
    let key: GlassLocalizedText
    switch self {
    case .glasses:
      key = .menuGlasses
    case .addGlass:
      key = .menuAddGlass
    case .showAll:
      key = .menuShowAll
    case .hideAll:
      key = .menuHideAll
    case .showGlass:
      key = .menuShowGlass
    case .hideGlass:
      key = .menuHideGlass
    case .resetPositions:
      key = .menuResetPositions
    case .settings:
      key = .menuSettings
    case .quit:
      key = .menuQuit
    case .startupFailed:
      key = .menuStartupFailed
    case .startupFailedDetail:
      key = .menuStartupFailedDetail
    case .resetTitle:
      key = .menuResetTitle
    case .resetDetail:
      key = .menuResetDetail
    case .resetAction:
      key = .menuResetAction
    case .resetBusy:
      key = .menuResetBusy
    case .resetNoDisplay:
      key = .menuResetNoDisplay
    case .resetFailed:
      key = .menuResetFailed
    case .resetFailureTitle:
      key = .menuResetFailureTitle
    case .addGlassCommand:
      key = .addGlass
    case .cancel:
      key = .cancelAction
    }
    return key.resolve(locale: locale)
  }
}

/// Desktop panel window controls and rename confirmation.
public enum SchneeGlassPanelText: CaseIterable {
  case unlockPosition
  case lockPosition
  case stopKeepOnTop
  case keepOnTop
  case stopAllSpaces
  case showAllSpaces
  case compactTiles
  case disableCompactTiles
  case enableCompactTiles
  case sortName
  case sortModified
  case sortSize
  case sortFiles
  case foldersFirst
  case disableFoldersFirst
  case enableFoldersFirst
  case topLeft
  case topRight
  case bottomLeft
  case bottomRight
  case center
  case snapGlass
  case windowOptions
  case reconnectFolder
  case renameMenu
  case revealFolder
  case renameTitle
  case renameDetail
  case renameAction
  case cancel
  case glassName

  public func resolve(locale: Locale) -> String {
    let key: GlassLocalizedText
    switch self {
    case .unlockPosition:
      key = .panelUnlockPosition
    case .lockPosition:
      key = .panelLockPosition
    case .stopKeepOnTop:
      key = .panelStopKeepOnTop
    case .keepOnTop:
      key = .panelKeepOnTop
    case .stopAllSpaces:
      key = .panelStopAllSpaces
    case .showAllSpaces:
      key = .panelShowAllSpaces
    case .compactTiles:
      key = .panelCompactTiles
    case .disableCompactTiles:
      key = .panelDisableCompactTiles
    case .enableCompactTiles:
      key = .panelEnableCompactTiles
    case .sortName:
      key = .panelSortName
    case .sortModified:
      key = .panelSortModified
    case .sortSize:
      key = .panelSortSize
    case .sortFiles:
      key = .panelSortFiles
    case .foldersFirst:
      key = .panelFoldersFirst
    case .disableFoldersFirst:
      key = .panelDisableFoldersFirst
    case .enableFoldersFirst:
      key = .panelEnableFoldersFirst
    case .topLeft:
      key = .panelTopLeft
    case .topRight:
      key = .panelTopRight
    case .bottomLeft:
      key = .panelBottomLeft
    case .bottomRight:
      key = .panelBottomRight
    case .center:
      key = .panelCenter
    case .snapGlass:
      key = .panelSnapGlass
    case .windowOptions:
      key = .panelWindowOptions
    case .reconnectFolder:
      key = .panelReconnectFolder
    case .renameMenu:
      key = .renameGlassMenu
    case .revealFolder:
      key = .showConnectedFolder
    case .renameTitle:
      key = .renameGlassTitle
    case .renameDetail:
      key = .renameGlassDetail
    case .renameAction:
      key = .renameAction
    case .cancel:
      key = .cancelAction
    case .glassName:
      key = .glassName
    }
    return key.resolve(locale: locale)
  }

  public static func opacity(percentage: String, locale: Locale) -> String {
    String(
      format: GlassLocalizedText.panelOpacity.resolve(locale: locale),
      locale: locale,
      percentage
    )
  }
}

/// Narrow bridge for native folder panels. Adapters receive resolved strings from the app host.
public enum SchneeGlassFolderSelectionText {
  case add
  case reconnect
  case recoveryDestination

  public func prompt(locale: Locale) -> String {
    switch self {
    case .add:
      return GlassLocalizedText.folderSelectionAdd.resolve(locale: locale)
    case .reconnect, .recoveryDestination:
      return GlassLocalizedText.folderSelectionReconnect.resolve(locale: locale)
    }
  }

  public func message(locale: Locale) -> String {
    switch self {
    case .add:
      return GlassLocalizedText.folderSelectionAddDetail.resolve(locale: locale)
    case .reconnect:
      return GlassLocalizedText.folderSelectionReconnectDetail.resolve(locale: locale)
    case .recoveryDestination:
      return GlassLocalizedText.folderSelectionRecoveryDetail.resolve(locale: locale)
    }
  }
}

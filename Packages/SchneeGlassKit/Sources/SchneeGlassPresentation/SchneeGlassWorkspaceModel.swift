import FileDomain
import Foundation
import Observation
import SchneeGlassApplication
import SchneeGlassDomain

public struct GlassWorkspaceEntry: Identifiable, Hashable, Sendable {
  public let id: GlassID
  public var title: String
  public var contentState: GlassContentState
  public var interactionState: InteractionState
  public var placement: GlassPlacement?
  public var showOnAllSpaces: Bool

  public init(
    id: GlassID,
    title: String,
    contentState: GlassContentState,
    interactionState: InteractionState = .idle,
    placement: GlassPlacement? = nil,
    showOnAllSpaces: Bool = false
  ) {
    self.id = id
    self.title = title
    self.contentState = contentState
    self.interactionState = interactionState
    self.placement = placement
    self.showOnAllSpaces = showOnAllSpaces
  }
}

public enum GlassPlacementPersistenceResult: Hashable, Sendable {
  case updated
  case busy
  case missing
  case failed
}

public enum GlassPositionResetResult: Hashable, Sendable {
  case updated
  case noGlasses
  case busy
  case failed
}

public enum ConfigurationBackupListingResult: Hashable, Sendable {
  case loaded([ConfigurationBackupDescriptor])
  case failed
}

public enum ConfigurationBackupRestoreResult: Hashable, Sendable {
  case restored
  case restoredNeedsRestart
  case busy
  case copyInProgress
  case failed
}

enum WorkspaceConfigurationMutationPolicy {
  static func allowsMutation(
    isMutatingConfiguration: Bool,
    requiresConfigurationRecovery: Bool
  ) -> Bool {
    !isMutatingConfiguration && !requiresConfigurationRecovery
  }
}

enum WorkspaceConfigurationAuthorityPolicy {
  static func hasAuthoritativeSnapshot(
    hasLoadedConfigurationSnapshot: Bool,
    isMutatingConfiguration: Bool,
    requiresConfigurationRecovery: Bool
  ) -> Bool {
    hasLoadedConfigurationSnapshot
      && WorkspaceConfigurationMutationPolicy.allowsMutation(
        isMutatingConfiguration: isMutatingConfiguration,
        requiresConfigurationRecovery: requiresConfigurationRecovery
      )
  }
}

enum WorkspaceConfigurationBackupRestorePolicy {
  static func allowsRestore(
    hasLoadedConfigurationSnapshot: Bool,
    isMutatingConfiguration: Bool,
    requiresConfigurationRecovery: Bool
  ) -> Bool {
    !isMutatingConfiguration
      && (hasLoadedConfigurationSnapshot || requiresConfigurationRecovery)
  }
}

@MainActor
@Observable
public final class SchneeGlassWorkspaceModel {
  public private(set) var glasses: [GlassWorkspaceEntry] = []
  public private(set) var isCreatingGlass = false
  public private(set) var isRestoring = false
  public private(set) var isMutatingConfiguration = false
  public private(set) var requiresConfigurationRecovery = false
  private var notification: WorkspaceNotification?

  public var userMessage: String? {
    localizedUserMessage(locale: Locale(identifier: "en"))
  }

  public func localizedUserMessage(locale: Locale) -> String? {
    notification?.resolve(locale: locale)
  }

  public var canMutateConfiguration: Bool {
    !isShuttingDown && hasAuthoritativeConfigurationSnapshot
  }

  public var canAddGlass: Bool {
    canMutateConfiguration
  }

  public var hasAuthoritativeConfigurationSnapshot: Bool {
    WorkspaceConfigurationAuthorityPolicy.hasAuthoritativeSnapshot(
      hasLoadedConfigurationSnapshot: hasLoadedConfigurationSnapshot,
      isMutatingConfiguration: isMutatingConfiguration,
      requiresConfigurationRecovery: requiresConfigurationRecovery
    )
  }

  private let createGlassUseCase: CreateGlassUseCase
  private let restoreApplicationUseCase: RestoreApplicationUseCase
  private let reconnectGlassSourceUseCase: ReconnectGlassSourceUseCase
  private let removeGlassUseCase: RemoveGlassUseCase
  private let updateGlassPlacementUseCase: UpdateGlassPlacementUseCase
  private let resetGlassPositionsUseCase: ResetGlassPositionsUseCase
  private let updateGlassTitleUseCase: UpdateGlassTitleUseCase
  private let updateGlassSpacesBehaviorUseCase: UpdateGlassSpacesBehaviorUseCase
  private let configurationRecoveryUseCase: ConfigurationRecoveryUseCase
  private let fileActionUseCase: WorkspaceFileActionUseCase
  private let folderActionUseCase: WorkspaceFolderActionUseCase
  private let runtimeSessionFactory: GlassRuntimeSessionFactory
  private var sessions: [GlassID: GlassRuntimeSession] = [:]
  private var manuallyRefreshingGlassIDs: Set<GlassID> = []
  private var connectedFolderURLs: [GlassID: URL] = [:]
  private var stateTasks: [GlassID: Task<Void, Never>] = [:]
  private var sessionTaskTracker = WorkspaceSessionTaskTracker()
  private var dropExecutionGate = WorkspaceDropExecutionGate()
  private var dropPlanningTracker = WorkspaceDropPlanningTracker()
  private var didAttemptInitialRestore = false
  private var hasLoadedConfigurationSnapshot = false
  private let initialRestoreTaskCoordinator = WorkspaceInitialRestoreTaskCoordinator()
  private let configurationMutationTaskCoordinator = WorkspaceConfigurationMutationTaskCoordinator()
  private var isShuttingDown = false

  public init(
    createGlassUseCase: CreateGlassUseCase,
    restoreApplicationUseCase: RestoreApplicationUseCase,
    reconnectGlassSourceUseCase: ReconnectGlassSourceUseCase,
    removeGlassUseCase: RemoveGlassUseCase,
    updateGlassPlacementUseCase: UpdateGlassPlacementUseCase,
    resetGlassPositionsUseCase: ResetGlassPositionsUseCase,
    updateGlassTitleUseCase: UpdateGlassTitleUseCase,
    updateGlassSpacesBehaviorUseCase: UpdateGlassSpacesBehaviorUseCase,
    configurationRecoveryUseCase: ConfigurationRecoveryUseCase,
    fileActionUseCase: WorkspaceFileActionUseCase,
    folderActionUseCase: WorkspaceFolderActionUseCase,
    runtimeSessionFactory: GlassRuntimeSessionFactory
  ) {
    self.createGlassUseCase = createGlassUseCase
    self.restoreApplicationUseCase = restoreApplicationUseCase
    self.reconnectGlassSourceUseCase = reconnectGlassSourceUseCase
    self.removeGlassUseCase = removeGlassUseCase
    self.updateGlassPlacementUseCase = updateGlassPlacementUseCase
    self.resetGlassPositionsUseCase = resetGlassPositionsUseCase
    self.updateGlassTitleUseCase = updateGlassTitleUseCase
    self.updateGlassSpacesBehaviorUseCase = updateGlassSpacesBehaviorUseCase
    self.configurationRecoveryUseCase = configurationRecoveryUseCase
    self.fileActionUseCase = fileActionUseCase
    self.folderActionUseCase = folderActionUseCase
    self.runtimeSessionFactory = runtimeSessionFactory
  }

  public func restoreIfNeeded() async {
    guard !isShuttingDown,
      !didAttemptInitialRestore,
      !isMutatingConfiguration
    else {
      return
    }

    didAttemptInitialRestore = true
    isMutatingConfiguration = true
    isRestoring = true
    notification = nil
    defer {
      isRestoring = false
      isMutatingConfiguration = false
    }

    await initialRestoreTaskCoordinator.run { [weak self] in
      guard let self else {
        return
      }

      do {
        let result = try await restoreApplicationUseCase.execute()
        requiresConfigurationRecovery = false
        await applyRestoreResult(result)
        hasLoadedConfigurationSnapshot = true
      } catch is CancellationError {
        didAttemptInitialRestore = false
      } catch {
        enterConfigurationRecoveryRequiredState()
      }
    }
  }

  public func loadConfigurationBackups() async -> ConfigurationBackupListingResult {
    do {
      return .loaded(try await configurationRecoveryUseCase.availableBackups())
    } catch {
      return .failed
    }
  }

  public func restoreConfigurationBackup(
    id: String
  ) async -> ConfigurationBackupRestoreResult {
    guard !isShuttingDown else {
      return .busy
    }
    guard
      WorkspaceConfigurationBackupRestorePolicy.allowsRestore(
        hasLoadedConfigurationSnapshot: hasLoadedConfigurationSnapshot,
        isMutatingConfiguration: isMutatingConfiguration,
        requiresConfigurationRecovery: requiresConfigurationRecovery
      )
    else {
      return .busy
    }
    guard !hasActiveCopy else {
      return .copyInProgress
    }

    isMutatingConfiguration = true
    isRestoring = true
    notification = nil
    defer {
      isRestoring = false
      isMutatingConfiguration = false
    }

    return await configurationMutationTaskCoordinator.run(ifBusy: .busy) { [weak self] in
      guard let self else {
        return .busy
      }

      var backupWasRestored = false
      do {
        _ = try await configurationRecoveryUseCase.restoreBackup(id: id)
        backupWasRestored = true

        await deactivateAllSessions()
        glasses.removeAll(keepingCapacity: false)

        let result = try await restoreApplicationUseCase.execute()
        requiresConfigurationRecovery = false
        await applyRestoreResult(result)
        hasLoadedConfigurationSnapshot = true
        return .restored
      } catch is CancellationError {
        if backupWasRestored {
          requiresConfigurationRecovery = true
          notification = .text(.workspaceMessageBackupReloadFailed)
          return .restoredNeedsRestart
        }

        return .busy
      } catch {
        if backupWasRestored {
          requiresConfigurationRecovery = true
          notification = .text(.workspaceMessageBackupReloadFailed)
          return .restoredNeedsRestart
        }

        notification = .text(.workspaceMessageBackupRestoreFailed)
        return .failed
      }
    }
  }

  public func addGlass() async {
    guard canAddGlass else {
      presentConfigurationRecoveryRequirementIfNeeded()
      return
    }

    isMutatingConfiguration = true
    isCreatingGlass = true
    notification = nil
    defer {
      isCreatingGlass = false
      isMutatingConfiguration = false
    }

    await configurationMutationTaskCoordinator.run(ifBusy: ()) { [weak self] in
      guard let self else {
        return
      }

      do {
        guard let seed = try await createGlassUseCase.execute() else {
          return
        }
        try await activate(seed)
      } catch is CancellationError {
        return
      } catch {
        if let createError = error as? CreateGlassError,
          case .configurationLoadFailed = createError
        {
          enterConfigurationRecoveryRequiredState()
        } else {
          notification = Self.userFacingMessage(for: error)
        }
      }
    }
  }

  public func removeGlass(id: GlassID) async {
    guard canMutateConfiguration,
      !isDropBusy(glassID: id)
    else {
      presentConfigurationRecoveryRequirementIfNeeded()
      return
    }

    isMutatingConfiguration = true
    defer { isMutatingConfiguration = false }

    await configurationMutationTaskCoordinator.run(ifBusy: ()) { [weak self] in
      guard let self else {
        return
      }

      do {
        let removed = try await removeGlassUseCase.execute(glassID: id)
        guard removed else {
          return
        }

        sessionTaskTracker.invalidate(id)
        stateTasks[id]?.cancel()
        stateTasks[id] = nil

        if let session = sessions[id] {
          // Keep the session discoverable until stop completes. If app termination starts while
          // this await is in flight, shutdown() can still find the same session and join its
          // idempotent concurrent stop instead of approving termination before
          // access/subscription cleanup.
          await session.stop()
          sessions[id] = nil
        }
        connectedFolderURLs[id] = nil

        glasses.removeAll { $0.id == id }
        notification = nil
      } catch is CancellationError {
        return
      } catch let error as RemoveGlassError {
        if case .configurationLoadFailed = error {
          enterConfigurationRecoveryRequiredState()
        } else {
          notification = .text(.workspaceMessageRemoveFailed)
        }
      } catch {
        notification = .text(.workspaceMessageRemoveFailed)
      }
    }
  }

  public func persistPlacement(
    glassID: GlassID,
    placement: GlassPlacement
  ) async -> GlassPlacementPersistenceResult {
    if requiresConfigurationRecovery {
      presentConfigurationRecoveryRequirementIfNeeded()
      return .failed
    }
    guard !isMutatingConfiguration else {
      return .busy
    }

    isMutatingConfiguration = true
    defer { isMutatingConfiguration = false }

    return await configurationMutationTaskCoordinator.run(ifBusy: .busy) { [weak self] in
      guard let self else {
        return .busy
      }

      do {
        let updated = try await updateGlassPlacementUseCase.execute(
          glassID: glassID,
          placement: placement
        )
        guard updated else {
          return .missing
        }

        if let index = glasses.firstIndex(where: { $0.id == glassID }) {
          glasses[index].placement = placement
        }
        return .updated
      } catch is CancellationError {
        return .failed
      } catch let error as UpdateGlassPlacementError {
        if case .configurationLoadFailed = error {
          enterConfigurationRecoveryRequiredState()
        } else {
          notification = .text(.workspaceMessagePlacementFailed)
        }
        return .failed
      } catch {
        notification = .text(.workspaceMessagePlacementFailed)
        return .failed
      }
    }
  }

  public func resetGlassPositions(
    placements: [GlassID: GlassPlacement]
  ) async -> GlassPositionResetResult {
    guard !isShuttingDown else {
      return .busy
    }
    guard !glasses.isEmpty else {
      return .noGlasses
    }
    if requiresConfigurationRecovery {
      presentConfigurationRecoveryRequirementIfNeeded()
      return .failed
    }
    guard !isMutatingConfiguration else {
      return .busy
    }
    guard Set(placements.keys) == Set(glasses.map(\.id)) else {
      notification = .text(.workspaceMessageResetStale)
      return .failed
    }

    isMutatingConfiguration = true
    defer { isMutatingConfiguration = false }

    return await configurationMutationTaskCoordinator.run(ifBusy: .busy) { [weak self] in
      guard let self else {
        return .busy
      }

      do {
        _ = try await resetGlassPositionsUseCase.execute(placements: placements)
        for index in glasses.indices {
          if let placement = placements[glasses[index].id] {
            glasses[index].placement = placement
          }
        }
        notification = nil
        return .updated
      } catch is CancellationError {
        return .failed
      } catch let error as ResetGlassPositionsError {
        if case .configurationLoadFailed = error {
          enterConfigurationRecoveryRequiredState()
        } else {
          notification = .text(.workspaceMessageResetFailed)
        }
        return .failed
      } catch {
        notification = .text(.workspaceMessageResetFailed)
        return .failed
      }
    }
  }

  public func planDrop(
    glassID: GlassID,
    sourceURLs: [URL]
  ) async -> DropPlan {
    guard canMutateConfiguration,
      let session = sessions[glassID],
      !isDropBusy(glassID: glassID)
    else {
      let rejection = DropPlan.reject(.destinationUnavailable)
      updateInteraction(.dropInvalid(.destinationUnavailable), for: glassID)
      return rejection
    }

    let planningToken = dropPlanningTracker.begin(glassID)
    defer { dropPlanningTracker.finish(planningToken, for: glassID) }

    updateInteraction(.hovered, for: glassID)
    let plan = await session.previewDrop(sourceURLs: sourceURLs)

    guard dropPlanningTracker.isCurrent(planningToken, for: glassID),
      canMutateConfiguration,
      !isDropBusy(glassID: glassID),
      sessions[glassID] === session
    else {
      return .reject(.destinationUnavailable)
    }

    switch plan {
    case .copy(let copyPlan):
      updateInteraction(.dropValid(.copy(copyPlan)), for: glassID)
    case .noOperation:
      updateInteraction(.dropInvalid(.containsSameDirectoryItem), for: glassID)
    case .reject(let reason):
      updateInteraction(.dropInvalid(reason), for: glassID)
    }

    return plan
  }

  public func performDrop(
    glassID: GlassID,
    sourceURLs: [URL]
  ) async -> Bool {
    guard canMutateConfiguration,
      let session = sessions[glassID],
      !isDropBusy(glassID: glassID),
      dropExecutionGate.begin(glassID)
    else {
      updateInteraction(.dropInvalid(.destinationUnavailable), for: glassID)
      presentConfigurationRecoveryRequirementIfNeeded()
      return false
    }
    dropPlanningTracker.invalidate(glassID)
    defer { dropExecutionGate.end(glassID) }

    let freshPlan = await session.planDrop(sourceURLs: sourceURLs)
    guard case .copy(let copyPlan) = freshPlan else {
      switch freshPlan {
      case .noOperation:
        updateInteraction(.dropInvalid(.containsSameDirectoryItem), for: glassID)
      case .reject(let reason):
        updateInteraction(.dropInvalid(reason), for: glassID)
      case .copy:
        break
      }
      return false
    }

    guard canMutateConfiguration else {
      await session.abandonCopyPlan(copyPlan)
      updateInteraction(.dropInvalid(.destinationUnavailable), for: glassID)
      presentConfigurationRecoveryRequirementIfNeeded()
      return false
    }

    let firstFilename = copyPlan.items.first?.destinationFilename ?? "file"
    updateInteraction(
      .copying(
        CopyProgress(
          currentIndex: 1,
          totalCount: copyPlan.items.count,
          currentFilename: firstFilename
        )
      ),
      for: glassID
    )

    do {
      let result = try await session.executeCopy(copyPlan) { [weak self] progress in
        await self?.updateInteraction(.copying(progress), for: glassID)
      }
      updateInteraction(.idle, for: glassID)

      if let failure = result.failed {
        notification = .copyFailure(failure.reason, succeededCount: result.succeeded.count)
        return !result.succeeded.isEmpty
      }

      if result.succeeded.contains(where: { $0.recoveryMetadataCleanupPending }) {
        notification = .text(.workspaceMessageCopyCleanupPending)
      } else {
        notification = nil
      }
      return true
    } catch let error as GlassCopyExecutionError {
      updateInteraction(.idle, for: glassID)
      switch error {
      case .sessionNotRunning, .destinationMismatch:
        notification = .text(.workspaceMessageCopyDestinationGone)
      case .copyInProgress:
        notification = .text(.workspaceMessageCopyBusy)
      case .planNotPending:
        notification = .text(.workspaceMessageCopyUnauthorized)
      }
      return false
    } catch {
      updateInteraction(.idle, for: glassID)
      notification = .text(.workspaceMessageCopyFailed)
      return false
    }
  }

  public func cancelDrop(glassID: GlassID) {
    dropPlanningTracker.invalidate(glassID)
    guard !isDropBusy(glassID: glassID) else {
      return
    }
    updateInteraction(.idle, for: glassID)
  }

  public func cancelCopy(glassID: GlassID) async {
    guard let entry = glasses.first(where: { $0.id == glassID }),
      GlassInteractionPolicy.allowsCopyCancellation(during: entry.interactionState),
      let session = sessions[glassID]
    else {
      return
    }
    await session.cancelCopy()
  }

  public func canRenameGlass(glassID: GlassID) -> Bool {
    canMutateConfiguration
      && glasses.contains(where: { $0.id == glassID })
      && !isDropBusy(glassID: glassID)
  }

  public func renameGlass(
    glassID: GlassID,
    title: String
  ) async {
    if requiresConfigurationRecovery {
      presentConfigurationRecoveryRequirementIfNeeded()
      return
    }
    guard canRenameGlass(glassID: glassID) else {
      return
    }

    isMutatingConfiguration = true
    notification = nil
    defer { isMutatingConfiguration = false }

    await configurationMutationTaskCoordinator.run(ifBusy: ()) { [weak self] in
      guard let self else {
        return
      }

      do {
        let updated = try await updateGlassTitleUseCase.execute(
          glassID: glassID,
          title: title
        )
        guard updated,
          let index = glasses.firstIndex(where: { $0.id == glassID })
        else {
          return
        }

        glasses[index].title = title.trimmingCharacters(in: .whitespacesAndNewlines)
      } catch is CancellationError {
        return
      } catch let error as UpdateGlassTitleError {
        switch error {
        case .configurationLoadFailed:
          enterConfigurationRecoveryRequiredState()
        case .configurationChanged:
          notification = .text(.workspaceMessageRenameStale)
        case .emptyTitle:
          notification = .text(.workspaceMessageRenameEmpty)
        case .titleTooLong:
          notification = .text(.workspaceMessageRenameTooLong)
        case .invalidConfiguration:
          notification = .text(.workspaceMessageRenameInvalid)
        case .configurationSaveFailed:
          notification = .text(.workspaceMessageRenameSaveFailed)
        }
      } catch {
        notification = .text(.workspaceMessageRenameFailed)
      }
    }
  }

  public func canChangeSpacesBehavior(glassID: GlassID) -> Bool {
    canMutateConfiguration
      && glasses.contains(where: { $0.id == glassID })
      && !isDropBusy(glassID: glassID)
  }

  public func setShowOnAllSpaces(
    glassID: GlassID,
    showOnAllSpaces: Bool
  ) async {
    if requiresConfigurationRecovery {
      presentConfigurationRecoveryRequirementIfNeeded()
      return
    }
    guard canChangeSpacesBehavior(glassID: glassID) else {
      return
    }

    isMutatingConfiguration = true
    notification = nil
    defer { isMutatingConfiguration = false }

    await configurationMutationTaskCoordinator.run(ifBusy: ()) { [weak self] in
      guard let self else {
        return
      }

      do {
        let updated = try await updateGlassSpacesBehaviorUseCase.execute(
          glassID: glassID,
          showOnAllSpaces: showOnAllSpaces
        )
        guard updated,
          let index = glasses.firstIndex(where: { $0.id == glassID })
        else {
          return
        }

        glasses[index].showOnAllSpaces = showOnAllSpaces
      } catch is CancellationError {
        return
      } catch let error as UpdateGlassSpacesBehaviorError {
        switch error {
        case .configurationLoadFailed:
          enterConfigurationRecoveryRequiredState()
        case .configurationChanged:
          notification = .text(.workspaceMessageSpacesStale)
        case .invalidConfiguration:
          notification = .text(.workspaceMessageSpacesInvalid)
        case .configurationSaveFailed:
          notification = .text(.workspaceMessageSpacesSaveFailed)
        }
      } catch {
        notification = .text(.workspaceMessageSpacesFailed)
      }
    }
  }

  public func canRefreshGlass(glassID: GlassID) -> Bool {
    guard canMutateConfiguration,
      sessions[glassID] != nil,
      !manuallyRefreshingGlassIDs.contains(glassID),
      !isDropBusy(glassID: glassID),
      let entry = glasses.first(where: { $0.id == glassID }),
      GlassInteractionPolicy.allowsRemoval(during: entry.interactionState)
    else {
      return false
    }

    switch entry.contentState {
    case .ready, .empty, .failed(.enumerationFailed), .failed(.metadataFailed):
      return true
    case .loading, .unavailable, .failed(.unexpected):
      return false
    }
  }

  public func refreshGlass(glassID: GlassID) async {
    guard canRefreshGlass(glassID: glassID), let session = sessions[glassID] else {
      return
    }
    manuallyRefreshingGlassIDs.insert(glassID)
    defer { manuallyRefreshingGlassIDs.remove(glassID) }
    await session.refresh()
  }

  public func canReconnectSource(glassID: GlassID) -> Bool {
    guard canMutateConfiguration,
      !isDropBusy(glassID: glassID),
      let entry = glasses.first(where: { $0.id == glassID })
    else {
      return false
    }

    if case .unavailable = entry.contentState {
      return true
    }
    return false
  }

  public func reconnectGlassSource(glassID: GlassID) async {
    if requiresConfigurationRecovery {
      presentConfigurationRecoveryRequirementIfNeeded()
      return
    }
    guard canReconnectSource(glassID: glassID) else {
      return
    }

    isMutatingConfiguration = true
    notification = nil
    defer { isMutatingConfiguration = false }

    await configurationMutationTaskCoordinator.run(ifBusy: ()) { [weak self] in
      guard let self else {
        return
      }

      sessionTaskTracker.invalidate(glassID)
      stateTasks[glassID]?.cancel()
      stateTasks[glassID] = nil
      if let session = sessions[glassID] {
        // Retain discovery while stop suspends: shutdown can still find this session
        // and join the same idempotent cleanup before approving termination.
        await WorkspaceSessionRetirement.stopAndRemove(
          stop: { await session.stop() },
          isCurrent: { self.sessions[glassID] === session },
          remove: { self.sessions[glassID] = nil }
        )
      }
      connectedFolderURLs[glassID] = nil

      do {
        guard let seed = try await reconnectGlassSourceUseCase.execute(glassID: glassID) else {
          return
        }

        do {
          try await activate(seed)
          notification = nil
        } catch is CancellationError {
          return
        } catch {
          notification = .text(.workspaceMessageReconnectActivationFailed)
        }
      } catch is CancellationError {
        return
      } catch let error as ReconnectGlassSourceError {
        handleReconnectError(error)
      } catch {
        notification = .text(.workspaceMessageReconnectFailed)
      }
    }
  }

  public func open(_ item: GlassItem) {
    do {
      try fileActionUseCase.open(item)
    } catch {
      notification = .openFailed(item.displayName)
    }
  }

  public func revealInFinder(_ item: GlassItem) {
    fileActionUseCase.reveal(item)
  }

  public func canRevealConnectedFolder(glassID: GlassID) -> Bool {
    connectedFolderURLs[glassID] != nil
  }

  public func revealConnectedFolder(glassID: GlassID) {
    guard let url = connectedFolderURLs[glassID] else {
      notification = .text(.workspaceMessageInactiveConnection)
      return
    }
    folderActionUseCase.revealConnectedFolder(url: url)
  }

  public func dismissMessage() {
    notification = nil
  }

  public func prepareForTermination() {
    isShuttingDown = true
  }

  public func cancelActiveCopiesForTermination() async {
    prepareForTermination()

    // Start copy cancellation before the remaining shutdown sequence awaits Recovery,
    // configuration quiescence, or placement persistence. This prevents an in-flight copy from
    // continuing toward final commit merely because termination cleanup has other work to finish.
    let activeSessions = Array(sessions.values)
    for session in activeSessions {
      await session.cancelCopy()
    }
  }

  public func quiesceConfigurationMutationsForTermination() async {
    prepareForTermination()

    // Initial restore and every configuration mutation must finish cancellation cleanup before
    // termination performs its final placement flush. Otherwise a mutation can keep the workspace
    // busy or continue writing configuration after AppKit has approved process termination.
    await initialRestoreTaskCoordinator.cancelAndWait()
    await configurationMutationTaskCoordinator.cancelAndWait()

    // The tracked operations have completed. Their outer callers may still be scheduled to run
    // their cleanup on MainActor, so establish the quiesced state explicitly before the
    // termination-only placement flush starts.
    isCreatingGlass = false
    isRestoring = false
    isMutatingConfiguration = false
  }

  public func shutdown() async {
    await cancelActiveCopiesForTermination()
    await quiesceConfigurationMutationsForTermination()
    await deactivateAllSessions()
  }

  private func applyRestoreResult(_ result: ApplicationRestoreResult) async {
    for failure in result.failures {
      upsert(
        GlassWorkspaceEntry(
          id: failure.glassID,
          title: failure.title,
          contentState: Self.contentState(for: failure.reason),
          placement: failure.placement,
          showOnAllSpaces: failure.showOnAllSpaces
        )
      )
    }

    for seed in result.seeds {
      do {
        try await activate(seed)
      } catch is CancellationError {
        continue
      } catch {
        upsert(
          GlassWorkspaceEntry(
            id: seed.configuration.id,
            title: seed.configuration.title,
            contentState: .failed(.unexpected),
            placement: seed.configuration.placement,
            showOnAllSpaces: seed.configuration.showOnAllSpaces
          )
        )
      }
    }

    if result.refreshedConfigurationSavePending {
      notification = .text(.workspaceMessageRestorePermissionsPending)
    } else if !result.failures.isEmpty {
      notification = .text(.workspaceMessageRestorePartial)
    } else {
      notification = nil
    }
  }

  private func deactivateAllSessions() async {
    let activeSessions = Array(sessions)
    sessionTaskTracker.invalidateAll()
    for task in stateTasks.values {
      task.cancel()
    }
    stateTasks.removeAll(keepingCapacity: false)
    connectedFolderURLs.removeAll(keepingCapacity: false)

    // Stop may suspend during snapshot/copy/security-scope cleanup. Keep each session
    // discoverable until its stop has completed so a reentrant shutdown can join
    // cleanup instead of returning while folder authority is still held.
    for (glassID, session) in activeSessions {
      await WorkspaceSessionRetirement.stopAndRemove(
        stop: { await session.stop() },
        isCurrent: { self.sessions[glassID] === session },
        remove: { self.sessions[glassID] = nil }
      )
    }
  }

  private func activate(_ seed: CreatedGlassRuntimeSeed) async throws {
    let session = runtimeSessionFactory.makeSession(from: seed)

    guard !isShuttingDown else {
      await session.stop()
      throw CancellationError()
    }

    do {
      let states = try await session.start()
      guard !isShuttingDown else {
        throw CancellationError()
      }

      let glassID = seed.configuration.id

      sessions[glassID] = session
      connectedFolderURLs[glassID] = seed.access.url
      upsert(
        GlassWorkspaceEntry(
          id: glassID,
          title: seed.configuration.title,
          contentState: .loading,
          placement: seed.configuration.placement,
          showOnAllSpaces: seed.configuration.showOnAllSpaces
        )
      )

      stateTasks[glassID]?.cancel()
      let stateTaskToken = sessionTaskTracker.begin(glassID)
      stateTasks[glassID] = Task { [weak self] in
        for await state in states {
          guard !Task.isCancelled,
            let self,
            self.sessionTaskTracker.isCurrent(stateTaskToken, for: glassID)
          else {
            return
          }
          self.updateState(state, for: glassID)
        }

        guard let self,
          self.sessionTaskTracker.finish(stateTaskToken, for: glassID)
        else {
          return
        }
        self.stateTasks[glassID] = nil
        self.sessions[glassID] = nil
        self.connectedFolderURLs[glassID] = nil
      }
    } catch {
      await session.stop()
      throw error
    }
  }

  private func updateState(_ state: GlassContentState, for glassID: GlassID) {
    guard let index = glasses.firstIndex(where: { $0.id == glassID }) else {
      return
    }
    glasses[index].contentState = state
  }

  private func updateInteraction(_ state: InteractionState, for glassID: GlassID) {
    guard let index = glasses.firstIndex(where: { $0.id == glassID }) else {
      return
    }
    glasses[index].interactionState = state
  }

  private func handleReconnectError(_ error: ReconnectGlassSourceError) {
    switch error {
    case .configurationLoadFailed:
      enterConfigurationRecoveryRequiredState()
    case .configurationMissing:
      notification = .text(.workspaceMessageReconnectMissing)
    case .sourceCreationFailed:
      notification = .text(.workspaceMessageReconnectAccessSaveFailed)
    case .selectedSourceIdentityUnavailable:
      notification = .text(.workspaceMessageReconnectIdentityUnknown)
    case .selectedSourceMismatch:
      notification = .text(.workspaceMessageReconnectWrongFolder)
    case .folderAccess(.bookmarkResolutionFailed), .folderAccessFailed:
      notification = .text(.workspaceMessageReconnectOpenFailed)
    case .folderAccess(.accessDenied):
      notification = .text(.workspaceMessageReconnectDenied)
    case .folderAccess(.resourceReplacementDetected):
      notification = .text(.workspaceMessageReconnectReplaced)
    case .eventStreamFailed:
      notification = .text(.workspaceMessageReconnectWatchFailed)
    case .snapshotFailed:
      notification = .text(.workspaceMessageReconnectReadFailed)
    case .invalidConfiguration:
      notification = .text(.workspaceMessageReconnectInvalid)
    case .staleConfiguration:
      notification = .text(.workspaceMessageReconnectStale)
    case .configurationSaveFailed:
      notification = .text(.workspaceMessageReconnectSaveFailed)
    }
  }

  private func enterConfigurationRecoveryRequiredState() {
    requiresConfigurationRecovery = true
    notification = .text(.workspaceMessageRecoveryRequired)
  }

  private func presentConfigurationRecoveryRequirementIfNeeded() {
    guard requiresConfigurationRecovery else {
      return
    }
    notification = .text(.workspaceMessageRecoveryRequired)
  }

  private var hasActiveCopy: Bool {
    if dropExecutionGate.hasActiveExecution {
      return true
    }
    return glasses.contains { entry in
      if case .copying = entry.interactionState {
        return true
      }
      return false
    }
  }

  private func isDropBusy(glassID: GlassID) -> Bool {
    dropExecutionGate.contains(glassID) || isCopying(glassID: glassID)
  }

  private func isCopying(glassID: GlassID) -> Bool {
    guard let entry = glasses.first(where: { $0.id == glassID }) else {
      return false
    }
    if case .copying = entry.interactionState {
      return true
    }
    return false
  }

  private func upsert(_ entry: GlassWorkspaceEntry) {
    if let index = glasses.firstIndex(where: { $0.id == entry.id }) {
      glasses[index] = entry
    } else {
      glasses.append(entry)
    }
  }

  private static func contentState(
    for failure: GlassRestoreFailure.Reason
  ) -> GlassContentState {
    switch failure {
    case .folderAccess(let accessError):
      switch accessError {
      case .bookmarkResolutionFailed:
        return .unavailable(.bookmarkResolutionFailed)
      case .accessDenied:
        return .unavailable(.permissionLost)
      case .resourceReplacementDetected:
        return .unavailable(.replacementDetected)
      }

    case .eventStreamFailed:
      return .failed(.unexpected)

    case .snapshotFailed:
      return .failed(.enumerationFailed)

    case .invalidRefreshedConfiguration:
      return .failed(.unexpected)
    }
  }

  static func copyFailureMessage(
    _ failure: CopyItemFailure,
    succeededCount: Int
  ) -> String {
    WorkspaceNotification.copyFailure(failure.reason, succeededCount: succeededCount)
      .resolve(locale: Locale(identifier: "en"))
  }

  private static func userFacingMessage(for error: Error) -> WorkspaceNotification {
    guard let createError = error as? CreateGlassError else {
      return .text(.workspaceMessageAddFailed)
    }

    switch createError {
    case .sourceCreationFailed:
      return .text(.workspaceMessageAddAccessSaveFailed)
    case .sourceIdentityUnavailable:
      return .text(.workspaceMessageAddIdentityUnknown)
    case .placementUnavailable:
      return .text(.workspaceMessageAddPlacementFailed)
    case .invalidConfiguration:
      return .text(.workspaceMessageAddInvalid)
    case .configurationLoadFailed:
      return .text(.workspaceMessageRecoveryRequired)
    case .folderAccess:
      return .text(.workspaceMessageAddAccessFailed)
    case .eventStreamFailed:
      return .text(.workspaceMessageAddWatchFailed)
    case .snapshotFailed:
      return .text(.workspaceMessageAddReadFailed)
    case .configurationSaveFailed:
      return .text(.workspaceMessageAddSaveFailed)
    }
  }
}

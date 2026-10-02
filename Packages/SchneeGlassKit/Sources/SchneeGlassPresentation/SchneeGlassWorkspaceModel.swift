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
  public private(set) var userMessage: String?

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
    userMessage = nil
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
    userMessage = nil
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
          userMessage =
            "The configuration backup was restored, but SchneeGlass couldn't reload it. Restart SchneeGlass to retry the restored configuration."
          return .restoredNeedsRestart
        }

        return .busy
      } catch {
        if backupWasRestored {
          requiresConfigurationRecovery = true
          userMessage =
            "The configuration backup was restored, but SchneeGlass couldn't reload it. Restart SchneeGlass to retry the restored configuration."
          return .restoredNeedsRestart
        }

        userMessage =
          "SchneeGlass couldn't restore that configuration backup. The current configuration was left unchanged."
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
    userMessage = nil
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
          userMessage = Self.userFacingMessage(for: error)
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
        userMessage = nil
      } catch is CancellationError {
        return
      } catch let error as RemoveGlassError {
        if case .configurationLoadFailed = error {
          enterConfigurationRecoveryRequiredState()
        } else {
          userMessage =
            "SchneeGlass couldn't remove this Glass from its configuration. The folder and its files were not changed."
        }
      } catch {
        userMessage =
          "SchneeGlass couldn't remove this Glass from its configuration. The folder and its files were not changed."
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
          userMessage =
            "SchneeGlass couldn't save the new Glass position. Files and folders were not changed."
        }
        return .failed
      } catch {
        userMessage =
          "SchneeGlass couldn't save the new Glass position. Files and folders were not changed."
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
      userMessage =
        "SchneeGlass couldn't reset positions because the workspace changed. No files or folders were changed."
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
        userMessage = nil
        return .updated
      } catch is CancellationError {
        return .failed
      } catch let error as ResetGlassPositionsError {
        if case .configurationLoadFailed = error {
          enterConfigurationRecoveryRequiredState()
        } else {
          userMessage =
            "SchneeGlass couldn't reset Glass positions. Files and folders were not changed."
        }
        return .failed
      } catch {
        userMessage =
          "SchneeGlass couldn't reset Glass positions. Files and folders were not changed."
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
        userMessage = Self.copyFailureMessage(
          failure,
          succeededCount: result.succeeded.count
        )
        return !result.succeeded.isEmpty
      }

      if result.succeeded.contains(where: { $0.recoveryMetadataCleanupPending }) {
        userMessage =
          "The files were copied, but SchneeGlass still has recovery metadata to clean up. Your copied files were not changed."
      } else {
        userMessage = nil
      }
      return true
    } catch let error as GlassCopyExecutionError {
      updateInteraction(.idle, for: glassID)
      switch error {
      case .sessionNotRunning, .destinationMismatch:
        userMessage = "This Glass is no longer available as a copy destination. Nothing was copied."
      case .copyInProgress:
        userMessage = "A copy is already running for this Glass."
      case .planNotPending:
        userMessage =
          "This Drop is no longer authorized for copying. Nothing was copied; try again."
      }
      return false
    } catch {
      updateInteraction(.idle, for: glassID)
      userMessage = "SchneeGlass couldn't copy these files. Source files were not moved or deleted."
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
    userMessage = nil
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
          userMessage =
            "The Glass configuration changed while renaming. Nothing was overwritten; try again."
        case .emptyTitle:
          userMessage = "Glass name cannot be empty."
        case .titleTooLong:
          userMessage = "Glass name must be 100 characters or fewer."
        case .invalidConfiguration:
          userMessage = "SchneeGlass couldn't build a valid renamed Glass. Nothing was saved."
        case .configurationSaveFailed:
          userMessage = "SchneeGlass couldn't save the new Glass name. Nothing was changed."
        }
      } catch {
        userMessage = "SchneeGlass couldn't rename this Glass. Nothing was changed."
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
    userMessage = nil
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
          userMessage =
            "The Glass configuration changed while updating Spaces behavior. Nothing was overwritten; try again."
        case .invalidConfiguration:
          userMessage =
            "SchneeGlass couldn't build a valid Spaces configuration. Nothing was saved."
        case .configurationSaveFailed:
          userMessage =
            "SchneeGlass couldn't save the Spaces behavior. Nothing was changed."
        }
      } catch {
        userMessage =
          "SchneeGlass couldn't update this Glass's Spaces behavior. Nothing was changed."
      }
    }
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
    userMessage = nil
    defer { isMutatingConfiguration = false }

    await configurationMutationTaskCoordinator.run(ifBusy: ()) { [weak self] in
      guard let self else {
        return
      }

      sessionTaskTracker.invalidate(glassID)
      stateTasks[glassID]?.cancel()
      stateTasks[glassID] = nil
      if let session = sessions.removeValue(forKey: glassID) {
        await session.stop()
      }
      connectedFolderURLs[glassID] = nil

      do {
        guard let seed = try await reconnectGlassSourceUseCase.execute(glassID: glassID) else {
          return
        }

        do {
          try await activate(seed)
          userMessage = nil
        } catch is CancellationError {
          return
        } catch {
          userMessage =
            "The folder reconnect was saved, but SchneeGlass couldn't start this Glass. Try reconnecting again or restart SchneeGlass."
        }
      } catch is CancellationError {
        return
      } catch let error as ReconnectGlassSourceError {
        handleReconnectError(error)
      } catch {
        userMessage =
          "SchneeGlass couldn't reconnect this Glass. The saved folder connection was left unchanged."
      }
    }
  }

  public func open(_ item: GlassItem) {
    do {
      try fileActionUseCase.open(item)
    } catch {
      userMessage = "macOS couldn't open \(item.displayName)."
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
      userMessage = "This Glass does not currently have an active folder connection."
      return
    }
    folderActionUseCase.revealConnectedFolder(url: url)
  }

  public func dismissMessage() {
    userMessage = nil
  }

  public func prepareForTermination() {
    isShuttingDown = true
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
    await quiesceConfigurationMutationsForTermination()

    // Application termination is different from configuration recovery: an active user copy must
    // enter the existing cancellation/recovery path instead of making Quit wait for the copy to
    // finish naturally.
    let activeSessions = Array(sessions.values)
    for session in activeSessions {
      await session.cancelCopy()
    }

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
      userMessage =
        "Some refreshed folder permissions could not be saved. Your current Glasses remain available for this session."
    } else if !result.failures.isEmpty {
      userMessage = "Some Glasses couldn't reconnect. Other Glasses were restored normally."
    } else {
      userMessage = nil
    }
  }

  private func deactivateAllSessions() async {
    let activeSessions = Array(sessions.values)
    sessionTaskTracker.invalidateAll()
    for task in stateTasks.values {
      task.cancel()
    }
    stateTasks.removeAll(keepingCapacity: false)
    sessions.removeAll(keepingCapacity: false)
    connectedFolderURLs.removeAll(keepingCapacity: false)

    for session in activeSessions {
      await session.stop()
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
      userMessage = "This Glass is no longer present in the saved configuration."
    case .sourceCreationFailed:
      userMessage =
        "SchneeGlass couldn't remember access to the selected folder. The previous connection was left unchanged."
    case .selectedSourceIdentityUnavailable:
      userMessage =
        "SchneeGlass couldn't prove that the selected folder is the original folder. The previous connection was left unchanged."
    case .selectedSourceMismatch:
      userMessage =
        "That is a different folder. Choose the original folder that this Glass was connected to."
    case .folderAccess(.bookmarkResolutionFailed), .folderAccessFailed:
      userMessage =
        "macOS couldn't reopen the selected folder. The previous connection was left unchanged."
    case .folderAccess(.accessDenied):
      userMessage =
        "macOS denied access to the selected folder. The previous connection was left unchanged."
    case .folderAccess(.resourceReplacementDetected):
      userMessage =
        "The selected folder changed while reconnecting. Nothing was saved."
    case .eventStreamFailed:
      userMessage =
        "SchneeGlass could access the folder but couldn't watch it for changes. Nothing was saved."
    case .snapshotFailed:
      userMessage =
        "SchneeGlass could access the folder but couldn't read it safely. Nothing was saved."
    case .invalidConfiguration:
      userMessage =
        "SchneeGlass couldn't build a valid reconnect configuration. Nothing was saved."
    case .staleConfiguration:
      userMessage =
        "The Glass configuration changed while reconnecting. Nothing was overwritten; try again."
    case .configurationSaveFailed:
      userMessage =
        "SchneeGlass couldn't save the reconnected folder. The previous connection was left unchanged."
    }
  }

  private func enterConfigurationRecoveryRequiredState() {
    requiresConfigurationRecovery = true
    userMessage = Self.configurationRecoveryRequiredMessage
  }

  private func presentConfigurationRecoveryRequirementIfNeeded() {
    guard requiresConfigurationRecovery else {
      return
    }
    userMessage = Self.configurationRecoveryRequiredMessage
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

  private static let configurationRecoveryRequiredMessage =
    "SchneeGlass couldn't read its saved configuration. Use Recovery before making changes."

  static func copyFailureMessage(
    _ failure: CopyItemFailure,
    succeededCount: Int
  ) -> String {
    let prefix =
      succeededCount > 0
      ? "\(succeededCount) file(s) were copied before the operation stopped. "
      : "Nothing was copied. "

    switch failure.reason {
    case .sourceUnavailable:
      return prefix + "A source file became unavailable."
    case .unsupportedItem:
      return prefix + "One of the dropped items is not supported."
    case .destinationUnavailable:
      return prefix + "The destination folder became unavailable."
    case .permissionDenied:
      return prefix + "macOS denied file access."
    case .insufficientSpace:
      return prefix + "There is not enough free space at the destination."
    case .collision:
      return prefix + "A file with the same name already exists. Nothing was overwritten."
    case .verificationFailed:
      return prefix + "SchneeGlass could not verify a copied file safely."
    case .commitStateUnknown:
      let completedPrefix = succeededCount > 0 ? prefix : ""
      return
        completedPrefix
        + "SchneeGlass may have created the current destination file, but could not verify its final state. "
        + "Check Recovery before retrying; source files were not moved or deleted."
    case .cancelled:
      return prefix + "The copy was cancelled."
    case .unexpected:
      return prefix + "SchneeGlass encountered an unexpected copy error."
    }
  }

  private static func userFacingMessage(for error: Error) -> String {
    guard let createError = error as? CreateGlassError else {
      return "SchneeGlass couldn't add this folder. Nothing was changed."
    }

    switch createError {
    case .sourceCreationFailed:
      return "SchneeGlass couldn't remember access to this folder."
    case .sourceIdentityUnavailable:
      return "SchneeGlass couldn't safely verify this folder's identity. Nothing was added."
    case .placementUnavailable:
      return "SchneeGlass couldn't find a usable screen position."
    case .invalidConfiguration:
      return "SchneeGlass couldn't create a valid Glass for this folder."
    case .configurationLoadFailed:
      return configurationRecoveryRequiredMessage
    case .folderAccess:
      return "SchneeGlass couldn't access this folder. Choose it again to reconnect."
    case .eventStreamFailed:
      return "SchneeGlass couldn't watch this folder for changes."
    case .snapshotFailed:
      return "SchneeGlass couldn't read this folder."
    case .configurationSaveFailed:
      return "SchneeGlass couldn't save this Glass. Nothing was added."
    }
  }
}

import Foundation
import SchneeGlassApplication
import SchneeGlassFileSystemAdapter
import SchneeGlassMacOSAdapter
import SchneeGlassPersistenceAdapter
import SchneeGlassPresentation

@MainActor
final class SchneeGlassCompositionRoot {
  let workspaceModel: SchneeGlassWorkspaceModel
  let pendingCopyRecoveryModel: PendingCopyRecoveryCenterModel

  private let processInstanceLock: ApplicationProcessLock

  private init(
    processInstanceLock: ApplicationProcessLock,
    workspaceModel: SchneeGlassWorkspaceModel,
    pendingCopyRecoveryModel: PendingCopyRecoveryCenterModel
  ) {
    self.processInstanceLock = processInstanceLock
    self.workspaceModel = workspaceModel
    self.pendingCopyRecoveryModel = pendingCopyRecoveryModel
  }

  static func make() throws -> SchneeGlassCompositionRoot {
    let fileManager = FileManager.default
    let applicationSupport = try fileManager.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    let processInstanceLock = try ApplicationProcessLock(
      lockFileURL: applicationSupport.appendingPathComponent(
        ".io.github.lamy210.schneeglass.instance.lock",
        isDirectory: false
      )
    )
    let baseDirectory =
      applicationSupport
      .appendingPathComponent("io.github.lamy210.schneeglass", isDirectory: true)

    let configurationStore = JSONConfigurationStore(baseDirectory: baseDirectory)
    let accessController = SecurityScopedAccessCoordinator()
    let eventHub = FileEventHub()
    let snapshotReader = NativeFolderSnapshotReader()
    let pendingCopyStore = JSONPendingCopyStore(
      applicationSupportRoot: baseDirectory,
      relativeDirectory: "FileOperations"
    )
    let dropCopyPipeline = PinnedDropCopyPipeline(recoveryStore: pendingCopyStore)
    let activityGate = FileOperationActivityGate()
    let folderSelector = NativeFolderSelector()
    let sourceCreator = SecurityScopedFolderSourceFactory()
    let fileActor = NSWorkspaceFileActionAdapter()

    let fileCopying = ActivityTrackedFileCopying(
      delegate: dropCopyPipeline.fileCopying,
      abandoner: dropCopyPipeline.dropPlanning,
      activityGate: activityGate
    )

    let createGlassUseCase = CreateGlassUseCase(
      folderSelector: folderSelector,
      sourceCreator: sourceCreator,
      placementProvider: NativeInitialGlassPlacementProvider(),
      configurationStore: configurationStore,
      accessController: accessController,
      eventStreaming: eventHub,
      snapshotReader: snapshotReader
    )

    let restoreApplicationUseCase = RestoreApplicationUseCase(
      configurationStore: configurationStore,
      accessController: accessController,
      eventStreaming: eventHub,
      snapshotReader: snapshotReader
    )

    let reconnectGlassSourceUseCase = ReconnectGlassSourceUseCase(
      configurationStore: configurationStore,
      folderSelector: NativeFolderReconnectSelector(),
      sourceCreator: sourceCreator,
      accessController: accessController,
      eventStreaming: eventHub,
      snapshotReader: snapshotReader
    )

    let removeGlassUseCase = RemoveGlassUseCase(
      configurationStore: configurationStore,
      pendingCopyStore: pendingCopyStore
    )

    let updateGlassPlacementUseCase = UpdateGlassPlacementUseCase(
      configurationStore: configurationStore
    )

    let resetGlassPositionsUseCase = ResetGlassPositionsUseCase(
      configurationStore: configurationStore
    )

    let updateGlassTitleUseCase = UpdateGlassTitleUseCase(
      configurationStore: configurationStore
    )

    let updateGlassSpacesBehaviorUseCase = UpdateGlassSpacesBehaviorUseCase(
      configurationStore: configurationStore
    )

    let configurationRecoveryUseCase = ConfigurationRecoveryUseCase(
      recoveryStore: configurationStore,
      pendingCopyStore: pendingCopyStore,
      activityGate: activityGate
    )

    let fileActionUseCase = WorkspaceFileActionUseCase(
      actor: fileActor
    )
    let folderActionUseCase = WorkspaceFolderActionUseCase(
      actor: fileActor
    )

    let runtimeSessionFactory = GlassRuntimeSessionFactory(
      eventStreaming: eventHub,
      snapshotReader: snapshotReader,
      accessController: accessController,
      dropPlanning: dropCopyPipeline.dropPlanning,
      fileCopying: fileCopying
    )

    let workspaceModel = SchneeGlassWorkspaceModel(
      createGlassUseCase: createGlassUseCase,
      restoreApplicationUseCase: restoreApplicationUseCase,
      reconnectGlassSourceUseCase: reconnectGlassSourceUseCase,
      removeGlassUseCase: removeGlassUseCase,
      updateGlassPlacementUseCase: updateGlassPlacementUseCase,
      resetGlassPositionsUseCase: resetGlassPositionsUseCase,
      updateGlassTitleUseCase: updateGlassTitleUseCase,
      updateGlassSpacesBehaviorUseCase: updateGlassSpacesBehaviorUseCase,
      configurationRecoveryUseCase: configurationRecoveryUseCase,
      fileActionUseCase: fileActionUseCase,
      folderActionUseCase: folderActionUseCase,
      runtimeSessionFactory: runtimeSessionFactory
    )

    let recoveryInspector = PendingCopyRecoveryInspector()
    let recoveryExecution = PendingCopyRecoveryExecutionUseCase(
      pendingCopyStore: pendingCopyStore,
      recoveryInspector: recoveryInspector,
      ownedStagingCleaner: OwnedStagingRecoveryCleaner()
    )
    let recoveryCenterUseCase = PendingCopyRecoveryCenterUseCase(
      pendingCopyStore: pendingCopyStore,
      configurationStore: configurationStore,
      accessController: accessController,
      recoveryInspector: recoveryInspector,
      recoveryExecution: recoveryExecution,
      activityGate: activityGate
    )
    let reconnectUseCase = PendingCopyDestinationReconnectUseCase(
      pendingCopyStore: pendingCopyStore,
      configurationStore: configurationStore,
      folderSelector: folderSelector,
      sourceCreator: sourceCreator,
      accessController: accessController,
      activityGate: activityGate
    )
    let navigationUseCase = PendingCopyRecoveryNavigationUseCase(
      pendingCopyStore: pendingCopyStore,
      configurationStore: configurationStore,
      accessController: accessController,
      recoveryInspector: recoveryInspector,
      fileActor: fileActor
    )
    let pendingCopyRecoveryModel = PendingCopyRecoveryCenterModel(
      workspaceModel: workspaceModel,
      useCase: recoveryCenterUseCase,
      reconnectUseCase: reconnectUseCase,
      navigationUseCase: navigationUseCase
    )

    return SchneeGlassCompositionRoot(
      processInstanceLock: processInstanceLock,
      workspaceModel: workspaceModel,
      pendingCopyRecoveryModel: pendingCopyRecoveryModel
    )
  }
}

enum SchneeGlassBootstrapState {
  case ready(SchneeGlassCompositionRoot)
  case failed

  @MainActor
  static func resolve() -> SchneeGlassBootstrapState {
    do {
      return .ready(try SchneeGlassCompositionRoot.make())
    } catch {
      return .failed
    }
  }
}

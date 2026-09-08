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

    private init(
        workspaceModel: SchneeGlassWorkspaceModel,
        pendingCopyRecoveryModel: PendingCopyRecoveryCenterModel
    ) {
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
        let baseDirectory = applicationSupport
            .appendingPathComponent("io.github.lamy210.schneeglass", isDirectory: true)
        let fileOperationsDirectory = baseDirectory
            .appendingPathComponent("FileOperations", isDirectory: true)

        let configurationStore = JSONConfigurationStore(baseDirectory: baseDirectory)
        let accessController = SecurityScopedAccessCoordinator()
        let eventHub = FileEventHub()
        let snapshotReader = NativeFolderSnapshotReader()
        let dropPlanning = NativeDropPlanningAdapter()
        let pendingCopyStore = JSONPendingCopyStore(baseDirectory: fileOperationsDirectory)
        let activityGate = FileOperationActivityGate()
        let folderSelector = NativeFolderSelector()
        let sourceCreator = SecurityScopedFolderSourceFactory()
        let fileActor = NSWorkspaceFileActionAdapter()

        let rawFileCopying = SafeFileCopyEngine(recoveryStore: pendingCopyStore)
        let fileCopying = ActivityTrackedFileCopying(
            delegate: rawFileCopying,
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

        let removeGlassUseCase = RemoveGlassUseCase(
            configurationStore: configurationStore
        )

        let updateGlassPlacementUseCase = UpdateGlassPlacementUseCase(
            configurationStore: configurationStore
        )

        let resetGlassPositionsUseCase = ResetGlassPositionsUseCase(
            configurationStore: configurationStore
        )

        let configurationRecoveryUseCase = ConfigurationRecoveryUseCase(
            recoveryProvider: configurationStore
        )

        let fileActionUseCase = WorkspaceFileActionUseCase(
            actor: fileActor
        )

        let runtimeSessionFactory = GlassRuntimeSessionFactory(
            eventStreaming: eventHub,
            snapshotReader: snapshotReader,
            accessController: accessController,
            dropPlanning: dropPlanning,
            fileCopying: fileCopying
        )

        let workspaceModel = SchneeGlassWorkspaceModel(
            createGlassUseCase: createGlassUseCase,
            restoreApplicationUseCase: restoreApplicationUseCase,
            removeGlassUseCase: removeGlassUseCase,
            updateGlassPlacementUseCase: updateGlassPlacementUseCase,
            resetGlassPositionsUseCase: resetGlassPositionsUseCase,
            configurationRecoveryUseCase: configurationRecoveryUseCase,
            fileActionUseCase: fileActionUseCase,
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

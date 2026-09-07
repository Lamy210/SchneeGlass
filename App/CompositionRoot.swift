import Foundation
import SchneeGlassApplication
import SchneeGlassFileSystemAdapter
import SchneeGlassMacOSAdapter
import SchneeGlassPersistenceAdapter
import SchneeGlassPresentation

@MainActor
final class SchneeGlassCompositionRoot {
    let workspaceModel: SchneeGlassWorkspaceModel

    private init(workspaceModel: SchneeGlassWorkspaceModel) {
        self.workspaceModel = workspaceModel
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

        let configurationStore = JSONConfigurationStore(baseDirectory: baseDirectory)
        let accessController = SecurityScopedAccessCoordinator()
        let eventHub = FileEventHub()
        let snapshotReader = NativeFolderSnapshotReader()

        let createGlassUseCase = CreateGlassUseCase(
            folderSelector: NativeFolderSelector(),
            sourceCreator: SecurityScopedFolderSourceFactory(),
            placementProvider: NativeInitialGlassPlacementProvider(),
            configurationStore: configurationStore,
            accessController: accessController,
            eventStreaming: eventHub,
            snapshotReader: snapshotReader
        )

        let runtimeSessionFactory = GlassRuntimeSessionFactory(
            eventStreaming: eventHub,
            snapshotReader: snapshotReader,
            accessController: accessController
        )

        return SchneeGlassCompositionRoot(
            workspaceModel: SchneeGlassWorkspaceModel(
                createGlassUseCase: createGlassUseCase,
                runtimeSessionFactory: runtimeSessionFactory
            )
        )
    }
}

enum SchneeGlassBootstrapState {
    case ready(SchneeGlassWorkspaceModel)
    case failed

    @MainActor
    static func resolve() -> SchneeGlassBootstrapState {
        do {
            return .ready(try SchneeGlassCompositionRoot.make().workspaceModel)
        } catch {
            return .failed
        }
    }
}

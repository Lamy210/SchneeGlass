import FileDomain
import Foundation
import SchneeGlassDomain

@MainActor
public final class CreateGlassUseCase {
    private let folderSelector: any FolderSelecting
    private let sourceCreator: any FolderSourceCreating
    private let placementProvider: any InitialGlassPlacementProviding
    private let configurationStore: any ConditionalConfigurationPersisting
    private let accessController: any FolderAccessControlling
    private let eventStreaming: any FileEventStreaming
    private let snapshotReader: any FolderSnapshotReading

    public init(
        folderSelector: any FolderSelecting,
        sourceCreator: any FolderSourceCreating,
        placementProvider: any InitialGlassPlacementProviding,
        configurationStore: any ConditionalConfigurationPersisting,
        accessController: any FolderAccessControlling,
        eventStreaming: any FileEventStreaming,
        snapshotReader: any FolderSnapshotReading
    ) {
        self.folderSelector = folderSelector
        self.sourceCreator = sourceCreator
        self.placementProvider = placementProvider
        self.configurationStore = configurationStore
        self.accessController = accessController
        self.eventStreaming = eventStreaming
        self.snapshotReader = snapshotReader
    }

    public func execute() async throws -> CreatedGlassRuntimeSeed? {
        guard let selectedURL = await folderSelector.selectFolder() else {
            return nil
        }

        let source: FolderSource
        do {
            source = try await sourceCreator.createSource(for: selectedURL)
        } catch {
            throw CreateGlassError.sourceCreationFailed
        }

        let placement: GlassPlacement
        do {
            placement = try placementProvider.initialPlacement()
        } catch {
            throw CreateGlassError.placementUnavailable
        }

        let configuration: GlassConfiguration
        do {
            configuration = try GlassConfiguration(
                title: Self.defaultTitle(for: selectedURL),
                source: source,
                placement: placement
            )
        } catch {
            throw CreateGlassError.invalidConfiguration
        }

        let existingConfigurations: [GlassConfiguration]
        do {
            existingConfigurations = try await configurationStore.load()
        } catch {
            throw CreateGlassError.configurationLoadFailed
        }

        let acquisition: FolderAccessAcquisition
        do {
            acquisition = try await accessController.acquire(
                source: source,
                glassID: configuration.id
            )
        } catch let error as FolderAccessError {
            throw CreateGlassError.folderAccess(error)
        } catch {
            throw CreateGlassError.folderAccess(.bookmarkResolutionFailed)
        }

        let eventSubscription: FileEventSubscription
        do {
            eventSubscription = try await eventStreaming.subscribe(for: acquisition.handle)
        } catch {
            await accessController.release(handleID: acquisition.handle.id)
            throw CreateGlassError.eventStreamFailed
        }

        do {
            let snapshot: FolderSnapshot
            do {
                snapshot = try await snapshotReader.snapshot(
                    for: acquisition.handle,
                    generation: 1
                )
            } catch {
                throw CreateGlassError.snapshotFailed
            }

            let persistedConfiguration: GlassConfiguration
            if let refreshedSource = acquisition.refreshedSource {
                do {
                    persistedConfiguration = try GlassConfiguration(
                        id: configuration.id,
                        title: configuration.title,
                        source: refreshedSource,
                        placement: configuration.placement,
                        showOnAllSpaces: configuration.showOnAllSpaces,
                        createdAt: configuration.createdAt
                    )
                } catch {
                    throw CreateGlassError.invalidConfiguration
                }
            } else {
                persistedConfiguration = configuration
            }

            do {
                guard try await configurationStore.save(
                    existingConfigurations + [persistedConfiguration],
                    ifCurrentMatches: existingConfigurations
                ) else {
                    throw CreateGlassError.configurationChanged
                }
            } catch let error as CreateGlassError {
                throw error
            } catch {
                throw CreateGlassError.configurationSaveFailed
            }

            return CreatedGlassRuntimeSeed(
                configuration: persistedConfiguration,
                access: acquisition.handle,
                snapshot: snapshot,
                eventSubscription: eventSubscription
            )
        } catch {
            await eventStreaming.stop(subscriptionID: eventSubscription.id)
            await accessController.release(handleID: acquisition.handle.id)
            throw error
        }
    }

    private static func defaultTitle(for url: URL) -> String {
        let name = url.standardizedFileURL.lastPathComponent
        if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }

        let path = url.standardizedFileURL.path
        return path.isEmpty ? "Folder" : path
    }
}

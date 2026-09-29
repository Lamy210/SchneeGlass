import FileDomain
import Foundation
import SchneeGlassDomain

public struct GlassRestoreFailure: Hashable, Sendable {
    public enum Reason: Hashable, Sendable {
        case folderAccess(FolderAccessError)
        case eventStreamFailed
        case snapshotFailed
        case invalidRefreshedConfiguration
    }

    public let glassID: GlassID
    public let title: String
    public let placement: GlassPlacement
    public let showOnAllSpaces: Bool
    public let reason: Reason

    public init(
        glassID: GlassID,
        title: String,
        placement: GlassPlacement,
        showOnAllSpaces: Bool,
        reason: Reason
    ) {
        self.glassID = glassID
        self.title = title
        self.placement = placement
        self.showOnAllSpaces = showOnAllSpaces
        self.reason = reason
    }
}

public struct ApplicationRestoreResult: Sendable {
    public let seeds: [CreatedGlassRuntimeSeed]
    public let failures: [GlassRestoreFailure]
    public let refreshedConfigurationSavePending: Bool

    public init(
        seeds: [CreatedGlassRuntimeSeed],
        failures: [GlassRestoreFailure],
        refreshedConfigurationSavePending: Bool
    ) {
        self.seeds = seeds
        self.failures = failures
        self.refreshedConfigurationSavePending = refreshedConfigurationSavePending
    }
}

public enum RestoreApplicationError: Error, Hashable, Sendable {
    case configurationLoadFailed
}

public actor RestoreApplicationUseCase {
    private let configurationStore: any ConditionalConfigurationPersisting
    private let accessController: any FolderAccessControlling
    private let eventStreaming: any FileEventStreaming
    private let snapshotReader: any FolderSnapshotReading

    public init(
        configurationStore: any ConditionalConfigurationPersisting,
        accessController: any FolderAccessControlling,
        eventStreaming: any FileEventStreaming,
        snapshotReader: any FolderSnapshotReading
    ) {
        self.configurationStore = configurationStore
        self.accessController = accessController
        self.eventStreaming = eventStreaming
        self.snapshotReader = snapshotReader
    }

    public func execute() async throws -> ApplicationRestoreResult {
        let configurations: [GlassConfiguration]
        do {
            configurations = try await configurationStore.load()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw RestoreApplicationError.configurationLoadFailed
        }

        try await checkCancellation(cleaning: [])

        guard !configurations.isEmpty else {
            return ApplicationRestoreResult(
                seeds: [],
                failures: [],
                refreshedConfigurationSavePending: false
            )
        }

        var effectiveConfigurations = configurations
        var seeds: [CreatedGlassRuntimeSeed] = []
        var failures: [GlassRestoreFailure] = []
        var refreshedConfigurationExists = false

        for (index, configuration) in configurations.enumerated() {
            try await checkCancellation(cleaning: seeds)

            let acquisition: FolderAccessAcquisition
            do {
                acquisition = try await accessController.acquire(
                    source: configuration.source,
                    glassID: configuration.id
                )
            } catch is CancellationError {
                await cleanup(seeds)
                throw CancellationError()
            } catch let error as FolderAccessError {
                failures.append(Self.failure(for: configuration, reason: .folderAccess(error)))
                continue
            } catch {
                failures.append(
                    Self.failure(
                        for: configuration,
                        reason: .folderAccess(.bookmarkResolutionFailed)
                    )
                )
                continue
            }

            try await checkCancellation(
                cleaning: seeds,
                currentAccess: acquisition.handle
            )

            let subscription: FileEventSubscription
            do {
                subscription = try await eventStreaming.subscribe(for: acquisition.handle)
            } catch is CancellationError {
                await accessController.release(handleID: acquisition.handle.id)
                await cleanup(seeds)
                throw CancellationError()
            } catch {
                await accessController.release(handleID: acquisition.handle.id)
                failures.append(Self.failure(for: configuration, reason: .eventStreamFailed))
                continue
            }

            try await checkCancellation(
                cleaning: seeds,
                currentAccess: acquisition.handle,
                currentSubscription: subscription
            )

            let snapshot: FolderSnapshot
            do {
                snapshot = try await snapshotReader.snapshot(
                    for: acquisition.handle,
                    generation: 1
                )
            } catch is CancellationError {
                await eventStreaming.stop(subscriptionID: subscription.id)
                await accessController.release(handleID: acquisition.handle.id)
                await cleanup(seeds)
                throw CancellationError()
            } catch {
                await eventStreaming.stop(subscriptionID: subscription.id)
                await accessController.release(handleID: acquisition.handle.id)
                failures.append(Self.failure(for: configuration, reason: .snapshotFailed))
                continue
            }

            try await checkCancellation(
                cleaning: seeds,
                currentAccess: acquisition.handle,
                currentSubscription: subscription
            )

            var effectiveConfiguration = configuration
            if let refreshedSource = acquisition.refreshedSource {
                do {
                    effectiveConfiguration = try GlassConfiguration(
                        id: configuration.id,
                        title: configuration.title,
                        source: refreshedSource,
                        placement: configuration.placement,
                        showOnAllSpaces: configuration.showOnAllSpaces,
                        createdAt: configuration.createdAt
                    )
                    effectiveConfigurations[index] = effectiveConfiguration
                    refreshedConfigurationExists = true
                } catch {
                    await eventStreaming.stop(subscriptionID: subscription.id)
                    await accessController.release(handleID: acquisition.handle.id)
                    failures.append(
                        Self.failure(
                            for: configuration,
                            reason: .invalidRefreshedConfiguration
                        )
                    )
                    continue
                }
            }

            seeds.append(
                CreatedGlassRuntimeSeed(
                    configuration: effectiveConfiguration,
                    access: acquisition.handle,
                    snapshot: snapshot,
                    eventSubscription: subscription
                )
            )
        }

        try await checkCancellation(cleaning: seeds)

        var refreshedConfigurationSavePending = false
        if refreshedConfigurationExists {
            do {
                let didSave = try await configurationStore.save(
                    effectiveConfigurations,
                    ifCurrentMatches: configurations
                )
                refreshedConfigurationSavePending = !didSave
            } catch is CancellationError {
                await cleanup(seeds)
                throw CancellationError()
            } catch {
                refreshedConfigurationSavePending = true
            }
        }

        try await checkCancellation(cleaning: seeds)

        return ApplicationRestoreResult(
            seeds: seeds,
            failures: failures,
            refreshedConfigurationSavePending: refreshedConfigurationSavePending
        )
    }

    private func checkCancellation(
        cleaning seeds: [CreatedGlassRuntimeSeed],
        currentAccess: FolderAccessHandle? = nil,
        currentSubscription: FileEventSubscription? = nil
    ) async throws {
        do {
            try Task.checkCancellation()
        } catch {
            if let currentSubscription {
                await eventStreaming.stop(subscriptionID: currentSubscription.id)
            }
            if let currentAccess {
                await accessController.release(handleID: currentAccess.id)
            }
            await cleanup(seeds)
            throw error
        }
    }

    private func cleanup(_ seeds: [CreatedGlassRuntimeSeed]) async {
        for seed in seeds.reversed() {
            await eventStreaming.stop(subscriptionID: seed.eventSubscription.id)
            await accessController.release(handleID: seed.access.id)
        }
    }

    private static func failure(
        for configuration: GlassConfiguration,
        reason: GlassRestoreFailure.Reason
    ) -> GlassRestoreFailure {
        GlassRestoreFailure(
            glassID: configuration.id,
            title: configuration.title,
            placement: configuration.placement,
            showOnAllSpaces: configuration.showOnAllSpaces,
            reason: reason
        )
    }
}

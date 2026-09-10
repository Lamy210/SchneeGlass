import SchneeGlassDomain

public enum UpdateGlassPlacementError: Error, Hashable, Sendable {
    case configurationLoadFailed
    case configurationChanged
    case invalidConfiguration
    case configurationSaveFailed
}

public actor UpdateGlassPlacementUseCase {
    private let configurationStore: any ConditionalConfigurationPersisting

    public init(configurationStore: any ConditionalConfigurationPersisting) {
        self.configurationStore = configurationStore
    }

    @discardableResult
    public func execute(
        glassID: GlassID,
        placement: GlassPlacement
    ) async throws -> Bool {
        var configurations: [GlassConfiguration]
        do {
            configurations = try await configurationStore.load()
        } catch {
            throw UpdateGlassPlacementError.configurationLoadFailed
        }
        let expectedCurrent = configurations

        guard let index = configurations.firstIndex(where: { $0.id == glassID }) else {
            return false
        }

        let current = configurations[index]
        let updated: GlassConfiguration
        do {
            updated = try GlassConfiguration(
                id: current.id,
                title: current.title,
                source: current.source,
                placement: placement,
                showOnAllSpaces: current.showOnAllSpaces,
                createdAt: current.createdAt
            )
        } catch {
            throw UpdateGlassPlacementError.invalidConfiguration
        }

        guard updated != current else {
            return true
        }

        configurations[index] = updated
        do {
            guard try await configurationStore.save(
                configurations,
                ifCurrentMatches: expectedCurrent
            ) else {
                throw UpdateGlassPlacementError.configurationChanged
            }
        } catch let error as UpdateGlassPlacementError {
            throw error
        } catch {
            throw UpdateGlassPlacementError.configurationSaveFailed
        }

        return true
    }
}

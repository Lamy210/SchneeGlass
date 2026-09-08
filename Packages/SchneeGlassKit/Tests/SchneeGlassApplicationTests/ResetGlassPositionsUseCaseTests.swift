import Foundation
@testable import SchneeGlassApplication
import SchneeGlassDomain
import Testing

private enum ResetPositionsStoreTestError: Error, Sendable {
    case injected
}

private actor ResetPositionsConfigurationStore: ConfigurationPersisting {
    private let loaded: [GlassConfiguration]
    private let failLoad: Bool
    private let failSave: Bool
    private var saved: [[GlassConfiguration]] = []

    init(
        loaded: [GlassConfiguration],
        failLoad: Bool = false,
        failSave: Bool = false
    ) {
        self.loaded = loaded
        self.failLoad = failLoad
        self.failSave = failSave
    }

    func load() async throws -> [GlassConfiguration] {
        if failLoad { throw ResetPositionsStoreTestError.injected }
        return loaded
    }

    func save(_ configurations: [GlassConfiguration]) async throws {
        if failSave { throw ResetPositionsStoreTestError.injected }
        saved.append(configurations)
    }

    func savedValues() -> [[GlassConfiguration]] { saved }
}

private func resetPositionConfiguration(
    id: GlassID = GlassID(),
    title: String = "Projects",
    x: Double,
    y: Double
) throws -> GlassConfiguration {
    try GlassConfiguration(
        id: id,
        title: title,
        source: FolderSource(
            bookmarkData: Data([1]),
            lastKnownPath: "/tmp/\(title)"
        ),
        placement: GlassPlacement(x: x, y: y),
        createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
}

@Test
func resetPositionsPersistsWholeConfigurationExactlyOnce() async throws {
    let first = try resetPositionConfiguration(title: "Projects", x: 100, y: 120)
    let second = try resetPositionConfiguration(title: "Downloads", x: 500, y: 520)
    let store = ResetPositionsConfigurationStore(loaded: [first, second])
    let useCase = ResetGlassPositionsUseCase(configurationStore: store)
    let firstPlacement = try GlassPlacement(x: 40, y: 600, displayHint: "Built-in Display")
    let secondPlacement = try GlassPlacement(x: 68, y: 572, displayHint: "Built-in Display")

    let result = try await useCase.execute(
        placements: [
            first.id: firstPlacement,
            second.id: secondPlacement,
        ]
    )

    #expect(result.map(\.placement) == [firstPlacement, secondPlacement])
    let saves = await store.savedValues()
    #expect(saves.count == 1)
    #expect(saves[0].map(\.placement) == [firstPlacement, secondPlacement])
    #expect(saves[0][0].source == first.source)
    #expect(saves[0][1].source == second.source)
}

@Test
func resetPositionsRejectsStaleWorkspaceWithoutWriting() async throws {
    let persisted = try resetPositionConfiguration(x: 100, y: 120)
    let store = ResetPositionsConfigurationStore(loaded: [persisted])
    let useCase = ResetGlassPositionsUseCase(configurationStore: store)

    do {
        _ = try await useCase.execute(
            placements: [
                GlassID(): try GlassPlacement(x: 40, y: 600),
            ]
        )
        Issue.record("Expected configurationChanged")
    } catch let error as ResetGlassPositionsError {
        #expect(error == .configurationChanged)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(await store.savedValues().isEmpty)
}

@Test
func resetPositionsWithNoChangesDoesNotCreateAnotherVersion() async throws {
    let persisted = try resetPositionConfiguration(x: 100, y: 120)
    let store = ResetPositionsConfigurationStore(loaded: [persisted])
    let useCase = ResetGlassPositionsUseCase(configurationStore: store)

    let result = try await useCase.execute(
        placements: [persisted.id: persisted.placement]
    )

    #expect(result == [persisted])
    #expect(await store.savedValues().isEmpty)
}

@Test
func resetPositionsSaveFailureDoesNotExposePartialPersistence() async throws {
    let first = try resetPositionConfiguration(title: "Projects", x: 100, y: 120)
    let second = try resetPositionConfiguration(title: "Downloads", x: 500, y: 520)
    let store = ResetPositionsConfigurationStore(
        loaded: [first, second],
        failSave: true
    )
    let useCase = ResetGlassPositionsUseCase(configurationStore: store)

    do {
        _ = try await useCase.execute(
            placements: [
                first.id: try GlassPlacement(x: 40, y: 600),
                second.id: try GlassPlacement(x: 68, y: 572),
            ]
        )
        Issue.record("Expected configurationSaveFailed")
    } catch let error as ResetGlassPositionsError {
        #expect(error == .configurationSaveFailed)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(await store.savedValues().isEmpty)
}

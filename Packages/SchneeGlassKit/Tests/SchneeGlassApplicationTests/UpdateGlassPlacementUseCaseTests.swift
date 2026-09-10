import Foundation
@testable import SchneeGlassApplication
import SchneeGlassDomain
import Testing

private enum PlacementStoreTestError: Error, Sendable {
    case injected
}

private actor PlacementConfigurationStore: ConditionalConfigurationPersisting {
    private let loaded: [GlassConfiguration]
    private let failLoad: Bool
    private let failSave: Bool
    private let rejectConditionalSave: Bool
    private var saved: [[GlassConfiguration]] = []

    init(
        loaded: [GlassConfiguration],
        failLoad: Bool = false,
        failSave: Bool = false,
        rejectConditionalSave: Bool = false
    ) {
        self.loaded = loaded
        self.failLoad = failLoad
        self.failSave = failSave
        self.rejectConditionalSave = rejectConditionalSave
    }

    func load() async throws -> [GlassConfiguration] {
        if failLoad { throw PlacementStoreTestError.injected }
        return loaded
    }

    func save(_ configurations: [GlassConfiguration]) async throws {
        if failSave { throw PlacementStoreTestError.injected }
        saved.append(configurations)
    }

    func save(
        _ configurations: [GlassConfiguration],
        ifCurrentMatches expectedCurrent: [GlassConfiguration]
    ) async throws -> Bool {
        if failSave { throw PlacementStoreTestError.injected }
        guard !rejectConditionalSave, expectedCurrent == loaded else {
            return false
        }
        saved.append(configurations)
        return true
    }

    func savedValues() -> [[GlassConfiguration]] { saved }
}

private func placementConfiguration(
    id: GlassID = GlassID(),
    x: Double = 100,
    y: Double = 120
) throws -> GlassConfiguration {
    try GlassConfiguration(
        id: id,
        title: "Projects",
        source: FolderSource(
            bookmarkData: Data([1]),
            lastKnownPath: "/tmp/Projects"
        ),
        placement: GlassPlacement(x: x, y: y),
        createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
}

@Test
func placementUpdateChangesOnlyTargetConfiguration() async throws {
    let targetID = GlassID()
    let target = try placementConfiguration(id: targetID)
    let other = try placementConfiguration(x: 500, y: 520)
    let store = PlacementConfigurationStore(loaded: [target, other])
    let useCase = UpdateGlassPlacementUseCase(configurationStore: store)
    let newPlacement = try GlassPlacement(x: 250, y: 280, width: 480, height: 360)

    let updated = try await useCase.execute(
        glassID: targetID,
        placement: newPlacement
    )

    #expect(updated)
    let saved = try #require(await store.savedValues().last)
    #expect(saved.count == 2)
    #expect(saved[0].id == targetID)
    #expect(saved[0].placement == newPlacement)
    #expect(saved[0].source == target.source)
    #expect(saved[1] == other)
}

@Test
func placementUpdateMissingGlassDoesNotWrite() async throws {
    let existing = try placementConfiguration()
    let store = PlacementConfigurationStore(loaded: [existing])
    let useCase = UpdateGlassPlacementUseCase(configurationStore: store)

    let updated = try await useCase.execute(
        glassID: GlassID(),
        placement: try GlassPlacement(x: 200, y: 200)
    )

    #expect(!updated)
    #expect(await store.savedValues().isEmpty)
}

@Test
func unchangedPlacementDoesNotWriteAnotherConfigurationVersion() async throws {
    let existing = try placementConfiguration()
    let store = PlacementConfigurationStore(loaded: [existing])
    let useCase = UpdateGlassPlacementUseCase(configurationStore: store)

    let updated = try await useCase.execute(
        glassID: existing.id,
        placement: existing.placement
    )

    #expect(updated)
    #expect(await store.savedValues().isEmpty)
}

@Test
func placementRejectsStaleConfigurationWithoutWriting() async throws {
    let existing = try placementConfiguration()
    let store = PlacementConfigurationStore(
        loaded: [existing],
        rejectConditionalSave: true
    )
    let useCase = UpdateGlassPlacementUseCase(configurationStore: store)

    do {
        _ = try await useCase.execute(
            glassID: existing.id,
            placement: try GlassPlacement(x: 700, y: 720)
        )
        Issue.record("Expected stale configuration rejection")
    } catch let error as UpdateGlassPlacementError {
        #expect(error == .configurationChanged)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(await store.savedValues().isEmpty)
}

@Test
func placementSaveFailureIsExplicit() async throws {
    let existing = try placementConfiguration()
    let store = PlacementConfigurationStore(loaded: [existing], failSave: true)
    let useCase = UpdateGlassPlacementUseCase(configurationStore: store)

    do {
        _ = try await useCase.execute(
            glassID: existing.id,
            placement: try GlassPlacement(x: 700, y: 720)
        )
        Issue.record("Expected placement save failure")
    } catch let error as UpdateGlassPlacementError {
        #expect(error == .configurationSaveFailed)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

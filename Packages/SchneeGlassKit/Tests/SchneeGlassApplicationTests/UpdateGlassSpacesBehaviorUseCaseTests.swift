import Foundation
import SchneeGlassDomain
import Testing

@testable import SchneeGlassApplication

private enum SpacesStoreTestError: Error, Sendable {
  case injected
}

private actor SpacesConfigurationStore: ConditionalConfigurationPersisting {
  private let loaded: [GlassConfiguration]
  private let failSave: Bool
  private let rejectConditionalSave: Bool
  private var saved: [[GlassConfiguration]] = []

  init(
    loaded: [GlassConfiguration],
    failSave: Bool = false,
    rejectConditionalSave: Bool = false
  ) {
    self.loaded = loaded
    self.failSave = failSave
    self.rejectConditionalSave = rejectConditionalSave
  }

  func load() async throws -> [GlassConfiguration] {
    loaded
  }

  func save(_ configurations: [GlassConfiguration]) async throws {
    if failSave {
      throw SpacesStoreTestError.injected
    }
    saved.append(configurations)
  }

  func save(
    _ configurations: [GlassConfiguration],
    ifCurrentMatches expectedCurrent: [GlassConfiguration]
  ) async throws -> Bool {
    if failSave {
      throw SpacesStoreTestError.injected
    }
    guard !rejectConditionalSave, expectedCurrent == loaded else {
      return false
    }
    saved.append(configurations)
    return true
  }

  func savedValues() -> [[GlassConfiguration]] {
    saved
  }
}

private func spacesConfiguration(
  id: GlassID = GlassID(),
  title: String = "Projects",
  showOnAllSpaces: Bool = false
) throws -> GlassConfiguration {
  try GlassConfiguration(
    id: id,
    title: title,
    source: FolderSource(
      bookmarkData: Data([1, 2, 3]),
      lastKnownPath: "/tmp/Projects"
    ),
    placement: GlassPlacement(x: 120, y: 140, width: 420, height: 300),
    showOnAllSpaces: showOnAllSpaces,
    createdAt: Date(timeIntervalSince1970: 1_700_000_000)
  )
}

@Test
func spacesBehaviorUpdateChangesOnlyTargetSetting() async throws {
  let targetID = GlassID()
  let target = try spacesConfiguration(id: targetID, showOnAllSpaces: false)
  let other = try spacesConfiguration(title: "Other", showOnAllSpaces: false)
  let store = SpacesConfigurationStore(loaded: [target, other])
  let useCase = UpdateGlassSpacesBehaviorUseCase(configurationStore: store)

  let updated = try await useCase.execute(
    glassID: targetID,
    showOnAllSpaces: true
  )

  #expect(updated)
  let saved = try #require(await store.savedValues().last)
  #expect(saved.count == 2)
  #expect(saved[0].showOnAllSpaces)
  #expect(saved[0].id == target.id)
  #expect(saved[0].title == target.title)
  #expect(saved[0].source == target.source)
  #expect(saved[0].placement == target.placement)
  #expect(saved[0].createdAt == target.createdAt)
  #expect(saved[1] == other)
}

@Test
func unchangedSpacesBehaviorDoesNotWrite() async throws {
  let existing = try spacesConfiguration(showOnAllSpaces: true)
  let store = SpacesConfigurationStore(loaded: [existing])
  let useCase = UpdateGlassSpacesBehaviorUseCase(configurationStore: store)

  let updated = try await useCase.execute(
    glassID: existing.id,
    showOnAllSpaces: true
  )

  #expect(updated)
  #expect(await store.savedValues().isEmpty)
}

@Test
func missingGlassSpacesBehaviorDoesNotWrite() async throws {
  let existing = try spacesConfiguration()
  let store = SpacesConfigurationStore(loaded: [existing])
  let useCase = UpdateGlassSpacesBehaviorUseCase(configurationStore: store)

  let updated = try await useCase.execute(
    glassID: GlassID(),
    showOnAllSpaces: true
  )

  #expect(!updated)
  #expect(await store.savedValues().isEmpty)
}

@Test
func staleSpacesBehaviorSaveIsRejected() async throws {
  let existing = try spacesConfiguration()
  let store = SpacesConfigurationStore(
    loaded: [existing],
    rejectConditionalSave: true
  )
  let useCase = UpdateGlassSpacesBehaviorUseCase(configurationStore: store)

  do {
    _ = try await useCase.execute(
      glassID: existing.id,
      showOnAllSpaces: true
    )
    Issue.record("Expected stale configuration rejection")
  } catch let error as UpdateGlassSpacesBehaviorError {
    #expect(error == .configurationChanged)
  }

  #expect(await store.savedValues().isEmpty)
}

@Test
func spacesBehaviorSaveFailureIsExplicit() async throws {
  let existing = try spacesConfiguration()
  let store = SpacesConfigurationStore(
    loaded: [existing],
    failSave: true
  )
  let useCase = UpdateGlassSpacesBehaviorUseCase(configurationStore: store)

  do {
    _ = try await useCase.execute(
      glassID: existing.id,
      showOnAllSpaces: true
    )
    Issue.record("Expected save failure")
  } catch let error as UpdateGlassSpacesBehaviorError {
    #expect(error == .configurationSaveFailed)
  }

  #expect(await store.savedValues().isEmpty)
}

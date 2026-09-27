import Foundation
import SchneeGlassDomain
import Testing

@testable import SchneeGlassApplication

private enum TitleStoreTestError: Error, Sendable {
  case injected
}

private actor TitleConfigurationStore: ConditionalConfigurationPersisting {
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
      throw TitleStoreTestError.injected
    }
    saved.append(configurations)
  }

  func save(
    _ configurations: [GlassConfiguration],
    ifCurrentMatches expectedCurrent: [GlassConfiguration]
  ) async throws -> Bool {
    if failSave {
      throw TitleStoreTestError.injected
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

private func titleConfiguration(
  id: GlassID = GlassID(),
  title: String = "Projects"
) throws -> GlassConfiguration {
  try GlassConfiguration(
    id: id,
    title: title,
    source: FolderSource(
      bookmarkData: Data([1]),
      lastKnownPath: "/tmp/Projects"
    ),
    placement: GlassPlacement(x: 100, y: 120),
    showOnAllSpaces: true,
    createdAt: Date(timeIntervalSince1970: 1_700_000_000)
  )
}

@Test
func titleUpdateChangesOnlyTargetTitleAndNormalizesWhitespace() async throws {
  let targetID = GlassID()
  let target = try titleConfiguration(id: targetID)
  let other = try titleConfiguration(title: "Other")
  let store = TitleConfigurationStore(loaded: [target, other])
  let useCase = UpdateGlassTitleUseCase(configurationStore: store)

  let updated = try await useCase.execute(
    glassID: targetID,
    title: "  Renamed Projects  "
  )

  #expect(updated)
  let saved = try #require(await store.savedValues().last)
  #expect(saved.count == 2)
  #expect(saved[0].title == "Renamed Projects")
  #expect(saved[0].id == target.id)
  #expect(saved[0].source == target.source)
  #expect(saved[0].placement == target.placement)
  #expect(saved[0].showOnAllSpaces == target.showOnAllSpaces)
  #expect(saved[0].createdAt == target.createdAt)
  #expect(saved[1] == other)
}

@Test
func unchangedNormalizedTitleDoesNotWrite() async throws {
  let existing = try titleConfiguration(title: "Projects")
  let store = TitleConfigurationStore(loaded: [existing])
  let useCase = UpdateGlassTitleUseCase(configurationStore: store)

  let updated = try await useCase.execute(
    glassID: existing.id,
    title: "  Projects\n"
  )

  #expect(updated)
  #expect(await store.savedValues().isEmpty)
}

@Test
func missingGlassDoesNotWrite() async throws {
  let existing = try titleConfiguration()
  let store = TitleConfigurationStore(loaded: [existing])
  let useCase = UpdateGlassTitleUseCase(configurationStore: store)

  let updated = try await useCase.execute(
    glassID: GlassID(),
    title: "Renamed"
  )

  #expect(!updated)
  #expect(await store.savedValues().isEmpty)
}

@Test
func emptyTitleIsRejectedWithoutWrite() async throws {
  let existing = try titleConfiguration()
  let store = TitleConfigurationStore(loaded: [existing])
  let useCase = UpdateGlassTitleUseCase(configurationStore: store)

  do {
    _ = try await useCase.execute(glassID: existing.id, title: "   \n")
    Issue.record("Expected empty title rejection")
  } catch let error as UpdateGlassTitleError {
    #expect(error == .emptyTitle)
  }

  #expect(await store.savedValues().isEmpty)
}

@Test
func overlongTitleIsRejectedWithoutWrite() async throws {
  let existing = try titleConfiguration()
  let store = TitleConfigurationStore(loaded: [existing])
  let useCase = UpdateGlassTitleUseCase(configurationStore: store)

  do {
    _ = try await useCase.execute(
      glassID: existing.id,
      title: String(repeating: "a", count: 101)
    )
    Issue.record("Expected title length rejection")
  } catch let error as UpdateGlassTitleError {
    #expect(error == .titleTooLong)
  }

  #expect(await store.savedValues().isEmpty)
}

@Test
func staleConfigurationSaveIsRejected() async throws {
  let existing = try titleConfiguration()
  let store = TitleConfigurationStore(
    loaded: [existing],
    rejectConditionalSave: true
  )
  let useCase = UpdateGlassTitleUseCase(configurationStore: store)

  do {
    _ = try await useCase.execute(
      glassID: existing.id,
      title: "Renamed"
    )
    Issue.record("Expected stale configuration rejection")
  } catch let error as UpdateGlassTitleError {
    #expect(error == .configurationChanged)
  }

  #expect(await store.savedValues().isEmpty)
}

@Test
func configurationSaveFailureIsExplicit() async throws {
  let existing = try titleConfiguration()
  let store = TitleConfigurationStore(
    loaded: [existing],
    failSave: true
  )
  let useCase = UpdateGlassTitleUseCase(configurationStore: store)

  do {
    _ = try await useCase.execute(
      glassID: existing.id,
      title: "Renamed"
    )
    Issue.record("Expected save failure")
  } catch let error as UpdateGlassTitleError {
    #expect(error == .configurationSaveFailed)
  }

  #expect(await store.savedValues().isEmpty)
}

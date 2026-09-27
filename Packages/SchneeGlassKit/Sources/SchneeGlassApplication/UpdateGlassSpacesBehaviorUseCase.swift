import SchneeGlassDomain

public enum UpdateGlassSpacesBehaviorError: Error, Hashable, Sendable {
  case configurationLoadFailed
  case configurationChanged
  case invalidConfiguration
  case configurationSaveFailed
}

public actor UpdateGlassSpacesBehaviorUseCase {
  private let configurationStore: any ConditionalConfigurationPersisting

  public init(configurationStore: any ConditionalConfigurationPersisting) {
    self.configurationStore = configurationStore
  }

  @discardableResult
  public func execute(
    glassID: GlassID,
    showOnAllSpaces: Bool
  ) async throws -> Bool {
    var configurations: [GlassConfiguration]
    do {
      configurations = try await configurationStore.load()
    } catch {
      throw UpdateGlassSpacesBehaviorError.configurationLoadFailed
    }
    let expectedCurrent = configurations

    guard let index = configurations.firstIndex(where: { $0.id == glassID }) else {
      return false
    }

    let current = configurations[index]
    guard current.showOnAllSpaces != showOnAllSpaces else {
      return true
    }

    let updated: GlassConfiguration
    do {
      updated = try GlassConfiguration(
        id: current.id,
        title: current.title,
        source: current.source,
        placement: current.placement,
        showOnAllSpaces: showOnAllSpaces,
        createdAt: current.createdAt
      )
    } catch {
      throw UpdateGlassSpacesBehaviorError.invalidConfiguration
    }

    configurations[index] = updated
    do {
      guard
        try await configurationStore.save(
          configurations,
          ifCurrentMatches: expectedCurrent
        )
      else {
        throw UpdateGlassSpacesBehaviorError.configurationChanged
      }
    } catch let error as UpdateGlassSpacesBehaviorError {
      throw error
    } catch {
      throw UpdateGlassSpacesBehaviorError.configurationSaveFailed
    }

    return true
  }
}

import SchneeGlassDomain

public enum UpdateGlassTitleError: Error, Hashable, Sendable {
  case configurationLoadFailed
  case configurationChanged
  case emptyTitle
  case titleTooLong
  case invalidConfiguration
  case configurationSaveFailed
}

public actor UpdateGlassTitleUseCase {
  private let configurationStore: any ConditionalConfigurationPersisting

  public init(configurationStore: any ConditionalConfigurationPersisting) {
    self.configurationStore = configurationStore
  }

  @discardableResult
  public func execute(
    glassID: GlassID,
    title: String
  ) async throws -> Bool {
    try Task.checkCancellation()

    var configurations: [GlassConfiguration]
    do {
      configurations = try await configurationStore.load()
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw UpdateGlassTitleError.configurationLoadFailed
    }

    try Task.checkCancellation()
    let expectedCurrent = configurations

    guard let index = configurations.firstIndex(where: { $0.id == glassID }) else {
      return false
    }

    let current = configurations[index]
    let updated: GlassConfiguration
    do {
      updated = try GlassConfiguration(
        id: current.id,
        title: title,
        source: current.source,
        placement: current.placement,
        showOnAllSpaces: current.showOnAllSpaces,
        createdAt: current.createdAt
      )
    } catch let error as GlassConfigurationValidationError {
      switch error {
      case .emptyTitle:
        throw UpdateGlassTitleError.emptyTitle
      case .titleTooLong:
        throw UpdateGlassTitleError.titleTooLong
      }
    } catch {
      throw UpdateGlassTitleError.invalidConfiguration
    }

    guard updated != current else {
      return true
    }

    configurations[index] = updated
    try Task.checkCancellation()

    do {
      guard
        try await configurationStore.save(
          configurations,
          ifCurrentMatches: expectedCurrent
        )
      else {
        throw UpdateGlassTitleError.configurationChanged
      }
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as UpdateGlassTitleError {
      throw error
    } catch {
      throw UpdateGlassTitleError.configurationSaveFailed
    }

    return true
  }
}

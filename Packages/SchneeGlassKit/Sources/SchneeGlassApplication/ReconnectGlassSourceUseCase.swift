import FileDomain
import Foundation
import SchneeGlassDomain

public enum ReconnectGlassSourceError: Error, Hashable, Sendable {
  case configurationLoadFailed
  case configurationMissing
  case sourceCreationFailed
  case selectedSourceIdentityUnavailable
  case selectedSourceMismatch
  case folderAccess(FolderAccessError)
  case eventStreamFailed
  case snapshotFailed
  case invalidConfiguration
  case staleConfiguration
  case configurationSaveFailed
}

public actor ReconnectGlassSourceUseCase {
  private let configurationStore: any ConditionalConfigurationPersisting
  private let folderSelector: any FolderSelecting
  private let sourceCreator: any FolderSourceCreating
  private let accessController: any FolderAccessControlling
  private let eventStreaming: any FileEventStreaming
  private let snapshotReader: any FolderSnapshotReading

  public init(
    configurationStore: any ConditionalConfigurationPersisting,
    folderSelector: any FolderSelecting,
    sourceCreator: any FolderSourceCreating,
    accessController: any FolderAccessControlling,
    eventStreaming: any FileEventStreaming,
    snapshotReader: any FolderSnapshotReading
  ) {
    self.configurationStore = configurationStore
    self.folderSelector = folderSelector
    self.sourceCreator = sourceCreator
    self.accessController = accessController
    self.eventStreaming = eventStreaming
    self.snapshotReader = snapshotReader
  }

  /// Reconnects one Glass to the same physical folder and returns a prepared runtime seed.
  ///
  /// Returns `nil` when the user cancels folder selection. The saved configuration is updated only
  /// after the selected folder has passed persistent identity validation, access acquisition,
  /// event-stream subscription, and initial snapshot creation.
  public func execute(glassID: GlassID) async throws -> CreatedGlassRuntimeSeed? {
    let preflight = try await loadConfiguration(glassID: glassID)

    guard let selectedURL = await folderSelector.selectFolder() else {
      return nil
    }

    let selectedSource: FolderSource
    do {
      selectedSource = try await sourceCreator.createSource(for: selectedURL)
    } catch let error as FolderSourceCreationError {
      switch error {
      case .bookmarkCreationFailed:
        throw ReconnectGlassSourceError.sourceCreationFailed
      case .resourceIdentityUnavailable:
        throw ReconnectGlassSourceError.selectedSourceIdentityUnavailable
      }
    } catch {
      throw ReconnectGlassSourceError.sourceCreationFailed
    }

    try Self.validatePersistentIdentity(
      expected: preflight.source.persistentIdentity,
      selected: selectedSource.persistentIdentity
    )

    let acquisition: FolderAccessAcquisition
    do {
      acquisition = try await accessController.acquire(
        source: selectedSource,
        glassID: glassID
      )
    } catch let error as FolderAccessError {
      throw ReconnectGlassSourceError.folderAccess(error)
    } catch {
      throw ReconnectGlassSourceError.folderAccess(.accessDenied)
    }

    let persistedSource = acquisition.refreshedSource ?? selectedSource
    do {
      try Self.validatePersistentIdentity(
        expected: preflight.source.persistentIdentity,
        selected: persistedSource.persistentIdentity
      )
    } catch {
      await accessController.release(handleID: acquisition.handle.id)
      throw error
    }

    let subscription: FileEventSubscription
    do {
      subscription = try await eventStreaming.subscribe(for: acquisition.handle)
    } catch {
      await accessController.release(handleID: acquisition.handle.id)
      throw ReconnectGlassSourceError.eventStreamFailed
    }

    let snapshot: FolderSnapshot
    do {
      snapshot = try await snapshotReader.snapshot(
        for: acquisition.handle,
        generation: 1
      )
    } catch {
      await eventStreaming.stop(subscriptionID: subscription.id)
      await accessController.release(handleID: acquisition.handle.id)
      throw ReconnectGlassSourceError.snapshotFailed
    }

    let updatedConfiguration: GlassConfiguration
    do {
      updatedConfiguration = try GlassConfiguration(
        id: preflight.id,
        title: preflight.title,
        source: persistedSource,
        placement: preflight.placement,
        showOnAllSpaces: preflight.showOnAllSpaces,
        createdAt: preflight.createdAt
      )
    } catch {
      await cleanup(subscription: subscription, access: acquisition.handle)
      throw ReconnectGlassSourceError.invalidConfiguration
    }

    do {
      try await commit(
        preflight: preflight,
        updatedConfiguration: updatedConfiguration
      )
    } catch {
      await cleanup(subscription: subscription, access: acquisition.handle)
      throw error
    }

    return CreatedGlassRuntimeSeed(
      configuration: updatedConfiguration,
      access: acquisition.handle,
      snapshot: snapshot,
      eventSubscription: subscription
    )
  }

  private func loadConfiguration(glassID: GlassID) async throws -> GlassConfiguration {
    let configurations: [GlassConfiguration]
    do {
      configurations = try await configurationStore.load()
    } catch {
      throw ReconnectGlassSourceError.configurationLoadFailed
    }

    guard let configuration = configurations.first(where: { $0.id == glassID }) else {
      throw ReconnectGlassSourceError.configurationMissing
    }
    return configuration
  }

  private func commit(
    preflight: GlassConfiguration,
    updatedConfiguration: GlassConfiguration
  ) async throws {
    let configurations: [GlassConfiguration]
    do {
      configurations = try await configurationStore.load()
    } catch {
      throw ReconnectGlassSourceError.configurationLoadFailed
    }

    guard let index = configurations.firstIndex(where: { $0.id == preflight.id }),
      configurations[index] == preflight
    else {
      throw ReconnectGlassSourceError.staleConfiguration
    }

    var updated = configurations
    updated[index] = updatedConfiguration

    do {
      guard try await configurationStore.save(
        updated,
        ifCurrentMatches: configurations
      ) else {
        throw ReconnectGlassSourceError.staleConfiguration
      }
    } catch let error as ReconnectGlassSourceError {
      throw error
    } catch {
      throw ReconnectGlassSourceError.configurationSaveFailed
    }
  }

  private func cleanup(
    subscription: FileEventSubscription,
    access: FolderAccessHandle
  ) async {
    await eventStreaming.stop(subscriptionID: subscription.id)
    await accessController.release(handleID: access.id)
  }

  private static func validatePersistentIdentity(
    expected: PersistentFolderIdentity?,
    selected: PersistentFolderIdentity?
  ) throws {
    guard let expected,
      let selected,
      let expectedVolume = expected.volumeUUIDString,
      let selectedVolume = selected.volumeUUIDString,
      let expectedDocument = expected.documentIdentifier,
      let selectedDocument = selected.documentIdentifier
    else {
      throw ReconnectGlassSourceError.selectedSourceIdentityUnavailable
    }

    guard expectedVolume == selectedVolume,
      expectedDocument == selectedDocument
    else {
      throw ReconnectGlassSourceError.selectedSourceMismatch
    }
  }
}

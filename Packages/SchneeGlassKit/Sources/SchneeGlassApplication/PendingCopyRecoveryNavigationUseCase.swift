import Foundation
import SchneeGlassDomain

public enum PendingCopyRecoveryNavigationError: Error, Hashable, Sendable {
  case unsupportedAction
  case recordsLoadFailed
  case configurationLoadFailed
  case recordMissing
  case configurationMissing
  case destinationUnavailable
  case actionNoLongerAvailable
}

/// Executes read-only manual-inspection actions for Pending Copy Recovery.
///
/// The caller supplies only an operation ID and requested reveal action. This use case reloads the
/// recovery record and current Glass configuration, reacquires destination access, performs a fresh
/// filesystem assessment, and only then asks macOS to reveal the item. UI-held paths and stale
/// assessments are never treated as authority.
public actor PendingCopyRecoveryNavigationUseCase {
  private let pendingCopyStore: any PendingCopyRecording
  private let configurationStore: any ConfigurationPersisting
  private let accessController: any FolderAccessControlling
  private let recoveryInspector: any PendingCopyRecoveryInspecting
  private let fileActor: any WorkspaceFileActing

  public init(
    pendingCopyStore: any PendingCopyRecording,
    configurationStore: any ConfigurationPersisting,
    accessController: any FolderAccessControlling,
    recoveryInspector: any PendingCopyRecoveryInspecting,
    fileActor: any WorkspaceFileActing
  ) {
    self.pendingCopyStore = pendingCopyStore
    self.configurationStore = configurationStore
    self.accessController = accessController
    self.recoveryInspector = recoveryInspector
    self.fileActor = fileActor
  }

  public func reveal(
    action: PendingCopyRecoveryAction,
    operationID: UUID
  ) async throws {
    try Task.checkCancellation()

    guard action == .revealStaging || action == .revealFinal else {
      throw PendingCopyRecoveryNavigationError.unsupportedAction
    }

    let records: [PendingCopyRecord]
    do {
      records = try await pendingCopyStore.records()
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw PendingCopyRecoveryNavigationError.recordsLoadFailed
    }
    try Task.checkCancellation()

    guard let record = records.first(where: { $0.operationID == operationID }) else {
      throw PendingCopyRecoveryNavigationError.recordMissing
    }

    let configurations: [GlassConfiguration]
    do {
      configurations = try await configurationStore.load()
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw PendingCopyRecoveryNavigationError.configurationLoadFailed
    }
    try Task.checkCancellation()

    guard
      let configuration = configurations.first(where: { $0.id == record.destinationGlassID })
    else {
      throw PendingCopyRecoveryNavigationError.configurationMissing
    }

    let acquisition: FolderAccessAcquisition
    do {
      acquisition = try await accessController.acquire(
        source: configuration.source,
        glassID: configuration.id
      )
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw PendingCopyRecoveryNavigationError.destinationUnavailable
    }

    do {
      try Task.checkCancellation()

      let assessment = await recoveryInspector.assess(
        record,
        destinationAccess: acquisition.handle
      )
      try Task.checkCancellation()

      let freshActions = PendingCopyRecoveryActionPlanner.plan(for: assessment).actions
      guard freshActions.contains(action) else {
        throw PendingCopyRecoveryNavigationError.actionNoLongerAvailable
      }

      let filename: String
      switch action {
      case .revealStaging:
        filename = record.stagingFilename
      case .revealFinal:
        filename = record.finalFilename
      case .discardMetadata, .removeOwnedStaging, .reconnectDestination:
        throw PendingCopyRecoveryNavigationError.unsupportedAction
      }

      let revealAssessment = await recoveryInspector.assess(
        record,
        destinationAccess: acquisition.handle
      )
      try Task.checkCancellation()

      let revealActions = PendingCopyRecoveryActionPlanner.plan(for: revealAssessment).actions
      guard revealActions.contains(action) else {
        throw PendingCopyRecoveryNavigationError.actionNoLongerAvailable
      }

      let url =
        acquisition.handle.url
        .appendingPathComponent(filename, isDirectory: false)
        .standardizedFileURL

      try Task.checkCancellation()
      await fileActor.reveal(url: url)
      await accessController.release(handleID: acquisition.handle.id)
    } catch {
      await accessController.release(handleID: acquisition.handle.id)
      throw error
    }
  }
}

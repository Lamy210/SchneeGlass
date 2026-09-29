import Foundation
import SchneeGlassDomain

public enum PendingCopyRecoveryCenterItemState: Hashable, Sendable {
  case assessed(PendingCopyRecoveryDisposition)
  case destinationUnavailable
  case configurationMissing
}

public struct PendingCopyRecoveryCenterItem: Hashable, Sendable, Identifiable {
  public var id: UUID { record.operationID }

  public let record: PendingCopyRecord
  public let glassTitle: String?
  public let state: PendingCopyRecoveryCenterItemState
  public let actions: [PendingCopyRecoveryAction]

  public init(
    record: PendingCopyRecord,
    glassTitle: String?,
    state: PendingCopyRecoveryCenterItemState,
    actions: [PendingCopyRecoveryAction]
  ) {
    self.record = record
    self.glassTitle = glassTitle
    self.state = state
    self.actions = actions
  }
}

public enum PendingCopyRecoveryCenterError: Error, Hashable, Sendable {
  case recordsLoadFailed
  case configurationLoadFailed
  case recordMissing
  case configurationMissing
  case destinationUnavailable
  case copyInProgress
  case recoveryInProgress
  case mutationFailed
}

public actor PendingCopyRecoveryCenterUseCase {
  private let pendingCopyStore: any PendingCopyRecording
  private let configurationStore: any ConfigurationPersisting
  private let accessController: any FolderAccessControlling
  private let recoveryInspector: any PendingCopyRecoveryInspecting
  private let recoveryExecution: PendingCopyRecoveryExecutionUseCase
  private let activityGate: FileOperationActivityGate

  public init(
    pendingCopyStore: any PendingCopyRecording,
    configurationStore: any ConfigurationPersisting,
    accessController: any FolderAccessControlling,
    recoveryInspector: any PendingCopyRecoveryInspecting,
    recoveryExecution: PendingCopyRecoveryExecutionUseCase,
    activityGate: FileOperationActivityGate
  ) {
    self.pendingCopyStore = pendingCopyStore
    self.configurationStore = configurationStore
    self.accessController = accessController
    self.recoveryInspector = recoveryInspector
    self.recoveryExecution = recoveryExecution
    self.activityGate = activityGate
  }

  public func loadItems() async throws -> [PendingCopyRecoveryCenterItem] {
    try Task.checkCancellation()

    if await activityGate.hasActiveCopies() {
      throw PendingCopyRecoveryCenterError.copyInProgress
    }
    try Task.checkCancellation()

    if await activityGate.hasActiveRecoveryMutation() {
      throw PendingCopyRecoveryCenterError.recoveryInProgress
    }
    try Task.checkCancellation()

    let records: [PendingCopyRecord]
    do {
      records = try await pendingCopyStore.records()
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw PendingCopyRecoveryCenterError.recordsLoadFailed
    }
    try Task.checkCancellation()

    guard !records.isEmpty else { return [] }

    let configurations: [GlassConfiguration]
    do {
      configurations = try await configurationStore.load()
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw PendingCopyRecoveryCenterError.configurationLoadFailed
    }
    try Task.checkCancellation()

    let byGlassID = Dictionary(uniqueKeysWithValues: configurations.map { ($0.id, $0) })
    var items: [PendingCopyRecoveryCenterItem] = []
    items.reserveCapacity(records.count)

    for record in records.sorted(by: Self.recoveryRecordOrder) {
      try Task.checkCancellation()

      guard let configuration = byGlassID[record.destinationGlassID] else {
        items.append(
          PendingCopyRecoveryCenterItem(
            record: record,
            glassTitle: nil,
            state: .configurationMissing,
            actions: []
          )
        )
        continue
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
        items.append(
          PendingCopyRecoveryCenterItem(
            record: record,
            glassTitle: configuration.title,
            state: .destinationUnavailable,
            actions: [.reconnectDestination]
          )
        )
        continue
      }

      do {
        try Task.checkCancellation()
      } catch {
        await accessController.release(handleID: acquisition.handle.id)
        throw error
      }

      let assessment = await recoveryInspector.assess(
        record,
        destinationAccess: acquisition.handle
      )
      await accessController.release(handleID: acquisition.handle.id)
      try Task.checkCancellation()

      items.append(
        PendingCopyRecoveryCenterItem(
          record: record,
          glassTitle: configuration.title,
          state: .assessed(assessment.disposition),
          actions: PendingCopyRecoveryActionPlanner.plan(for: assessment).actions
        )
      )
    }

    return items
  }

  public func executeMutation(
    action: PendingCopyRecoveryAction,
    operationID: UUID
  ) async throws {
    try Task.checkCancellation()

    switch await activityGate.beginRecoveryMutation() {
    case .granted:
      break
    case .copyInProgress:
      throw PendingCopyRecoveryCenterError.copyInProgress
    case .recoveryInProgress:
      throw PendingCopyRecoveryCenterError.recoveryInProgress
    }

    do {
      try Task.checkCancellation()
      try await executeMutationWithLease(action: action, operationID: operationID)
      await activityGate.endRecoveryMutation()
    } catch {
      await activityGate.endRecoveryMutation()
      throw error
    }
  }

  private func executeMutationWithLease(
    action: PendingCopyRecoveryAction,
    operationID: UUID
  ) async throws {
    let records: [PendingCopyRecord]
    do {
      records = try await pendingCopyStore.records()
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw PendingCopyRecoveryCenterError.recordsLoadFailed
    }
    try Task.checkCancellation()

    guard let record = records.first(where: { $0.operationID == operationID }) else {
      throw PendingCopyRecoveryCenterError.recordMissing
    }

    let configurations: [GlassConfiguration]
    do {
      configurations = try await configurationStore.load()
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw PendingCopyRecoveryCenterError.configurationLoadFailed
    }
    try Task.checkCancellation()

    guard
      let configuration = configurations.first(where: { $0.id == record.destinationGlassID })
    else {
      throw PendingCopyRecoveryCenterError.configurationMissing
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
      throw PendingCopyRecoveryCenterError.destinationUnavailable
    }

    do {
      try Task.checkCancellation()
    } catch {
      await accessController.release(handleID: acquisition.handle.id)
      throw error
    }

    do {
      try await recoveryExecution.execute(
        action: action,
        record: record,
        destinationAccess: acquisition.handle
      )
      await accessController.release(handleID: acquisition.handle.id)
    } catch is CancellationError {
      await accessController.release(handleID: acquisition.handle.id)
      throw CancellationError()
    } catch {
      await accessController.release(handleID: acquisition.handle.id)
      throw PendingCopyRecoveryCenterError.mutationFailed
    }
  }

  private static func recoveryRecordOrder(
    _ lhs: PendingCopyRecord,
    _ rhs: PendingCopyRecord
  ) -> Bool {
    if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
    return lhs.operationID.uuidString < rhs.operationID.uuidString
  }
}

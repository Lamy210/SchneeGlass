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
    case mutationFailed
}

public actor PendingCopyRecoveryCenterUseCase {
    private let pendingCopyStore: any PendingCopyRecording
    private let configurationStore: any ConfigurationPersisting
    private let accessController: any FolderAccessControlling
    private let recoveryInspector: any PendingCopyRecoveryInspecting
    private let recoveryExecution: PendingCopyRecoveryExecutionUseCase

    public init(
        pendingCopyStore: any PendingCopyRecording,
        configurationStore: any ConfigurationPersisting,
        accessController: any FolderAccessControlling,
        recoveryInspector: any PendingCopyRecoveryInspecting,
        recoveryExecution: PendingCopyRecoveryExecutionUseCase
    ) {
        self.pendingCopyStore = pendingCopyStore
        self.configurationStore = configurationStore
        self.accessController = accessController
        self.recoveryInspector = recoveryInspector
        self.recoveryExecution = recoveryExecution
    }

    public func loadItems() async throws -> [PendingCopyRecoveryCenterItem] {
        let records: [PendingCopyRecord]
        do {
            records = try await pendingCopyStore.records()
        } catch {
            throw PendingCopyRecoveryCenterError.recordsLoadFailed
        }

        guard !records.isEmpty else { return [] }

        let configurations: [GlassConfiguration]
        do {
            configurations = try await configurationStore.load()
        } catch {
            throw PendingCopyRecoveryCenterError.configurationLoadFailed
        }

        let byGlassID = Dictionary(uniqueKeysWithValues: configurations.map { ($0.id, $0) })
        var items: [PendingCopyRecoveryCenterItem] = []
        items.reserveCapacity(records.count)

        for record in records.sorted(by: Self.recoveryRecordOrder) {
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

            let assessment = await recoveryInspector.assess(
                record,
                destinationAccess: acquisition.handle
            )
            await accessController.release(handleID: acquisition.handle.id)

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
        let records: [PendingCopyRecord]
        do {
            records = try await pendingCopyStore.records()
        } catch {
            throw PendingCopyRecoveryCenterError.recordsLoadFailed
        }
        guard let record = records.first(where: { $0.operationID == operationID }) else {
            throw PendingCopyRecoveryCenterError.recordMissing
        }

        let configurations: [GlassConfiguration]
        do {
            configurations = try await configurationStore.load()
        } catch {
            throw PendingCopyRecoveryCenterError.configurationLoadFailed
        }
        guard let configuration = configurations.first(where: { $0.id == record.destinationGlassID }) else {
            throw PendingCopyRecoveryCenterError.configurationMissing
        }

        let acquisition: FolderAccessAcquisition
        do {
            acquisition = try await accessController.acquire(
                source: configuration.source,
                glassID: configuration.id
            )
        } catch {
            throw PendingCopyRecoveryCenterError.destinationUnavailable
        }

        do {
            try await recoveryExecution.execute(
                action: action,
                record: record,
                destinationAccess: acquisition.handle
            )
            await accessController.release(handleID: acquisition.handle.id)
        } catch {
            await accessController.release(handleID: acquisition.handle.id)
            throw PendingCopyRecoveryCenterError.mutationFailed
        }
    }

    private static func recoveryRecordOrder(_ lhs: PendingCopyRecord, _ rhs: PendingCopyRecord) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        return lhs.operationID.uuidString < rhs.operationID.uuidString
    }
}

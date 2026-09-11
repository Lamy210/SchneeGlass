import Foundation
import SchneeGlassDomain

public enum PendingCopyDestinationReconnectError: Error, Hashable, Sendable {
    case recordsLoadFailed
    case configurationLoadFailed
    case recordMissing
    case configurationMissing
    case sourceCreationFailed
    case selectedDestinationIdentityUnavailable
    case selectedDestinationMismatch
    case selectedDestinationAccessFailed
    case staleRecoveryState
    case copyInProgress
    case recoveryInProgress
    case invalidConfiguration
    case configurationSaveFailed
}

/// Reconnects the destination Glass for a pending-copy recovery record.
///
/// Folder selection happens before the Recovery mutation lease is acquired so a modal picker does
/// not block normal copy work. After selection, the record and Glass configuration are reloaded and
/// must still exactly match the preflight state before any configuration write is attempted.
public actor PendingCopyDestinationReconnectUseCase {
    private let pendingCopyStore: any PendingCopyRecording
    private let configurationStore: any ConditionalConfigurationPersisting
    private let folderSelector: any FolderSelecting
    private let sourceCreator: any FolderSourceCreating
    private let accessController: any FolderAccessControlling
    private let activityGate: FileOperationActivityGate

    public init(
        pendingCopyStore: any PendingCopyRecording,
        configurationStore: any ConditionalConfigurationPersisting,
        folderSelector: any FolderSelecting,
        sourceCreator: any FolderSourceCreating,
        accessController: any FolderAccessControlling,
        activityGate: FileOperationActivityGate
    ) {
        self.pendingCopyStore = pendingCopyStore
        self.configurationStore = configurationStore
        self.folderSelector = folderSelector
        self.sourceCreator = sourceCreator
        self.accessController = accessController
        self.activityGate = activityGate
    }

    /// Returns `false` when the user cancels folder selection.
    public func execute(operationID: UUID) async throws -> Bool {
        let preflight = try await loadCurrentState(operationID: operationID)

        guard let selectedURL = await folderSelector.selectFolder() else {
            return false
        }

        let selectedSource: FolderSource
        do {
            selectedSource = try await sourceCreator.createSource(for: selectedURL)
        } catch {
            throw PendingCopyDestinationReconnectError.sourceCreationFailed
        }

        try Self.validateSelectedIdentity(
            expected: preflight.configuration.source.fingerprint,
            selected: selectedSource.fingerprint
        )

        switch await activityGate.beginRecoveryMutation() {
        case .granted:
            break
        case .copyInProgress:
            throw PendingCopyDestinationReconnectError.copyInProgress
        case .recoveryInProgress:
            throw PendingCopyDestinationReconnectError.recoveryInProgress
        }

        do {
            let result = try await commitReconnect(
                operationID: operationID,
                preflight: preflight,
                selectedSource: selectedSource
            )
            await activityGate.endRecoveryMutation()
            return result
        } catch {
            await activityGate.endRecoveryMutation()
            throw error
        }
    }

    private struct CurrentState: Sendable {
        let record: PendingCopyRecord
        let configuration: GlassConfiguration
    }

    private func loadCurrentState(operationID: UUID) async throws -> CurrentState {
        let records: [PendingCopyRecord]
        do {
            records = try await pendingCopyStore.records()
        } catch {
            throw PendingCopyDestinationReconnectError.recordsLoadFailed
        }
        guard let record = records.first(where: { $0.operationID == operationID }) else {
            throw PendingCopyDestinationReconnectError.recordMissing
        }

        let configurations: [GlassConfiguration]
        do {
            configurations = try await configurationStore.load()
        } catch {
            throw PendingCopyDestinationReconnectError.configurationLoadFailed
        }
        guard let configuration = configurations.first(where: { $0.id == record.destinationGlassID }) else {
            throw PendingCopyDestinationReconnectError.configurationMissing
        }

        return CurrentState(record: record, configuration: configuration)
    }

    private func commitReconnect(
        operationID: UUID,
        preflight: CurrentState,
        selectedSource: FolderSource
    ) async throws -> Bool {
        let current = try await loadCurrentState(operationID: operationID)
        guard current.record == preflight.record,
              current.configuration == preflight.configuration
        else {
            throw PendingCopyDestinationReconnectError.staleRecoveryState
        }

        try Self.validateSelectedIdentity(
            expected: current.configuration.source.fingerprint,
            selected: selectedSource.fingerprint
        )

        let validationAccess: FolderAccessAcquisition
        do {
            validationAccess = try await accessController.acquire(
                source: selectedSource,
                glassID: current.configuration.id
            )
        } catch {
            throw PendingCopyDestinationReconnectError.selectedDestinationAccessFailed
        }

        let persistedSource = validationAccess.refreshedSource ?? selectedSource
        let observedFingerprint = validationAccess.handle.fingerprint
        await accessController.release(handleID: validationAccess.handle.id)

        // The folder selected before the Recovery lease was acquired must still resolve to the exact
        // same directory when access is established. A volume identifier alone cannot distinguish
        // two directories on one volume, so reconnect authority requires the directory resource ID.
        try Self.validateSelectedIdentity(
            expected: current.configuration.source.fingerprint,
            selected: observedFingerprint
        )
        try Self.validateSelectedIdentity(
            expected: current.configuration.source.fingerprint,
            selected: persistedSource.fingerprint
        )

        let updatedConfiguration: GlassConfiguration
        do {
            updatedConfiguration = try GlassConfiguration(
                id: current.configuration.id,
                title: current.configuration.title,
                source: persistedSource,
                placement: current.configuration.placement,
                showOnAllSpaces: current.configuration.showOnAllSpaces,
                createdAt: current.configuration.createdAt
            )
        } catch {
            throw PendingCopyDestinationReconnectError.invalidConfiguration
        }

        let configurations: [GlassConfiguration]
        do {
            configurations = try await configurationStore.load()
        } catch {
            throw PendingCopyDestinationReconnectError.configurationLoadFailed
        }

        guard let index = configurations.firstIndex(where: { $0.id == current.configuration.id }),
              configurations[index] == current.configuration
        else {
            throw PendingCopyDestinationReconnectError.staleRecoveryState
        }

        var updated = configurations
        updated[index] = updatedConfiguration

        do {
            guard try await configurationStore.save(
                updated,
                ifCurrentMatches: configurations
            ) else {
                throw PendingCopyDestinationReconnectError.staleRecoveryState
            }
        } catch let error as PendingCopyDestinationReconnectError {
            throw error
        } catch {
            throw PendingCopyDestinationReconnectError.configurationSaveFailed
        }

        return true
    }

    private static func validateSelectedIdentity(
        expected: ResourceFingerprint?,
        selected: ResourceFingerprint?
    ) throws {
        guard let expectedResource = expected?.resourceIdentifier,
              let selectedResource = selected?.resourceIdentifier
        else {
            throw PendingCopyDestinationReconnectError.selectedDestinationIdentityUnavailable
        }
        guard expectedResource == selectedResource else {
            throw PendingCopyDestinationReconnectError.selectedDestinationMismatch
        }

        if let expectedVolume = expected?.volumeIdentifier {
            guard let selectedVolume = selected?.volumeIdentifier else {
                throw PendingCopyDestinationReconnectError.selectedDestinationIdentityUnavailable
            }
            guard expectedVolume == selectedVolume else {
                throw PendingCopyDestinationReconnectError.selectedDestinationMismatch
            }
        }
    }
}

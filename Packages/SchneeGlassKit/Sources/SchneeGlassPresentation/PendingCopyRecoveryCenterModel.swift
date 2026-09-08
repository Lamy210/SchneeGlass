import Foundation
import Observation
import SchneeGlassApplication

@MainActor
@Observable
public final class PendingCopyRecoveryCenterModel {
    public private(set) var items: [PendingCopyRecoveryCenterItem] = []
    public private(set) var isLoading = false
    public private(set) var activeOperationID: UUID?
    public private(set) var message: String?

    private let workspaceModel: SchneeGlassWorkspaceModel
    private let useCase: PendingCopyRecoveryCenterUseCase
    private let reconnectUseCase: PendingCopyDestinationReconnectUseCase

    public init(
        workspaceModel: SchneeGlassWorkspaceModel,
        useCase: PendingCopyRecoveryCenterUseCase,
        reconnectUseCase: PendingCopyDestinationReconnectUseCase
    ) {
        self.workspaceModel = workspaceModel
        self.useCase = useCase
        self.reconnectUseCase = reconnectUseCase
    }

    public func refresh() async {
        guard !isLoading, activeOperationID == nil else {
            return
        }
        guard !workspaceModel.isMutatingConfiguration else {
            message = "SchneeGlass is updating its configuration. Try Recovery again when that operation finishes."
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            items = try await useCase.loadItems()
            message = nil
        } catch let error as PendingCopyRecoveryCenterError {
            items = []
            message = Self.message(for: error)
        } catch {
            items = []
            message = "SchneeGlass couldn't inspect pending copy recovery information. No files were changed."
        }
    }

    public func executeMutation(
        action: PendingCopyRecoveryAction,
        operationID: UUID
    ) async -> Bool {
        guard activeOperationID == nil else {
            return false
        }
        guard !workspaceModel.isMutatingConfiguration else {
            message = "SchneeGlass is updating its configuration. Try Recovery again when that operation finishes."
            return false
        }
        guard action == .discardMetadata || action == .removeOwnedStaging else {
            message = "This Recovery action is not a file-mutation action. No files were changed."
            return false
        }

        activeOperationID = operationID
        defer { activeOperationID = nil }

        do {
            try await useCase.executeMutation(action: action, operationID: operationID)
            await refreshAfterMutation()
            return true
        } catch let error as PendingCopyRecoveryCenterError {
            message = Self.message(for: error)
            return false
        } catch {
            message = "SchneeGlass couldn't complete that Recovery action. No final user file was deleted or overwritten."
            return false
        }
    }

    public func reconnectDestination(operationID: UUID) async -> Bool {
        guard activeOperationID == nil else {
            return false
        }
        guard !workspaceModel.isMutatingConfiguration else {
            message = "SchneeGlass is updating its configuration. Try reconnecting after that operation finishes."
            return false
        }

        activeOperationID = operationID
        defer { activeOperationID = nil }

        do {
            let reconnected = try await reconnectUseCase.execute(operationID: operationID)
            guard reconnected else {
                return false
            }

            do {
                items = try await useCase.loadItems()
                message = "Destination access was reconnected and saved. Pending Copy Recovery was refreshed. If the current Glass remains unavailable, restart SchneeGlass to start a new runtime session from the updated bookmark."
            } catch let error as PendingCopyRecoveryCenterError {
                message = Self.message(for: error)
            } catch {
                message = "Destination access was saved, but SchneeGlass couldn't refresh the Recovery list."
            }
            return true
        } catch let error as PendingCopyDestinationReconnectError {
            message = Self.message(for: error)
            return false
        } catch {
            message = "SchneeGlass couldn't reconnect that destination. The existing Glass configuration was not changed."
            return false
        }
    }

    public func dismissMessage() {
        message = nil
    }

    private func refreshAfterMutation() async {
        do {
            items = try await useCase.loadItems()
            message = "Recovery action completed. Final user-visible files were not deleted or overwritten."
        } catch let error as PendingCopyRecoveryCenterError {
            message = Self.message(for: error)
        } catch {
            message = "The Recovery action completed, but SchneeGlass couldn't refresh the Recovery list."
        }
    }

    private static func message(for error: PendingCopyRecoveryCenterError) -> String {
        switch error {
        case .copyInProgress:
            return "Wait for the current file copy to finish before using Pending Copy Recovery."
        case .recoveryInProgress:
            return "Another Pending Copy Recovery action is already running."
        case .recordsLoadFailed:
            return "SchneeGlass couldn't read pending copy recovery metadata. No files were changed."
        case .configurationLoadFailed:
            return "SchneeGlass couldn't read its configuration for Pending Copy Recovery. No files were changed."
        case .recordMissing:
            return "That recovery record no longer exists. Refresh the Recovery list."
        case .configurationMissing:
            return "The Glass for that recovery record no longer exists. SchneeGlass left the recovery metadata unchanged."
        case .destinationUnavailable:
            return "The destination folder is unavailable. Reconnect it before this recovery action can run."
        case .mutationFailed:
            return "SchneeGlass couldn't complete that recovery mutation safely. Final user-visible files were not deleted or overwritten."
        }
    }

    private static func message(for error: PendingCopyDestinationReconnectError) -> String {
        switch error {
        case .recordsLoadFailed:
            return "SchneeGlass couldn't read pending copy recovery metadata. The destination was not changed."
        case .configurationLoadFailed:
            return "SchneeGlass couldn't read its configuration. The destination was not changed."
        case .recordMissing:
            return "That recovery record no longer exists. Refresh the Recovery list."
        case .configurationMissing:
            return "The destination Glass no longer exists. No configuration was changed."
        case .sourceCreationFailed:
            return "macOS couldn't create persistent access for the selected folder. The existing destination was kept."
        case .selectedDestinationIdentityUnavailable:
            return "SchneeGlass couldn't prove that the selected folder is the original destination. The existing destination was kept."
        case .selectedDestinationMismatch:
            return "The selected folder does not match the recorded destination identity. The existing destination was kept."
        case .selectedDestinationAccessFailed:
            return "SchneeGlass couldn't access the selected folder after selection. The existing destination was kept."
        case .staleRecoveryState:
            return "The Glass or recovery record changed while the folder picker was open. Nothing was replaced; refresh and try again."
        case .copyInProgress:
            return "A file copy started while reconnecting. Finish that copy, then reconnect again."
        case .recoveryInProgress:
            return "Another Pending Copy Recovery action is already running."
        case .invalidConfiguration:
            return "SchneeGlass couldn't construct a valid updated Glass configuration. The existing destination was kept."
        case .configurationSaveFailed:
            return "SchneeGlass couldn't save the reconnected destination. The existing configuration remains authoritative."
        }
    }
}

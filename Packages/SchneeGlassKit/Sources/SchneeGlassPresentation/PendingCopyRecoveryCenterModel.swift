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
    private let navigationUseCase: PendingCopyRecoveryNavigationUseCase

    public init(
        workspaceModel: SchneeGlassWorkspaceModel,
        useCase: PendingCopyRecoveryCenterUseCase,
        reconnectUseCase: PendingCopyDestinationReconnectUseCase,
        navigationUseCase: PendingCopyRecoveryNavigationUseCase
    ) {
        self.workspaceModel = workspaceModel
        self.useCase = useCase
        self.reconnectUseCase = reconnectUseCase
        self.navigationUseCase = navigationUseCase
    }

    public func refresh() async {
        guard PendingCopyRecoveryActivityPolicy.canStart(
            isLoading: isLoading,
            activeOperationID: activeOperationID
        ) else {
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
        guard PendingCopyRecoveryActivityPolicy.canStart(
            isLoading: isLoading,
            activeOperationID: activeOperationID
        ) else {
            if isLoading {
                message = "Wait for the current Pending Copy Recovery refresh to finish before changing recovery state."
            }
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

    public func reveal(
        action: PendingCopyRecoveryAction,
        operationID: UUID
    ) async -> Bool {
        guard PendingCopyRecoveryActivityPolicy.canStart(
            isLoading: isLoading,
            activeOperationID: activeOperationID
        ) else {
            if isLoading {
                message = "Wait for the current Pending Copy Recovery refresh to finish before inspecting a recovery item."
            }
            return false
        }
        guard !workspaceModel.isMutatingConfiguration else {
            message = "SchneeGlass is updating its configuration. Try inspecting the recovery item after that operation finishes."
            return false
        }
        guard action == .revealStaging || action == .revealFinal else {
            message = "That Recovery action is not a read-only reveal action."
            return false
        }

        activeOperationID = operationID
        defer { activeOperationID = nil }

        do {
            try await navigationUseCase.reveal(action: action, operationID: operationID)
            message = action == .revealStaging
                ? "Finder opened the incomplete staging item for manual inspection. SchneeGlass did not modify it."
                : "Finder opened the final destination item for manual inspection. SchneeGlass did not modify it."
            return true
        } catch let error as PendingCopyRecoveryNavigationError {
            message = Self.message(for: error)
            return false
        } catch {
            message = "SchneeGlass couldn't reveal that recovery item. No files were changed."
            return false
        }
    }

    public func reconnectDestination(operationID: UUID) async -> Bool {
        guard PendingCopyRecoveryActivityPolicy.canStart(
            isLoading: isLoading,
            activeOperationID: activeOperationID
        ) else {
            if isLoading {
                message = "Wait for the current Pending Copy Recovery refresh to finish before reconnecting a destination."
            }
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

    private static func message(for error: PendingCopyRecoveryNavigationError) -> String {
        switch error {
        case .unsupportedAction:
            return "That Recovery action cannot be opened in Finder."
        case .recordsLoadFailed:
            return "SchneeGlass couldn't reload pending copy metadata before opening Finder. No files were changed."
        case .configurationLoadFailed:
            return "SchneeGlass couldn't reload its configuration before opening Finder. No files were changed."
        case .recordMissing:
            return "That recovery record no longer exists. Refresh the Recovery list."
        case .configurationMissing:
            return "The Glass for that recovery record no longer exists. Nothing was opened or changed."
        case .destinationUnavailable:
            return "The destination folder is unavailable. Reconnect it before inspecting its recovery files."
        case .actionNoLongerAvailable:
            return "The recovery state changed before Finder was opened. Refresh the Recovery list and inspect the latest state."
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

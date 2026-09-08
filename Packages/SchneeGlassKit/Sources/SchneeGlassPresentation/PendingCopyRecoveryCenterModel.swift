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

    public init(
        workspaceModel: SchneeGlassWorkspaceModel,
        useCase: PendingCopyRecoveryCenterUseCase
    ) {
        self.workspaceModel = workspaceModel
        self.useCase = useCase
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
            message = "This Recovery action is not available yet. No files were changed."
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
            return "The destination folder is unavailable. Reconnect support is required before this recovery action can run."
        case .mutationFailed:
            return "SchneeGlass couldn't complete that recovery mutation safely. Final user-visible files were not deleted or overwritten."
        }
    }
}

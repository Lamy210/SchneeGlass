import Foundation
import Observation
import SchneeGlassApplication

@MainActor
@Observable
public final class PendingCopyRecoveryCenterModel {
  public private(set) var items: [PendingCopyRecoveryCenterItem] = []
  public private(set) var isLoading = false
  public private(set) var activeOperationID: UUID?
  private var messageKey: GlassLocalizedText?

  public var message: String? {
    localizedMessage(locale: Locale(identifier: "en"))
  }

  public func localizedMessage(locale: Locale) -> String? {
    messageKey?.resolve(locale: locale)
  }

  private let workspaceModel: SchneeGlassWorkspaceModel
  private let useCase: PendingCopyRecoveryCenterUseCase
  private let reconnectUseCase: PendingCopyDestinationReconnectUseCase
  private let navigationUseCase: PendingCopyRecoveryNavigationUseCase
  private let taskCoordinator = PendingCopyRecoveryTaskCoordinator()
  private var isTerminating = false

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
    guard !isTerminating else {
      return
    }
    guard
      PendingCopyRecoveryActivityPolicy.canStart(
        isLoading: isLoading,
        activeOperationID: activeOperationID
      )
    else {
      return
    }
    guard !workspaceModel.isMutatingConfiguration else {
      messageKey = .recoveryMessageConfigurationBusy
      return
    }

    isLoading = true
    defer { isLoading = false }

    await taskCoordinator.run(ifBusy: ()) { [weak self] in
      guard let self else {
        return
      }

      do {
        items = try await useCase.loadItems()
        messageKey = nil
      } catch is CancellationError {
        return
      } catch let error as PendingCopyRecoveryCenterError {
        items = []
        messageKey = Self.messageKey(for: error)
      } catch {
        items = []
        messageKey = .recoveryMessageInspectFailed
      }
    }
  }

  public func executeMutation(
    action: PendingCopyRecoveryAction,
    operationID: UUID
  ) async -> Bool {
    guard !isTerminating else {
      return false
    }
    guard
      PendingCopyRecoveryActivityPolicy.canStart(
        isLoading: isLoading,
        activeOperationID: activeOperationID
      )
    else {
      if isLoading {
        messageKey = .recoveryMessageWaitForMutation
      }
      return false
    }
    guard !workspaceModel.isMutatingConfiguration else {
      messageKey = .recoveryMessageConfigurationBusy
      return false
    }
    guard action == .discardMetadata || action == .removeOwnedStaging else {
      messageKey = .recoveryMessageNotMutation
      return false
    }

    activeOperationID = operationID
    defer { activeOperationID = nil }

    return await taskCoordinator.run(ifBusy: false) { [weak self] in
      guard let self else {
        return false
      }

      do {
        try await useCase.executeMutation(action: action, operationID: operationID)
        await refreshAfterMutation()
        return true
      } catch is CancellationError {
        return false
      } catch let error as PendingCopyRecoveryCenterError {
        messageKey = Self.messageKey(for: error)
        return false
      } catch {
        messageKey = .recoveryMessageActionFailed
        return false
      }
    }
  }

  public func reveal(
    action: PendingCopyRecoveryAction,
    operationID: UUID
  ) async -> Bool {
    guard !isTerminating else {
      return false
    }
    guard
      PendingCopyRecoveryActivityPolicy.canStart(
        isLoading: isLoading,
        activeOperationID: activeOperationID
      )
    else {
      if isLoading {
        messageKey = .recoveryMessageWaitForReveal
      }
      return false
    }
    guard !workspaceModel.isMutatingConfiguration else {
      messageKey = .recoveryMessageBusyReveal
      return false
    }
    guard action == .revealStaging || action == .revealFinal else {
      messageKey = .recoveryMessageNotReveal
      return false
    }

    activeOperationID = operationID
    defer { activeOperationID = nil }

    return await taskCoordinator.run(ifBusy: false) { [weak self] in
      guard let self else {
        return false
      }

      do {
        try await navigationUseCase.reveal(action: action, operationID: operationID)
        if action == .revealStaging {
          messageKey = .recoveryMessageRevealedStaging
        } else {
          messageKey = .recoveryMessageRevealedFinal
        }
        return true
      } catch is CancellationError {
        return false
      } catch let error as PendingCopyRecoveryNavigationError {
        messageKey = Self.messageKey(for: error)
        return false
      } catch {
        messageKey = .recoveryMessageRevealFailed
        return false
      }
    }
  }

  public func reconnectDestination(operationID: UUID) async -> Bool {
    guard !isTerminating else {
      return false
    }
    guard
      PendingCopyRecoveryActivityPolicy.canStart(
        isLoading: isLoading,
        activeOperationID: activeOperationID
      )
    else {
      if isLoading {
        messageKey = .recoveryMessageWaitForReconnect
      }
      return false
    }
    guard !workspaceModel.isMutatingConfiguration else {
      messageKey = .recoveryMessageBusyReconnect
      return false
    }

    activeOperationID = operationID
    defer { activeOperationID = nil }

    return await taskCoordinator.run(ifBusy: false) { [weak self] in
      guard let self else {
        return false
      }

      do {
        let reconnected = try await reconnectUseCase.execute(operationID: operationID)
        guard reconnected else {
          return false
        }

        do {
          items = try await useCase.loadItems()
          messageKey = .recoveryMessageReconnected
        } catch is CancellationError {
          discardStaleItemsAfterPostActionReloadFailure()
          messageKey = nil
        } catch let error as PendingCopyRecoveryCenterError {
          discardStaleItemsAfterPostActionReloadFailure()
          messageKey = Self.messageKey(for: error)
        } catch {
          discardStaleItemsAfterPostActionReloadFailure()
          messageKey = .recoveryMessageReconnectReloadFailed
        }
        return true
      } catch is CancellationError {
        return false
      } catch let error as PendingCopyDestinationReconnectError {
        messageKey = Self.messageKey(for: error)
        return false
      } catch {
        messageKey = .recoveryMessageReconnectFailed
        return false
      }
    }
  }

  public func prepareForTermination() {
    isTerminating = true
  }

  public func shutdown() async {
    prepareForTermination()
    await taskCoordinator.cancelAndWait()

    // The tracked operation has finished its cancellation cleanup. Its outer caller may still be
    // scheduled to execute a defer on MainActor, so establish the quiesced presentation state now.
    isLoading = false
    activeOperationID = nil
  }

  public func dismissMessage() {
    messageKey = nil
  }

  private func refreshAfterMutation() async {
    do {
      items = try await useCase.loadItems()
      messageKey = .recoveryMessageMutationCompleted
    } catch is CancellationError {
      discardStaleItemsAfterPostActionReloadFailure()
      messageKey = nil
    } catch let error as PendingCopyRecoveryCenterError {
      discardStaleItemsAfterPostActionReloadFailure()
      messageKey = Self.messageKey(for: error)
    } catch {
      discardStaleItemsAfterPostActionReloadFailure()
      messageKey = .recoveryMessageMutationReloadFailed
    }
  }

  private func discardStaleItemsAfterPostActionReloadFailure() {
    items = PendingCopyRecoveryPostActionReloadPolicy.itemsAfterFailedReload(
      currentItems: items
    )
  }

  static func messageKey(for error: PendingCopyRecoveryNavigationError) -> GlassLocalizedText {
    switch error {
    case .unsupportedAction:
      return .recoveryMessageUnsupportedReveal
    case .recordsLoadFailed:
      return .recoveryMessageRevealRecordLoadFailed
    case .configurationLoadFailed:
      return .recoveryMessageRevealConfigLoadFailed
    case .recordMissing:
      return .recoveryMessageRecordMissing
    case .configurationMissing:
      return .recoveryMessageRevealGlassMissing
    case .destinationUnavailable:
      return .recoveryMessageRevealDestinationUnavailable
    case .actionNoLongerAvailable:
      return .recoveryMessageRevealStaleState
    }
  }

  static func messageKey(for error: PendingCopyRecoveryCenterError) -> GlassLocalizedText {
    switch error {
    case .copyInProgress:
      return .recoveryMessageCopyInProgress
    case .recoveryInProgress:
      return .recoveryMessageRecoveryInProgress
    case .recordsLoadFailed:
      return .recoveryMessageRecordsLoadFailed
    case .configurationLoadFailed:
      return .recoveryMessageConfigurationLoadFailed
    case .recordMissing:
      return .recoveryMessageRecordMissing
    case .configurationMissing:
      return .recoveryMessageConfigurationMissing
    case .destinationUnavailable:
      return .recoveryMessageDestinationUnavailable
    case .mutationFailed:
      return .recoveryMessageMutationFailed
    }
  }

  static func messageKey(for error: PendingCopyDestinationReconnectError) -> GlassLocalizedText {
    switch error {
    case .recordsLoadFailed:
      return .recoveryMessageReconnectRecordsLoadFailed
    case .configurationLoadFailed:
      return .recoveryMessageReconnectConfigLoadFailed
    case .recordMissing:
      return .recoveryMessageRecordMissing
    case .configurationMissing:
      return .recoveryMessageReconnectGlassMissing
    case .sourceCreationFailed:
      return .recoveryMessageSourceCreationFailed
    case .selectedDestinationIdentityUnavailable:
      return .recoveryMessageIdentityUnavailable
    case .selectedDestinationMismatch:
      return .recoveryMessageIdentityMismatch
    case .selectedDestinationAccessFailed:
      return .recoveryMessageSelectedAccessFailed
    case .staleRecoveryState:
      return .recoveryMessageStaleRecoveryState
    case .copyInProgress:
      return .recoveryMessageCopyStarted
    case .recoveryInProgress:
      return .recoveryMessageRecoveryInProgress
    case .invalidConfiguration:
      return .recoveryMessageInvalidConfiguration
    case .configurationSaveFailed:
      return .recoveryMessageConfigurationSaveFailed
    }
  }
}

import AppKit
import SchneeGlassApplication
import SchneeGlassMacOSAdapter
import SchneeGlassPresentation
import SwiftUI

@main
@MainActor
struct SchneeGlassApp: App {
  @NSApplicationDelegateAdaptor(SchneeGlassApplicationDelegate.self)
  private var applicationDelegate

  private let bootstrapState: SchneeGlassBootstrapState
  private let panelCoordinator: DesktopGlassPanelCoordinator?
  private let globalVisibilityShortcutController: SchneeGlassGlobalVisibilityShortcutController?

  init() {
    let state = SchneeGlassBootstrapState.resolve()
    self.bootstrapState = state

    if case .ready(let root) = state {
      let coordinator = DesktopGlassPanelCoordinator(model: root.workspaceModel)
      self.panelCoordinator = coordinator
      self.globalVisibilityShortcutController = SchneeGlassGlobalVisibilityShortcutController {
        [weak coordinator] in
        coordinator?.toggleAllVisibility()
      }
      applicationDelegate.configureShutdown {
        [
          weak coordinator,
          weak workspaceModel = root.workspaceModel,
          weak pendingCopyRecoveryModel = root.pendingCopyRecoveryModel,
        ] in
        workspaceModel?.prepareForTermination()
        pendingCopyRecoveryModel?.prepareForTermination()

        await workspaceModel?.cancelActiveCopiesForTermination()
        await pendingCopyRecoveryModel?.shutdown()
        await workspaceModel?.quiesceConfigurationMutationsForTermination()
        await coordinator?.flushPlacementsForTermination()
        await workspaceModel?.shutdown()
      }
    } else {
      self.panelCoordinator = nil
      self.globalVisibilityShortcutController = nil
    }
  }

  var body: some Scene {
    WindowGroup {
      switch bootstrapState {
      case .ready(let root):
        SchneeGlassWorkspaceView(model: root.workspaceModel)
          .task {
            await root.workspaceModel.restoreIfNeeded()
            panelCoordinator?.sync()
          }
          .onChange(of: root.workspaceModel.glasses) { _, _ in
            panelCoordinator?.sync()
          }

      case .failed:
        SchneeGlassBootstrapFailureView()
      }
    }
    .defaultSize(width: 720, height: 560)
    .commands {
      if case .ready(let root) = bootstrapState {
        let model = root.workspaceModel
        let locale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")

        CommandGroup(after: .newItem) {
          Button(SchneeGlassMenuText.addGlassCommand.resolve(locale: locale)) {
            Task {
              await model.addGlass()
            }
          }
          .keyboardShortcut("n", modifiers: .command)
          .disabled(!model.canAddGlass)
        }

        CommandMenu(SchneeGlassMenuText.glasses.resolve(locale: locale)) {
          Button(SchneeGlassMenuText.showAll.resolve(locale: locale)) {
            panelCoordinator?.showAll()
          }
          .disabled(model.glasses.isEmpty || model.isMutatingConfiguration)

          Button(SchneeGlassMenuText.hideAll.resolve(locale: locale)) {
            panelCoordinator?.hideAll()
          }
          .disabled(model.glasses.isEmpty || model.isMutatingConfiguration)

          Divider()

          Button(SchneeGlassMenuText.resetPositions.resolve(locale: locale)) {
            if let panelCoordinator {
              requestGlassPositionReset(coordinator: panelCoordinator, locale: locale)
            }
          }
          .disabled(model.glasses.isEmpty || !model.canMutateConfiguration)
        }
      }
    }

    MenuBarExtra("SchneeGlass", systemImage: "square.grid.2x2") {
      SchneeGlassMenuBarBootstrapContent(
        bootstrapState: bootstrapState,
        panelCoordinator: panelCoordinator
      )
    }
    .menuBarExtraStyle(.menu)

    Settings {
      SchneeGlassSettingsBootstrapView(
        bootstrapState: bootstrapState,
        panelCoordinator: panelCoordinator
      )
    }
  }
}

@MainActor
final class SchneeGlassApplicationDelegate: NSObject, NSApplicationDelegate {
  private let terminationCoordinator = ApplicationTerminationCoordinator()

  func configureShutdown(
    _ shutdownOperation: @escaping @MainActor () async -> Void
  ) {
    terminationCoordinator.configure(
      shutdownOperation: shutdownOperation
    )
  }

  func applicationShouldTerminate(
    _ sender: NSApplication
  ) -> NSApplication.TerminateReply {
    switch terminationCoordinator.requestTermination(
      reply: { shouldTerminate in
        sender.reply(toApplicationShouldTerminate: shouldTerminate)
      }
    ) {
    case .terminateNow:
      return .terminateNow
    case .terminateLater:
      return .terminateLater
    }
  }
}

private struct SchneeGlassMenuBarBootstrapContent: View {
  @Environment(\.locale) private var locale
  let bootstrapState: SchneeGlassBootstrapState
  let panelCoordinator: DesktopGlassPanelCoordinator?

  @ViewBuilder
  var body: some View {
    if case .ready(let root) = bootstrapState,
      let panelCoordinator
    {
      SchneeGlassMenuBarContent(
        model: root.workspaceModel,
        panelCoordinator: panelCoordinator
      )
    } else {
      Text(SchneeGlassMenuText.startupFailed.resolve(locale: locale))
        .disabled(true)

      Divider()

      SettingsLink {
        Text(SchneeGlassMenuText.settings.resolve(locale: locale))
      }

      Button(SchneeGlassMenuText.quit.resolve(locale: locale)) {
        NSApplication.shared.terminate(nil)
      }
    }
  }
}

private struct SchneeGlassMenuBarContent: View {
  @Environment(\.locale) private var locale
  let model: SchneeGlassWorkspaceModel
  let panelCoordinator: DesktopGlassPanelCoordinator

  var body: some View {
    let labels = GlassMenuLabels.make(for: model.glasses)

    Button(SchneeGlassMenuText.addGlass.resolve(locale: locale)) {
      Task {
        await model.addGlass()
      }
    }
    .disabled(!model.canAddGlass)

    Divider()

    Button(SchneeGlassMenuText.showAll.resolve(locale: locale)) {
      panelCoordinator.showAll()
    }
    .disabled(model.glasses.isEmpty || model.isMutatingConfiguration)

    Button(SchneeGlassMenuText.hideAll.resolve(locale: locale)) {
      panelCoordinator.hideAll()
    }
    .disabled(model.glasses.isEmpty || model.isMutatingConfiguration)

    Menu(SchneeGlassMenuText.showGlass.resolve(locale: locale)) {
      ForEach(model.glasses) { entry in
        Button(labels[entry.id] ?? entry.title) {
          panelCoordinator.setIndividualVisibility(true, for: entry.id)
        }
        .disabled(entry.placement == nil)
      }
    }
    .disabled(model.glasses.isEmpty || !panelCoordinator.canChangeIndividualVisibility)

    Menu(SchneeGlassMenuText.hideGlass.resolve(locale: locale)) {
      ForEach(model.glasses) { entry in
        Button(labels[entry.id] ?? entry.title) {
          panelCoordinator.setIndividualVisibility(false, for: entry.id)
        }
        .disabled(entry.placement == nil)
      }
    }
    .disabled(model.glasses.isEmpty || !panelCoordinator.canChangeIndividualVisibility)

    Divider()

    Button(SchneeGlassMenuText.resetPositions.resolve(locale: locale)) {
      requestGlassPositionReset(coordinator: panelCoordinator, locale: locale)
    }
    .disabled(model.glasses.isEmpty || !model.canMutateConfiguration)

    Divider()

    SettingsLink {
      Text(SchneeGlassMenuText.settings.resolve(locale: locale))
    }

    Button(SchneeGlassMenuText.quit.resolve(locale: locale)) {
      NSApplication.shared.terminate(nil)
    }
  }
}

@MainActor
private func requestGlassPositionReset(
  coordinator: DesktopGlassPanelCoordinator, locale: Locale
) {
  let confirmation = NSAlert()
  confirmation.messageText = SchneeGlassMenuText.resetTitle.resolve(locale: locale)
  confirmation.informativeText = SchneeGlassMenuText.resetDetail.resolve(locale: locale)
  confirmation.alertStyle = .informational
  confirmation.addButton(withTitle: SchneeGlassMenuText.resetAction.resolve(locale: locale))
  confirmation.addButton(withTitle: SchneeGlassMenuText.cancel.resolve(locale: locale))

  guard confirmation.runModal() == .alertFirstButtonReturn else {
    return
  }

  Task { @MainActor in
    let result = await coordinator.resetPositionsOnMainDisplay()
    switch result {
    case .updated, .noGlasses:
      return
    case .busy:
      presentResetFailure(
        message: SchneeGlassMenuText.resetBusy.resolve(locale: locale),
        locale: locale
      )
    case .noAvailableScreen:
      presentResetFailure(
        message: SchneeGlassMenuText.resetNoDisplay.resolve(locale: locale),
        locale: locale
      )
    case .failed:
      presentResetFailure(
        message: SchneeGlassMenuText.resetFailed.resolve(locale: locale),
        locale: locale
      )
    }
  }
}

@MainActor
private func presentResetFailure(message: String, locale: Locale) {
  let alert = NSAlert()
  alert.messageText = SchneeGlassMenuText.resetFailureTitle.resolve(locale: locale)
  alert.informativeText = message
  alert.alertStyle = .warning
  alert.addButton(withTitle: "OK")
  alert.runModal()
}

private struct SchneeGlassBootstrapFailureView: View {
  @Environment(\.locale) private var locale
  var body: some View {
    VStack(spacing: 14) {
      Image(systemName: "exclamationmark.triangle")
        .font(.system(size: 38, weight: .regular))
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)

      Text(SchneeGlassMenuText.startupFailed.resolve(locale: locale))
        .font(.title3.weight(.semibold))

      Text(SchneeGlassMenuText.startupFailedDetail.resolve(locale: locale))
        .font(.callout)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 420)
    }
    .frame(minWidth: 520, minHeight: 360)
    .padding(24)
  }
}

private struct SchneeGlassSettingsBootstrapView: View {
  @Environment(\.locale) private var locale
  let bootstrapState: SchneeGlassBootstrapState
  let panelCoordinator: DesktopGlassPanelCoordinator?

  @ViewBuilder
  var body: some View {
    if case .ready(let root) = bootstrapState,
      let panelCoordinator
    {
      SchneeGlassSettingsView(
        model: root.workspaceModel,
        pendingCopyRecoveryModel: root.pendingCopyRecoveryModel,
        panelCoordinator: panelCoordinator
      )
    } else {
      Form {
        Section(SchneeGlassSettingsText.recovery.resolve(locale: locale)) {
          Text(SchneeGlassSettingsText.recoveryUnavailable.resolve(locale: locale))
            .foregroundStyle(.secondary)

          Text(SchneeGlassSettingsText.filesUnchanged.resolve(locale: locale))
            .foregroundStyle(.secondary)
        }
      }
      .formStyle(.grouped)
      .frame(width: 480)
      .padding()
    }
  }
}

private struct SchneeGlassSettingsView: View {
  @Environment(\.locale) private var locale
  let model: SchneeGlassWorkspaceModel
  let pendingCopyRecoveryModel: PendingCopyRecoveryCenterModel
  let panelCoordinator: DesktopGlassPanelCoordinator

  @State private var backups: [ConfigurationBackupDescriptor] = []
  @State private var isLoadingBackups = false
  @State private var isRestoringBackup = false
  @State private var recoveryMessage: SchneeGlassSettingsText?

  var body: some View {
    Form {
      Section(SchneeGlassSettingsText.globalShortcut.resolve(locale: locale)) {
        HStack(spacing: 16) {
          Text(SchneeGlassSettingsText.showHideAll.resolve(locale: locale))
          Spacer()
          SchneeGlassGlobalShortcutRecorderView()
        }

        Text(SchneeGlassSettingsText.shortcutDetail.resolve(locale: locale))
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section(SchneeGlassSettingsText.configurationRecovery.resolve(locale: locale)) {
        Text(SchneeGlassSettingsText.configurationRecoveryDetail.resolve(locale: locale))
          .foregroundStyle(.secondary)

        if isLoadingBackups {
          ProgressView(SchneeGlassSettingsText.loadingBackups.resolve(locale: locale))
        } else if backups.isEmpty {
          Text(SchneeGlassSettingsText.noBackups.resolve(locale: locale))
            .foregroundStyle(.secondary)
        } else {
          ForEach(backups) { backup in
            HStack(spacing: 12) {
              VStack(alignment: .leading, spacing: 3) {
                Text(backup.createdAt.formatted(date: .abbreviated, time: .standard))
                Text(SchneeGlassSettingsText.backup.resolve(locale: locale))
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }

              Spacer()

              Button(SchneeGlassSettingsText.restore.resolve(locale: locale)) {
                guard confirmConfigurationBackupRestore(createdAt: backup.createdAt, locale: locale)
                else {
                  return
                }

                Task { @MainActor in
                  await restore(backup)
                }
              }
              .disabled(model.isMutatingConfiguration || isRestoringBackup)
            }
          }
        }

        HStack {
          Button(SchneeGlassSettingsText.refreshBackups.resolve(locale: locale)) {
            Task { @MainActor in
              await refreshBackups()
            }
          }
          .disabled(isLoadingBackups || isRestoringBackup)

          if isRestoringBackup {
            ProgressView()
              .controlSize(.small)
            Text(SchneeGlassSettingsText.restoring.resolve(locale: locale))
              .foregroundStyle(.secondary)
          }
        }

        if let recoveryMessage {
          Text(recoveryMessage.resolve(locale: locale))
            .foregroundStyle(.secondary)
        }
      }

      Section(SchneeGlassCopyRecoveryText.pendingRecovery.resolve(locale: locale)) {
        Text(SchneeGlassCopyRecoveryText.pendingRecoveryDetail.resolve(locale: locale))
          .foregroundStyle(.secondary)

        if pendingCopyRecoveryModel.isLoading {
          ProgressView(SchneeGlassCopyRecoveryText.inspectingPending.resolve(locale: locale))
        } else if pendingCopyRecoveryModel.items.isEmpty {
          Text(SchneeGlassCopyRecoveryText.noPending.resolve(locale: locale))
            .foregroundStyle(.secondary)
        } else {
          ForEach(pendingCopyRecoveryModel.items) { item in
            VStack(alignment: .leading, spacing: 8) {
              HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                  Text(item.record.finalFilename)
                    .font(.body.weight(.medium))
                  let unknownGlass = SchneeGlassCopyRecoveryText.unknownGlass.resolve(
                    locale: locale)
                  Text(item.glassTitle ?? unknownGlass)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if pendingCopyRecoveryModel.activeOperationID == item.id {
                  ProgressView()
                    .controlSize(.small)
                }
              }

              Text(
                CopyRecoveryStatePresentation.description(for: item.state, locale: locale)
              )
              .font(.caption)
              .foregroundStyle(.secondary)

              HStack(spacing: 8) {
                if item.actions.contains(.revealStaging)
                  || item.actions.contains(.revealFinal)
                {
                  Menu(SchneeGlassCopyRecoveryText.inspectFinder.resolve(locale: locale)) {
                    if item.actions.contains(.revealStaging) {
                      Button(SchneeGlassCopyRecoveryText.showIncomplete.resolve(locale: locale)) {
                        Task { @MainActor in
                          _ = await pendingCopyRecoveryModel.reveal(
                            action: .revealStaging,
                            operationID: item.id
                          )
                        }
                      }
                    }

                    if item.actions.contains(.revealFinal) {
                      Button(SchneeGlassCopyRecoveryText.showFinal.resolve(locale: locale)) {
                        Task { @MainActor in
                          _ = await pendingCopyRecoveryModel.reveal(
                            action: .revealFinal,
                            operationID: item.id
                          )
                        }
                      }
                    }
                  }
                }

                if item.actions.contains(.discardMetadata) {
                  Button(SchneeGlassCopyRecoveryText.discardMetadataMenu.resolve(locale: locale)) {
                    guard
                      confirmPendingCopyMetadataDiscard(
                        filename: item.record.finalFilename, locale: locale)
                    else {
                      return
                    }
                    Task { @MainActor in
                      _ = await pendingCopyRecoveryModel.executeMutation(
                        action: .discardMetadata,
                        operationID: item.id
                      )
                    }
                  }
                }

                if item.actions.contains(.removeOwnedStaging) {
                  Button(SchneeGlassCopyRecoveryText.removeIncompleteMenu.resolve(locale: locale)) {
                    guard
                      confirmOwnedStagingRemoval(
                        filename: item.record.finalFilename, locale: locale)
                    else {
                      return
                    }
                    Task { @MainActor in
                      _ = await pendingCopyRecoveryModel.executeMutation(
                        action: .removeOwnedStaging,
                        operationID: item.id
                      )
                    }
                  }
                }

                if item.actions.contains(.reconnectDestination) {
                  Button(SchneeGlassCopyRecoveryText.reconnectDestination.resolve(locale: locale)) {
                    Task { @MainActor in
                      _ = await pendingCopyRecoveryModel.reconnectDestination(
                        operationID: item.id
                      )
                    }
                  }
                }
              }
              .disabled(
                model.isMutatingConfiguration
                  || pendingCopyRecoveryModel.activeOperationID != nil
              )
            }
            .padding(.vertical, 4)
          }
        }

        Button(SchneeGlassCopyRecoveryText.refreshPending.resolve(locale: locale)) {
          Task { @MainActor in
            await pendingCopyRecoveryModel.refresh()
          }
        }
        .disabled(
          pendingCopyRecoveryModel.isLoading
            || pendingCopyRecoveryModel.activeOperationID != nil
        )

        if let message = pendingCopyRecoveryModel.localizedMessage(locale: locale) {
          Text(message)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Section(SchneeGlassCopyRecoveryText.safety.resolve(locale: locale)) {
        Text(SchneeGlassCopyRecoveryText.safetyDetail.resolve(locale: locale))
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .frame(width: 560)
    .padding()
    .task {
      await refreshBackups()
      await pendingCopyRecoveryModel.refresh()
    }
  }

  @MainActor
  private func refreshBackups() async {
    guard !isLoadingBackups else {
      return
    }

    isLoadingBackups = true
    defer { isLoadingBackups = false }

    switch await model.loadConfigurationBackups() {
    case .loaded(let loadedBackups):
      backups = loadedBackups
      if recoveryMessage == .backupReadFailed {
        recoveryMessage = nil
      }
    case .failed:
      backups = []
      recoveryMessage = .backupReadFailed
    }
  }

  @MainActor
  private func restore(_ backup: ConfigurationBackupDescriptor) async {
    guard !isRestoringBackup else {
      return
    }
    guard !model.isMutatingConfiguration else {
      recoveryMessage = .configurationBusy
      return
    }

    isRestoringBackup = true
    defer { isRestoringBackup = false }

    panelCoordinator.closeAll()

    let result = await model.restoreConfigurationBackup(id: backup.id)
    switch result {
    case .restored:
      panelCoordinator.showAll()
      recoveryMessage = .configurationRestored
      await refreshBackups()
      await pendingCopyRecoveryModel.refresh()

    case .restoredNeedsRestart:
      recoveryMessage = .restoredNeedsRestart
      await refreshBackups()

    case .busy:
      panelCoordinator.showAll()
      recoveryMessage = .configurationBusy

    case .copyInProgress:
      panelCoordinator.showAll()
      recoveryMessage = .waitForCopy

    case .failed:
      panelCoordinator.showAll()
      recoveryMessage = .restoreFailed
    }
  }
}

private struct SchneeGlassGlobalShortcutRecorderView: NSViewRepresentable {
  func makeNSView(context: Context) -> NSView {
    SchneeGlassGlobalVisibilityShortcutController.makeRecorderView()
  }

  func updateNSView(_ nsView: NSView, context: Context) {}
}

@MainActor
private func confirmConfigurationBackupRestore(createdAt: Date, locale: Locale) -> Bool {
  let confirmation = NSAlert()
  confirmation.messageText = SchneeGlassSettingsText.confirmRestoreTitle.resolve(locale: locale)
  let dateStyle = Date.FormatStyle(date: .abbreviated, time: .standard, locale: locale)
  confirmation.informativeText = SchneeGlassSettingsText.restoreConfirmation(
    date: createdAt.formatted(dateStyle),
    locale: locale
  )
  confirmation.alertStyle = .warning
  confirmation.addButton(
    withTitle: SchneeGlassSettingsText.confirmRestoreAction.resolve(locale: locale))
  confirmation.addButton(withTitle: SchneeGlassSettingsText.cancel.resolve(locale: locale))
  return confirmation.runModal() == .alertFirstButtonReturn
}

@MainActor
private func confirmPendingCopyMetadataDiscard(filename: String, locale: Locale) -> Bool {
  let confirmation = NSAlert()
  confirmation.messageText = SchneeGlassCopyRecoveryText.discardMetadataTitle.resolve(
    locale: locale)
  confirmation.informativeText = SchneeGlassCopyRecoveryText.discardConfirmation(
    filename: filename, locale: locale)
  confirmation.alertStyle = .informational
  confirmation.addButton(
    withTitle: SchneeGlassCopyRecoveryText.discardMetadataAction.resolve(locale: locale))
  confirmation.addButton(withTitle: SchneeGlassSettingsText.cancel.resolve(locale: locale))
  return confirmation.runModal() == .alertFirstButtonReturn
}

@MainActor
private func confirmOwnedStagingRemoval(filename: String, locale: Locale) -> Bool {
  let confirmation = NSAlert()
  confirmation.messageText = SchneeGlassCopyRecoveryText.removeIncompleteTitle.resolve(
    locale: locale)
  confirmation.informativeText = SchneeGlassCopyRecoveryText.removeConfirmation(
    filename: filename, locale: locale)
  confirmation.alertStyle = .warning
  confirmation.addButton(
    withTitle: SchneeGlassCopyRecoveryText.removeIncompleteAction.resolve(locale: locale))
  confirmation.addButton(withTitle: SchneeGlassSettingsText.cancel.resolve(locale: locale))
  return confirmation.runModal() == .alertFirstButtonReturn
}

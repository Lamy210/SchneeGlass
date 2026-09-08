import AppKit
import SchneeGlassApplication
import SchneeGlassMacOSAdapter
import SchneeGlassPresentation
import SwiftUI

@main
@MainActor
struct SchneeGlassApp: App {
    private let bootstrapState: SchneeGlassBootstrapState
    private let panelCoordinator: DesktopGlassPanelCoordinator?
    private let globalVisibilityShortcutController: SchneeGlassGlobalVisibilityShortcutController?

    init() {
        let state = SchneeGlassBootstrapState.resolve()
        self.bootstrapState = state

        if case let .ready(root) = state {
            let coordinator = DesktopGlassPanelCoordinator(model: root.workspaceModel)
            self.panelCoordinator = coordinator
            self.globalVisibilityShortcutController = SchneeGlassGlobalVisibilityShortcutController {
                [weak coordinator] in
                coordinator?.toggleAllVisibility()
            }
        } else {
            self.panelCoordinator = nil
            self.globalVisibilityShortcutController = nil
        }
    }

    var body: some Scene {
        WindowGroup {
            switch bootstrapState {
            case let .ready(root):
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
            if case let .ready(root) = bootstrapState {
                let model = root.workspaceModel

                CommandGroup(after: .newItem) {
                    Button("Add Glass") {
                        Task {
                            await model.addGlass()
                        }
                    }
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(model.isMutatingConfiguration)
                }

                CommandMenu("Glasses") {
                    Button("Show All Glasses") {
                        panelCoordinator?.showAll()
                    }
                    .disabled(model.glasses.isEmpty || model.isMutatingConfiguration)

                    Button("Hide All Glasses") {
                        panelCoordinator?.hideAll()
                    }
                    .disabled(model.glasses.isEmpty || model.isMutatingConfiguration)

                    Divider()

                    Button("Reset Glass Positions…") {
                        if let panelCoordinator {
                            requestGlassPositionReset(coordinator: panelCoordinator)
                        }
                    }
                    .disabled(model.glasses.isEmpty || model.isMutatingConfiguration)
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

private struct SchneeGlassMenuBarBootstrapContent: View {
    let bootstrapState: SchneeGlassBootstrapState
    let panelCoordinator: DesktopGlassPanelCoordinator?

    @ViewBuilder
    var body: some View {
        if case let .ready(root) = bootstrapState,
           let panelCoordinator
        {
            SchneeGlassMenuBarContent(
                model: root.workspaceModel,
                panelCoordinator: panelCoordinator
            )
        } else {
            Text("SchneeGlass couldn't start")
                .disabled(true)

            Divider()

            SettingsLink {
                Text("Settings…")
            }

            Button("Quit SchneeGlass") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

private struct SchneeGlassMenuBarContent: View {
    let model: SchneeGlassWorkspaceModel
    let panelCoordinator: DesktopGlassPanelCoordinator

    var body: some View {
        Button("Add Glass…") {
            Task {
                await model.addGlass()
            }
        }
        .disabled(model.isMutatingConfiguration)

        Divider()

        Button("Show All Glasses") {
            panelCoordinator.showAll()
        }
        .disabled(model.glasses.isEmpty || model.isMutatingConfiguration)

        Button("Hide All Glasses") {
            panelCoordinator.hideAll()
        }
        .disabled(model.glasses.isEmpty || model.isMutatingConfiguration)

        Divider()

        Button("Reset Glass Positions…") {
            requestGlassPositionReset(coordinator: panelCoordinator)
        }
        .disabled(model.glasses.isEmpty || model.isMutatingConfiguration)

        Divider()

        SettingsLink {
            Text("Settings…")
        }

        Button("Quit SchneeGlass") {
            NSApplication.shared.terminate(nil)
        }
    }
}

@MainActor
private func requestGlassPositionReset(coordinator: DesktopGlassPanelCoordinator) {
    let confirmation = NSAlert()
    confirmation.messageText = "Reset Glass Positions?"
    confirmation.informativeText = "All Glass panels will be moved onto the current main display. Connected folders and their files will not be moved, renamed, or deleted."
    confirmation.alertStyle = .informational
    confirmation.addButton(withTitle: "Reset Positions")
    confirmation.addButton(withTitle: "Cancel")

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
                message: "SchneeGlass is already updating its configuration. Try Reset Positions again after the current operation finishes."
            )
        case .noAvailableScreen:
            presentResetFailure(
                message: "SchneeGlass could not find an available display. No Glass positions were changed."
            )
        case .failed:
            presentResetFailure(
                message: "SchneeGlass could not reset Glass positions. No files or folders were changed."
            )
        }
    }
}

@MainActor
private func presentResetFailure(message: String) {
    let alert = NSAlert()
    alert.messageText = "Couldn’t Reset Glass Positions"
    alert.informativeText = message
    alert.alertStyle = .warning
    alert.addButton(withTitle: "OK")
    alert.runModal()
}

private struct SchneeGlassBootstrapFailureView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 38, weight: .regular))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("SchneeGlass couldn't start")
                .font(.title3.weight(.semibold))

            Text("The application support location could not be prepared. No folders or files were changed.")
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
    let bootstrapState: SchneeGlassBootstrapState
    let panelCoordinator: DesktopGlassPanelCoordinator?

    @ViewBuilder
    var body: some View {
        if case let .ready(root) = bootstrapState,
           let panelCoordinator
        {
            SchneeGlassSettingsView(
                model: root.workspaceModel,
                pendingCopyRecoveryModel: root.pendingCopyRecoveryModel,
                panelCoordinator: panelCoordinator
            )
        } else {
            Form {
                Section("Recovery") {
                    Text("Recovery is unavailable because SchneeGlass could not prepare its application support location.")
                        .foregroundStyle(.secondary)

                    Text("No folders or files were changed.")
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
    let model: SchneeGlassWorkspaceModel
    let pendingCopyRecoveryModel: PendingCopyRecoveryCenterModel
    let panelCoordinator: DesktopGlassPanelCoordinator

    @State private var backups: [ConfigurationBackupDescriptor] = []
    @State private var isLoadingBackups = false
    @State private var isRestoringBackup = false
    @State private var recoveryMessage: String?

    var body: some View {
        Form {
            Section("Global Shortcut") {
                HStack(spacing: 16) {
                    Text("Show / Hide All Glasses")
                    Spacer()
                    SchneeGlassGlobalShortcutRecorderView()
                }

                Text("No shortcut is assigned by default. Choose a shortcut to toggle all Desktop Glasses from anywhere without granting Accessibility permission.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Configuration Recovery") {
                Text("Restore an earlier SchneeGlass configuration without moving, renaming, deleting, or replacing files in connected folders.")
                    .foregroundStyle(.secondary)

                if isLoadingBackups {
                    ProgressView("Loading configuration backups…")
                } else if backups.isEmpty {
                    Text("No valid configuration backups are available.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(backups) { backup in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(backup.createdAt.formatted(date: .abbreviated, time: .standard))
                                Text("Configuration backup")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button("Restore…") {
                                guard confirmConfigurationBackupRestore(createdAt: backup.createdAt) else {
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
                    Button("Refresh Backups") {
                        Task { @MainActor in
                            await refreshBackups()
                        }
                    }
                    .disabled(isLoadingBackups || isRestoringBackup)

                    if isRestoringBackup {
                        ProgressView()
                            .controlSize(.small)
                        Text("Restoring configuration…")
                            .foregroundStyle(.secondary)
                    }
                }

                if let recoveryMessage {
                    Text(recoveryMessage)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Pending Copy Recovery") {
                Text("Review interrupted or incompletely finalized copy operations. SchneeGlass never deletes or overwrites a final user-visible file from this Recovery Center.")
                    .foregroundStyle(.secondary)

                if pendingCopyRecoveryModel.isLoading {
                    ProgressView("Inspecting pending copies…")
                } else if pendingCopyRecoveryModel.items.isEmpty {
                    Text("No pending copy recovery items are available.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(pendingCopyRecoveryModel.items) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.record.finalFilename)
                                        .font(.body.weight(.medium))
                                    Text(item.glassTitle ?? "Unknown Glass")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if pendingCopyRecoveryModel.activeOperationID == item.id {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                            }

                            Text(pendingCopyRecoveryDescription(for: item))
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 8) {
                                if item.actions.contains(.revealStaging)
                                    || item.actions.contains(.revealFinal)
                                {
                                    Menu("Inspect in Finder") {
                                        if item.actions.contains(.revealStaging) {
                                            Button("Show Incomplete Copy") {
                                                Task { @MainActor in
                                                    _ = await pendingCopyRecoveryModel.reveal(
                                                        action: .revealStaging,
                                                        operationID: item.id
                                                    )
                                                }
                                            }
                                        }

                                        if item.actions.contains(.revealFinal) {
                                            Button("Show Final File") {
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
                                    Button("Discard Metadata…") {
                                        guard confirmPendingCopyMetadataDiscard(filename: item.record.finalFilename) else {
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
                                    Button("Remove Incomplete Copy…") {
                                        guard confirmOwnedStagingRemoval(filename: item.record.finalFilename) else {
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
                                    Button("Reconnect Destination…") {
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

                Button("Refresh Pending Copies") {
                    Task { @MainActor in
                        await pendingCopyRecoveryModel.refresh()
                    }
                }
                .disabled(
                    pendingCopyRecoveryModel.isLoading
                        || pendingCopyRecoveryModel.activeOperationID != nil
                )

                if let message = pendingCopyRecoveryModel.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Safety") {
                Text("Configuration Recovery changes SchneeGlass configuration only. Reconnect Destination updates the saved security-scoped folder access after identity checks; it does not move, rename, delete, or overwrite folder contents. Inspect in Finder is read-only and revalidates the current recovery state before opening an item. Pending Copy Recovery may remove only a SchneeGlass-owned incomplete staging file after exact operation metadata and filesystem resource identity are revalidated. Final user-visible files are never deleted or overwritten by Recovery.")
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
        case let .loaded(loadedBackups):
            backups = loadedBackups
            if recoveryMessage == "SchneeGlass couldn't read its configuration backups. No configuration was changed." {
                recoveryMessage = nil
            }
        case .failed:
            backups = []
            recoveryMessage = "SchneeGlass couldn't read its configuration backups. No configuration was changed."
        }
    }

    @MainActor
    private func restore(_ backup: ConfigurationBackupDescriptor) async {
        guard !isRestoringBackup else {
            return
        }
        guard !model.isMutatingConfiguration else {
            recoveryMessage = "SchneeGlass is already updating its configuration. Try again after the current operation finishes."
            return
        }

        isRestoringBackup = true
        defer { isRestoringBackup = false }

        panelCoordinator.closeAll()

        let result = await model.restoreConfigurationBackup(id: backup.id)
        switch result {
        case .restored:
            panelCoordinator.showAll()
            recoveryMessage = "Configuration restored. Connected folders and files were not changed."
            await refreshBackups()
            await pendingCopyRecoveryModel.refresh()

        case .restoredNeedsRestart:
            recoveryMessage = "The backup was restored, but the workspace could not reload it. Restart SchneeGlass to retry the restored configuration."
            await refreshBackups()

        case .busy:
            panelCoordinator.showAll()
            recoveryMessage = "SchneeGlass is already updating its configuration. Try again after the current operation finishes."

        case .copyInProgress:
            panelCoordinator.showAll()
            recoveryMessage = "Wait for the current file copy to finish before restoring configuration."

        case .failed:
            panelCoordinator.showAll()
            recoveryMessage = "SchneeGlass couldn't restore that backup. The current configuration was left unchanged."
        }
    }
}

private struct SchneeGlassGlobalShortcutRecorderView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        SchneeGlassGlobalVisibilityShortcutController.makeRecorderView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private func pendingCopyRecoveryDescription(
    for item: PendingCopyRecoveryCenterItem
) -> String {
    switch item.state {
    case .configurationMissing:
        return "The original Glass configuration is missing. SchneeGlass will keep the recovery metadata and will not guess where the file belongs."

    case .destinationUnavailable:
        return "The destination folder cannot currently be accessed. Reconnect it before attempting cleanup."

    case let .assessed(disposition):
        switch disposition {
        case .metadataOnly:
            return "Only recovery metadata remains. Discarding it does not modify a connected folder."
        case let .stagingPresent(verification):
            if verification.resourceIdentity == .matchesRecordedIdentity {
                return "An incomplete SchneeGlass-owned staging file remains and its resource identity still matches the recorded operation."
            }
            return "A staging-like item remains, but ownership cannot be proven. SchneeGlass will not delete it."
        case .finalPresent:
            return "A final user-visible file exists. It is preserved; only recovery metadata may be discarded explicitly."
        case let .stagingAndFinalPresent(staging, _):
            if staging.resourceIdentity == .matchesRecordedIdentity {
                return "Both staging and final files exist. The final file is preserved; only the proven app-owned staging file may be removed explicitly."
            }
            return "Both staging and final files exist, but staging ownership cannot be proven. SchneeGlass will not delete either file."
        case .invalidRecord:
            return "Recovery metadata is invalid. No mutation action is offered."
        case .destinationMismatch:
            return "The recovery record does not match the destination Glass. No mutation action is offered."
        case .destinationUnavailable:
            return "The destination folder cannot currently be inspected."
        case .unexpectedFileType:
            return "An unexpected filesystem item exists at a recovery path. SchneeGlass will not mutate it."
        }
    }
}

@MainActor
private func confirmConfigurationBackupRestore(createdAt: Date) -> Bool {
    let confirmation = NSAlert()
    confirmation.messageText = "Restore Configuration Backup?"
    confirmation.informativeText = "Restore the SchneeGlass configuration from \(createdAt.formatted(date: .abbreviated, time: .standard)). SchneeGlass will preserve the current configuration before replacing it. Connected folders and their files will not be moved, renamed, deleted, or replaced."
    confirmation.alertStyle = .warning
    confirmation.addButton(withTitle: "Restore Configuration")
    confirmation.addButton(withTitle: "Cancel")
    return confirmation.runModal() == .alertFirstButtonReturn
}

@MainActor
private func confirmPendingCopyMetadataDiscard(filename: String) -> Bool {
    let confirmation = NSAlert()
    confirmation.messageText = "Discard Recovery Metadata?"
    confirmation.informativeText = "Discard SchneeGlass recovery metadata for \(filename). This action does not delete, rename, move, or overwrite the final file or any incomplete staging file."
    confirmation.alertStyle = .informational
    confirmation.addButton(withTitle: "Discard Metadata")
    confirmation.addButton(withTitle: "Cancel")
    return confirmation.runModal() == .alertFirstButtonReturn
}

@MainActor
private func confirmOwnedStagingRemoval(filename: String) -> Bool {
    let confirmation = NSAlert()
    confirmation.messageText = "Remove Incomplete Copy?"
    confirmation.informativeText = "Remove only the SchneeGlass-owned incomplete staging file associated with \(filename). SchneeGlass will revalidate the operation ID, file type, destination, and filesystem resource identity immediately before deletion. The final user-visible file will not be deleted or overwritten."
    confirmation.alertStyle = .warning
    confirmation.addButton(withTitle: "Remove Incomplete Copy")
    confirmation.addButton(withTitle: "Cancel")
    return confirmation.runModal() == .alertFirstButtonReturn
}

import AppKit
import SchneeGlassPresentation
import SwiftUI

@main
@MainActor
struct SchneeGlassApp: App {
    private let bootstrapState: SchneeGlassBootstrapState
    private let panelCoordinator: DesktopGlassPanelCoordinator?

    init() {
        let state = SchneeGlassBootstrapState.resolve()
        self.bootstrapState = state
        if case let .ready(model) = state {
            self.panelCoordinator = DesktopGlassPanelCoordinator(model: model)
        } else {
            self.panelCoordinator = nil
        }
    }

    var body: some Scene {
        WindowGroup {
            switch bootstrapState {
            case let .ready(model):
                SchneeGlassWorkspaceView(model: model)
                    .task {
                        await model.restoreIfNeeded()
                        panelCoordinator?.sync()
                    }
                    .onChange(of: model.glasses) { _, _ in
                        panelCoordinator?.sync()
                    }

            case .failed:
                SchneeGlassBootstrapFailureView()
            }
        }
        .defaultSize(width: 720, height: 560)
        .commands {
            if case let .ready(model) = bootstrapState {
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
                    .disabled(model.glasses.isEmpty)

                    Button("Hide All Glasses") {
                        panelCoordinator?.hideAll()
                    }
                    .disabled(model.glasses.isEmpty)

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
            SchneeGlassSettingsBootstrapView()
        }
    }
}

private struct SchneeGlassMenuBarBootstrapContent: View {
    let bootstrapState: SchneeGlassBootstrapState
    let panelCoordinator: DesktopGlassPanelCoordinator?

    @ViewBuilder
    var body: some View {
        if case let .ready(model) = bootstrapState,
           let panelCoordinator
        {
            SchneeGlassMenuBarContent(
                model: model,
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
        .disabled(model.glasses.isEmpty)

        Button("Hide All Glasses") {
            panelCoordinator.hideAll()
        }
        .disabled(model.glasses.isEmpty)

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
    var body: some View {
        Form {
            Section("SchneeGlass") {
                Text("Settings and Recovery controls will be connected as the next v0.1 slices are completed.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .padding()
    }
}

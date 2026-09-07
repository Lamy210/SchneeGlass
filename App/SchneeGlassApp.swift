import SchneeGlassPresentation
import SwiftUI

@main
@MainActor
struct SchneeGlassApp: App {
    private let bootstrapState: SchneeGlassBootstrapState

    init() {
        self.bootstrapState = SchneeGlassBootstrapState.resolve()
    }

    var body: some Scene {
        WindowGroup {
            switch bootstrapState {
            case let .ready(model):
                SchneeGlassWorkspaceView(model: model)
                    .task {
                        await model.restoreIfNeeded()
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
                    .disabled(model.isCreatingGlass || model.isRestoring)
                }
            }
        }

        Settings {
            SchneeGlassSettingsBootstrapView()
        }
    }
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

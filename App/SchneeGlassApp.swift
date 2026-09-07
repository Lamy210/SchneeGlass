import SwiftUI
import SchneeGlassPresentation

@main
struct SchneeGlassApp: App {
    var body: some Scene {
        WindowGroup {
            SchneeGlassBootstrapView()
        }

        Settings {
            SchneeGlassSettingsBootstrapView()
        }
    }
}

private struct SchneeGlassBootstrapView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "snowflake")
                .font(.system(size: 44, weight: .medium))
                .accessibilityHidden(true)

            Text("SchneeGlass")
                .font(.title2.weight(.semibold))

            Text("macOS desktop file workspace")
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 360, minHeight: 240)
        .padding(24)
    }
}

private struct SchneeGlassSettingsBootstrapView: View {
    var body: some View {
        Form {
            Section("SchneeGlass") {
                Text("Settings will be connected to the application layer in a later task.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding()
    }
}

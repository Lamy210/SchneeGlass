import AppKit
import SchneeGlassApplication
import SchneeGlassDomain

@MainActor
public final class NativeFolderSelector: FolderSelecting {
    public init() {}

    public func selectFolder() async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.resolvesAliases = true
        panel.prompt = "Add Glass"
        panel.message = "Choose a folder to place on your desktop as a SchneeGlass."

        return await withCheckedContinuation { continuation in
            panel.begin { response in
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
        }
    }
}

public enum InitialGlassPlacementError: Error, Hashable, Sendable {
    case noAvailableScreen
    case screenTooSmall
}

@MainActor
public final class NativeInitialGlassPlacementProvider: InitialGlassPlacementProviding {
    public init() {}

    public func initialPlacement() throws -> GlassPlacement {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            throw InitialGlassPlacementError.noAvailableScreen
        }
        return try InitialGlassPlacementCalculator.placement(in: screen.visibleFrame)
    }
}

enum InitialGlassPlacementCalculator {
    static func placement(in visibleFrame: CGRect) throws -> GlassPlacement {
        guard visibleFrame.width >= GlassPlacement.minimumWidth,
              visibleFrame.height >= GlassPlacement.minimumHeight
        else {
            throw InitialGlassPlacementError.screenTooSmall
        }

        let width = min(GlassPlacement.defaultWidth, visibleFrame.width)
        let height = min(GlassPlacement.defaultHeight, visibleFrame.height)
        let x = visibleFrame.midX - width / 2
        let y = visibleFrame.midY - height / 2

        return try GlassPlacement(
            x: x,
            y: y,
            width: width,
            height: height
        )
    }
}

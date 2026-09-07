import AppKit
import SchneeGlassDomain
import SchneeGlassMacOSAdapter
import SchneeGlassPresentation
import SwiftUI

@MainActor
final class DesktopGlassPanelCoordinator: NSObject, NSWindowDelegate {
    private final class DesktopGlassPanel: NSPanel {
        let glassID: GlassID
        var suppressPlacementPersistence = false

        init(glassID: GlassID, contentRect: NSRect) {
            self.glassID = glassID
            super.init(
                contentRect: contentRect,
                styleMask: [.titled, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
        }
    }

    private struct PanelRecord {
        let panel: DesktopGlassPanel
        var persistenceTask: Task<Void, Never>?
    }

    private let model: SchneeGlassWorkspaceModel
    private var panels: [GlassID: PanelRecord] = [:]

    init(model: SchneeGlassWorkspaceModel) {
        self.model = model
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        for record in panels.values {
            record.persistenceTask?.cancel()
        }
    }

    func sync() {
        let entriesByID = Dictionary(uniqueKeysWithValues: model.glasses.map { ($0.id, $0) })

        for glassID in panels.keys where entriesByID[glassID] == nil {
            removePanel(glassID: glassID)
        }

        for entry in model.glasses {
            guard let placement = entry.placement else {
                continue
            }

            if panels[entry.id] == nil {
                createPanel(for: entry, placement: placement)
            } else {
                updatePanel(for: entry, placement: placement)
            }
        }
    }

    func showAll() {
        sync()
        for record in panels.values {
            record.panel.orderFrontRegardless()
        }
    }

    func hideAll() {
        for record in panels.values {
            record.panel.orderOut(nil)
        }
    }

    func closeAll() {
        let records = Array(panels.values)
        panels.removeAll(keepingCapacity: false)
        for record in records {
            record.persistenceTask?.cancel()
            record.panel.delegate = nil
            record.panel.close()
        }
    }

    func windowDidMove(_ notification: Notification) {
        guard let panel = notification.object as? DesktopGlassPanel,
              !panel.suppressPlacementPersistence
        else {
            return
        }
        schedulePlacementPersistence(for: panel, delayNanoseconds: 350_000_000)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let panel = notification.object as? DesktopGlassPanel,
              !panel.suppressPlacementPersistence
        else {
            return
        }
        schedulePlacementPersistence(for: panel, delayNanoseconds: 150_000_000)
    }

    func windowWillClose(_ notification: Notification) {
        guard let panel = notification.object as? DesktopGlassPanel else {
            return
        }
        panels[panel.glassID]?.persistenceTask?.cancel()
        panels[panel.glassID] = nil
    }

    @objc
    private func screenParametersDidChange(_ notification: Notification) {
        sync()
    }

    private func createPanel(
        for entry: GlassWorkspaceEntry,
        placement: GlassPlacement
    ) {
        let requestedFrame = Self.frame(for: placement)
        let displayFrame = recoveredDisplayFrame(requestedFrame)
        let panel = DesktopGlassPanel(glassID: entry.id, contentRect: displayFrame)

        configure(panel, for: entry)
        panel.delegate = self
        panel.contentView = NSHostingView(
            rootView: SchneeGlassDesktopGlassView(model: model, glassID: entry.id)
        )

        panels[entry.id] = PanelRecord(panel: panel, persistenceTask: nil)
        panel.orderFront(nil)
    }

    private func updatePanel(
        for entry: GlassWorkspaceEntry,
        placement: GlassPlacement
    ) {
        guard let record = panels[entry.id] else {
            return
        }

        configure(record.panel, for: entry)

        let persistedFrame = Self.frame(for: placement)
        let desiredFrame = recoveredDisplayFrame(persistedFrame)
        if !record.panel.inLiveResize,
           !Self.framesApproximatelyEqual(record.panel.frame, desiredFrame)
        {
            record.panel.suppressPlacementPersistence = true
            record.panel.setFrame(desiredFrame, display: true)
            record.panel.suppressPlacementPersistence = false
        }
    }

    private func configure(
        _ panel: DesktopGlassPanel,
        for entry: GlassWorkspaceEntry
    ) {
        panel.title = entry.title
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.minSize = NSSize(
            width: GlassPlacement.minimumWidth,
            height: GlassPlacement.minimumHeight
        )
        panel.level = .normal

        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        if entry.showOnAllSpaces {
            panel.collectionBehavior.insert(.canJoinAllSpaces)
        } else {
            panel.collectionBehavior.remove(.canJoinAllSpaces)
        }
    }

    private func removePanel(glassID: GlassID) {
        guard let record = panels.removeValue(forKey: glassID) else {
            return
        }
        record.persistenceTask?.cancel()
        record.panel.delegate = nil
        record.panel.close()
    }

    private func schedulePlacementPersistence(
        for panel: DesktopGlassPanel,
        delayNanoseconds: UInt64
    ) {
        let glassID = panel.glassID
        panels[glassID]?.persistenceTask?.cancel()

        let frame = panel.frame
        let displayHint = panel.screen?.localizedName
        guard let placement = try? GlassPlacement(
            x: frame.origin.x,
            y: frame.origin.y,
            width: frame.width,
            height: frame.height,
            displayHint: displayHint
        ) else {
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            } catch {
                return
            }

            for attempt in 0..<6 {
                guard !Task.isCancelled else {
                    return
                }

                switch await model.persistPlacement(glassID: glassID, placement: placement) {
                case .updated, .missing, .failed:
                    return
                case .busy:
                    guard attempt < 5 else {
                        return
                    }
                    do {
                        try await Task.sleep(nanoseconds: 200_000_000)
                    } catch {
                        return
                    }
                }
            }
        }

        panels[glassID]?.persistenceTask = task
    }

    private func recoveredDisplayFrame(_ requestedFrame: NSRect) -> NSRect {
        DesktopGlassFrameCalculator.recoveredFrame(
            requestedFrame: requestedFrame,
            visibleFrames: NSScreen.screens.map(\.visibleFrame),
            preferredVisibleFrame: NSScreen.main?.visibleFrame
        )
    }

    private static func frame(for placement: GlassPlacement) -> NSRect {
        NSRect(
            x: placement.x,
            y: placement.y,
            width: placement.width,
            height: placement.height
        )
    }

    private static func framesApproximatelyEqual(_ lhs: NSRect, _ rhs: NSRect) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) < 0.5 &&
            abs(lhs.origin.y - rhs.origin.y) < 0.5 &&
            abs(lhs.width - rhs.width) < 0.5 &&
            abs(lhs.height - rhs.height) < 0.5
    }
}

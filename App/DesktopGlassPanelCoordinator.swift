import AppKit
import SchneeGlassDomain
import SchneeGlassMacOSAdapter
import SchneeGlassPresentation
import SwiftUI

enum DesktopGlassPositionResetResult: Hashable, Sendable {
    case updated
    case noGlasses
    case busy
    case noAvailableScreen
    case failed
}

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
    private var visibilityMode: DesktopGlassVisibilityMode = .shown
    private var isPanelCreationSuppressed = false
    private var isStopped = false

    init(model: SchneeGlassWorkspaceModel) {
        self.model = model
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillTerminate(_:)),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }

    func sync() {
        guard !isStopped else {
            return
        }

        let entriesByID = Dictionary(uniqueKeysWithValues: model.glasses.map { ($0.id, $0) })

        for glassID in panels.keys where entriesByID[glassID] == nil {
            removePanel(glassID: glassID)
        }

        for entry in model.glasses {
            guard let placement = entry.placement else {
                continue
            }

            if panels[entry.id] == nil {
                guard !isPanelCreationSuppressed else {
                    continue
                }
                createPanel(for: entry, placement: placement)
            } else {
                updatePanel(for: entry, placement: placement)
            }
        }
    }

    func showAll() {
        guard !isStopped, !model.isMutatingConfiguration else {
            return
        }

        isPanelCreationSuppressed = false
        visibilityMode = .shown
        sync()
        for record in panels.values {
            record.panel.orderFrontRegardless()
        }
    }

    func hideAll() {
        guard !isStopped, !model.isMutatingConfiguration else {
            return
        }

        visibilityMode = .hidden
        for record in panels.values {
            record.panel.orderOut(nil)
        }
    }

    func toggleAllVisibility() {
        guard !isStopped,
              !model.isMutatingConfiguration,
              !model.glasses.isEmpty
        else {
            return
        }

        switch visibilityMode.toggled(hasGlasses: true) {
        case .shown:
            showAll()
        case .hidden:
            hideAll()
        }
    }

    func resetPositionsOnMainDisplay() async -> DesktopGlassPositionResetResult {
        guard !isStopped else {
            return .failed
        }
        guard !model.glasses.isEmpty else {
            return .noGlasses
        }
        guard !model.isMutatingConfiguration else {
            return .busy
        }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return .noAvailableScreen
        }

        let items = model.glasses.map {
            GlassPlacementResetItem(id: $0.id, currentPlacement: $0.placement)
        }
        let planned: [GlassID: GlassPlacement]
        do {
            planned = try GlassPlacementResetPlanner.plan(
                items: items,
                visibleFrame: screen.visibleFrame,
                displayHint: screen.localizedName
            )
        } catch {
            return .failed
        }

        cancelPendingPlacementPersistence()

        switch await model.resetGlassPositions(placements: planned) {
        case .updated:
            sync()
            showAll()
            return .updated
        case .noGlasses:
            return .noGlasses
        case .busy:
            return .busy
        case .failed:
            return .failed
        }
    }

    /// Removes the current Desktop Glass surface and prevents `sync()` from recreating panels
    /// until `showAll()` explicitly resumes presentation.
    ///
    /// Recovery uses this as a quiescence boundary before configuration replacement so an
    /// observation-driven `sync()` cannot recreate interactive panels while the transaction is
    /// suspended on persistence I/O.
    func closeAll() {
        isPanelCreationSuppressed = true
        let records = Array(panels.values)
        panels.removeAll(keepingCapacity: false)
        for record in records {
            record.persistenceTask?.cancel()
            record.panel.delegate = nil
            record.panel.close()
        }
    }

    func stop() {
        guard !isStopped else {
            return
        }
        isStopped = true
        NotificationCenter.default.removeObserver(self)
        closeAll()
    }

    func windowDidMove(_ notification: Notification) {
        guard !isStopped,
              let panel = notification.object as? DesktopGlassPanel,
              !panel.suppressPlacementPersistence
        else {
            return
        }
        schedulePlacementPersistence(for: panel, delayNanoseconds: 350_000_000)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard !isStopped,
              let panel = notification.object as? DesktopGlassPanel,
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

    @objc
    private func applicationWillTerminate(_ notification: Notification) {
        stop()
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
        if visibilityMode.presentsPanels {
            panel.orderFront(nil)
        }
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

    private func cancelPendingPlacementPersistence() {
        for glassID in Array(panels.keys) {
            guard var record = panels[glassID] else {
                continue
            }
            record.persistenceTask?.cancel()
            record.persistenceTask = nil
            panels[glassID] = record
        }
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
                guard !Task.isCancelled, !isStopped else {
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

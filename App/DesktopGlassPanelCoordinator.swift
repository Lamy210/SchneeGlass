import AppKit
import SchneeGlassDomain
import SchneeGlassMacOSAdapter
import SchneeGlassPresentation
import SwiftUI

private struct DesktopGlassWindowControls: View {
  let isPositionLocked: Bool
  let keepsOnTop: Bool
  let showsReconnect: Bool
  let canReconnect: Bool
  let onTogglePositionLock: @MainActor () -> Void
  let onToggleKeepOnTop: @MainActor () -> Void
  let onReconnect: @MainActor () -> Void

  var body: some View {
    HStack(spacing: 6) {
      Button(action: onTogglePositionLock) {
        Image(systemName: isPositionLocked ? "lock.fill" : "lock.open")
          .frame(width: 20, height: 20)
      }
      .help(isPositionLocked ? "Unlock Glass position" : "Lock Glass position")
      .accessibilityLabel(
        isPositionLocked ? "Unlock Glass position" : "Lock Glass position"
      )

      Button(action: onToggleKeepOnTop) {
        Image(systemName: keepsOnTop ? "pin.fill" : "pin")
          .frame(width: 20, height: 20)
      }
      .help(keepsOnTop ? "Stop keeping Glass on top" : "Keep Glass on top")
      .accessibilityLabel(
        keepsOnTop ? "Stop keeping Glass on top" : "Keep Glass on top"
      )

      if showsReconnect {
        Button(action: onReconnect) {
          Image(systemName: "arrow.triangle.2.circlepath")
            .frame(width: 20, height: 20)
        }
        .disabled(!canReconnect)
        .help("Reconnect original folder")
        .accessibilityLabel("Reconnect original folder")
      }
    }
    .buttonStyle(.plain)
    .controlSize(.small)
  }
}

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
    var windowControlsAccessoryController: NSTitlebarAccessoryViewController?

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
  private let windowPreferences: DesktopGlassWindowPreferences
  private var panels: [GlassID: PanelRecord] = [:]
  private var visibilityMode: DesktopGlassVisibilityMode = .shown
  private var isPanelCreationSuppressed = false
  private var isStopped = false

  init(
    model: SchneeGlassWorkspaceModel,
    windowPreferences: DesktopGlassWindowPreferences = DesktopGlassWindowPreferences()
  ) {
    self.model = model
    self.windowPreferences = windowPreferences
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

  /// Removes the current Desktop Glass surface and prevents \`sync()\` from recreating panels
  /// until \`showAll()\` explicitly resumes presentation.
  ///
  /// Recovery uses this as a quiescence boundary before configuration replacement so an
  /// observation-driven \`sync()\` cannot recreate interactive panels while the transaction is
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

    let constrainedFrame = DesktopGlassDragConstraint.constrainedFrame(
      requestedFrame: panel.frame,
      visibleFrames: NSScreen.screens.map(\.visibleFrame),
      preferredVisibleFrame: panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
    )
    if !Self.framesApproximatelyEqual(panel.frame, constrainedFrame) {
      panel.suppressPlacementPersistence = true
      panel.setFrame(constrainedFrame, display: true)
      panel.suppressPlacementPersistence = false
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
    configureWindowControlsAccessory(for: panel, entry: entry)

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
    configureWindowControlsAccessory(for: record.panel, entry: entry)

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
    let isPositionLocked = windowPreferences.isPositionLocked(for: entry.id)
    panel.isMovable = !isPositionLocked
    panel.isMovableByWindowBackground = !isPositionLocked
    panel.minSize = NSSize(
      width: GlassPlacement.minimumWidth,
      height: GlassPlacement.minimumHeight
    )
    panel.level = windowPreferences.keepsOnTop(entry.id) ? .floating : .normal

    panel.standardWindowButton(.closeButton)?.isHidden = true
    panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
    panel.standardWindowButton(.zoomButton)?.isHidden = true

    if entry.showOnAllSpaces {
      panel.collectionBehavior.insert(.canJoinAllSpaces)
    } else {
      panel.collectionBehavior.remove(.canJoinAllSpaces)
    }
  }

  private func configureWindowControlsAccessory(
    for panel: DesktopGlassPanel,
    entry: GlassWorkspaceEntry
  ) {
    let glassID = panel.glassID
    let showsReconnect = Self.showsReconnect(for: entry)
    let rootView = DesktopGlassWindowControls(
      isPositionLocked: windowPreferences.isPositionLocked(for: glassID),
      keepsOnTop: windowPreferences.keepsOnTop(glassID),
      showsReconnect: showsReconnect,
      canReconnect: showsReconnect && model.canReconnectSource(glassID: glassID),
      onTogglePositionLock: { [weak self] in
        self?.togglePositionLock(for: glassID)
      },
      onToggleKeepOnTop: { [weak self] in
        self?.toggleKeepOnTop(for: glassID)
      },
      onReconnect: { [weak self] in
        guard let self else {
          return
        }
        Task {
          await self.model.reconnectGlassSource(glassID: glassID)
        }
      }
    )

    if let controller = panel.windowControlsAccessoryController {
      controller.view = NSHostingView(rootView: rootView)
      return
    }

    let controller = NSTitlebarAccessoryViewController()
    controller.layoutAttribute = .left
    controller.view = NSHostingView(rootView: rootView)
    panel.addTitlebarAccessoryViewController(controller)
    panel.windowControlsAccessoryController = controller
  }

  private func togglePositionLock(for glassID: GlassID) {
    guard let panel = panels[glassID]?.panel else {
      return
    }

    let isLocked = !windowPreferences.isPositionLocked(for: glassID)
    windowPreferences.setPositionLocked(isLocked, for: glassID)
    panel.isMovable = !isLocked
    panel.isMovableByWindowBackground = !isLocked
    guard let entry = model.glasses.first(where: { $0.id == glassID }) else {
      return
    }
    configureWindowControlsAccessory(for: panel, entry: entry)
  }

  private func toggleKeepOnTop(for glassID: GlassID) {
    guard let panel = panels[glassID]?.panel else {
      return
    }

    let keepsOnTop = !windowPreferences.keepsOnTop(glassID)
    windowPreferences.setKeepsOnTop(keepsOnTop, for: glassID)
    panel.level = keepsOnTop ? .floating : .normal
    guard let entry = model.glasses.first(where: { $0.id == glassID }) else {
      return
    }
    configureWindowControlsAccessory(for: panel, entry: entry)
  }

  private func removePanel(glassID: GlassID) {
    guard let record = panels.removeValue(forKey: glassID) else {
      return
    }
    record.persistenceTask?.cancel()
    windowPreferences.removePositionLock(for: glassID)
    windowPreferences.removeKeepOnTop(for: glassID)
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
    guard
      let placement = try? GlassPlacement(
        x: frame.origin.x,
        y: frame.origin.y,
        width: frame.width,
        height: frame.height,
        displayHint: displayHint
      )
    else {
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

      guard !Task.isCancelled, !isStopped else {
        return
      }

      await model.persistPlacementWhenAvailable(
        glassID: glassID,
        placement: placement
      )
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

  private static func showsReconnect(for entry: GlassWorkspaceEntry) -> Bool {
    if case .unavailable = entry.contentState {
      return true
    }
    return false
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
    abs(lhs.origin.x - rhs.origin.x) < 0.5 && abs(lhs.origin.y - rhs.origin.y) < 0.5
      && abs(lhs.width - rhs.width) < 0.5 && abs(lhs.height - rhs.height) < 0.5
  }
}

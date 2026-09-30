import AppKit
import SchneeGlassDomain
import SchneeGlassMacOSAdapter
import SchneeGlassPresentation
import SwiftUI

private struct DesktopGlassWindowControls: View {
  let isPositionLocked: Bool
  let keepsOnTop: Bool
  let showsOnAllSpaces: Bool
  let opacityPreset: DesktopGlassOpacityPreset
  let usesCompactFileTiles: Bool
  let fileSortPreference: DesktopGlassFileSortPreference
  let putsFoldersFirst: Bool
  let showsReconnect: Bool
  let canReconnect: Bool
  let canRevealConnectedFolder: Bool
  let canRename: Bool
  let canChangeSpacesBehavior: Bool
  let canSnap: Bool
  let onTogglePositionLock: @MainActor () -> Void
  let onToggleKeepOnTop: @MainActor () -> Void
  let onToggleSpacesBehavior: @MainActor () -> Void
  let onSetOpacity: @MainActor (DesktopGlassOpacityPreset) -> Void
  let onToggleCompactFileTiles: @MainActor () -> Void
  let onSetFileSort: @MainActor (DesktopGlassFileSortPreference) -> Void
  let onToggleFoldersFirst: @MainActor () -> Void
  let onReconnect: @MainActor () -> Void
  let onRevealConnectedFolder: @MainActor () -> Void
  let onRename: @MainActor () -> Void
  let onSnap: @MainActor (DesktopGlassSnapPreset) -> Void

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

      Menu {
        Button(action: onRename) {
          Label("Rename Glass…", systemImage: "pencil")
        }
        .disabled(!canRename)

        if canRevealConnectedFolder {
          Button(action: onRevealConnectedFolder) {
            Label("Show Connected Folder in Finder", systemImage: "folder")
          }
        }

        Divider()

        Button(action: onToggleKeepOnTop) {
          Label(
            keepsOnTop ? "Stop Keeping on Top" : "Keep on Top",
            systemImage: keepsOnTop ? "checkmark.circle.fill" : "circle"
          )
        }

        Button(action: onToggleSpacesBehavior) {
          Label(
            showsOnAllSpaces ? "Stop Showing on All Spaces" : "Show on All Spaces",
            systemImage: showsOnAllSpaces ? "checkmark.circle.fill" : "circle"
          )
        }
        .disabled(!canChangeSpacesBehavior)

        Menu {
          Button {
            onSetOpacity(.full)
          } label: {
            Label(
              "100%",
              systemImage: opacityPreset == .full ? "checkmark" : "circle"
            )
          }
          Button {
            onSetOpacity(.ninety)
          } label: {
            Label(
              "90%",
              systemImage: opacityPreset == .ninety ? "checkmark" : "circle"
            )
          }
          Button {
            onSetOpacity(.eighty)
          } label: {
            Label(
              "80%",
              systemImage: opacityPreset == .eighty ? "checkmark" : "circle"
            )
          }
          Button {
            onSetOpacity(.seventy)
          } label: {
            Label(
              "70%",
              systemImage: opacityPreset == .seventy ? "checkmark" : "circle"
            )
          }
        } label: {
          Label(
            "Opacity \(opacityPreset.percentageLabel)",
            systemImage: "circle.lefthalf.filled"
          )
        }

        Button(action: onToggleCompactFileTiles) {
          Label(
            "Compact File Tiles",
            systemImage: usesCompactFileTiles ? "checkmark.circle.fill" : "circle"
          )
        }
        .accessibilityLabel(
          usesCompactFileTiles ? "Disable Compact File Tiles" : "Enable Compact File Tiles"
        )

        Menu {
          Button {
            onSetFileSort(.nameAscending)
          } label: {
            Label(
              "Name",
              systemImage: fileSortPreference == .nameAscending ? "checkmark" : "circle"
            )
          }
          Button {
            onSetFileSort(.modifiedNewest)
          } label: {
            Label(
              "Modified",
              systemImage: fileSortPreference == .modifiedNewest ? "checkmark" : "circle"
            )
          }
          Button {
            onSetFileSort(.sizeLargest)
          } label: {
            Label(
              "Size",
              systemImage: fileSortPreference == .sizeLargest ? "checkmark" : "circle"
            )
          }
        } label: {
          Label("Sort Displayed Files", systemImage: "arrow.up.arrow.down")
        }

        Button(action: onToggleFoldersFirst) {
          Label(
            "Folders First",
            systemImage: putsFoldersFirst ? "checkmark.circle.fill" : "circle"
          )
        }
        .accessibilityLabel(
          putsFoldersFirst ? "Disable Folders First" : "Enable Folders First"
        )

        Menu {
          Button("Top Left") {
            onSnap(.topLeft)
          }
          Button("Top Right") {
            onSnap(.topRight)
          }
          Button("Bottom Left") {
            onSnap(.bottomLeft)
          }
          Button("Bottom Right") {
            onSnap(.bottomRight)
          }
          Divider()
          Button("Center") {
            onSnap(.center)
          }
        } label: {
          Label("Snap Glass", systemImage: "rectangle.split.2x2")
        }
        .disabled(!canSnap)
      } label: {
        Image(systemName: "ellipsis.circle")
          .frame(width: 20, height: 20)
      }
      .menuStyle(.borderlessButton)
      .fixedSize()
      .help("Glass window options")
      .accessibilityLabel("Glass window options")

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
  private var isTerminationFlushStarted = false
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

  func reconcileWindowPreferencesWithCurrentGlasses() {
    guard !isStopped,
      model.hasAuthoritativeConfigurationSnapshot
    else {
      return
    }

    windowPreferences.retainPreferences(
      onlyFor: Set(model.glasses.map(\.id))
    )
  }

  func sync() {
    guard !isStopped else {
      return
    }

    reconcileWindowPreferencesWithCurrentGlasses()

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

  /// Persists the current on-screen placement before AppKit reaches final synchronous teardown.
  ///
  /// This bypasses the normal move/resize debounce so a Quit immediately after user interaction
  /// cannot discard the latest frame.
  func flushPlacementsForTermination() async {
    guard !isStopped, !isTerminationFlushStarted else {
      return
    }
    isTerminationFlushStarted = true

    var pendingPlacements: [(GlassID, GlassPlacement)] = []
    pendingPlacements.reserveCapacity(panels.count)
    var cancelledPersistenceTasks: [Task<Void, Never>] = []
    cancelledPersistenceTasks.reserveCapacity(panels.count)

    for glassID in Array(panels.keys) {
      guard var record = panels[glassID],
        let persistenceTask = record.persistenceTask
      else {
        continue
      }

      // Termination supersedes the normal debounce. Otherwise a move or resize immediately before
      // Quit is cancelled by final panel teardown and the latest placement is lost.
      persistenceTask.cancel()
      cancelledPersistenceTasks.append(persistenceTask)
      record.persistenceTask = nil
      panels[glassID] = record

      guard let placement = Self.placement(for: record.panel) else {
        continue
      }
      pendingPlacements.append((glassID, placement))
    }

    // A debounce task may already be inside model persistence when Quit starts. Cancellation alone
    // does not prove its MainActor cleanup has released the configuration-mutation gate, so join
    // every cancelled task before making the final placement write.
    for task in cancelledPersistenceTasks {
      await task.value
    }

    for (glassID, placement) in pendingPlacements {
      // Configuration mutations were quiesced before this flush and cancelled debounce tasks have
      // now finished. Make one final conditional persistence attempt without entering the normal
      // busy-retry loop.
      _ = await model.persistPlacement(
        glassID: glassID,
        placement: placement
      )
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
      rootView: desktopGlassView(for: entry.id)
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
    panel.alphaValue = CGFloat(windowPreferences.opacityPreset(for: entry.id).rawValue)

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
      showsOnAllSpaces: entry.showOnAllSpaces,
      opacityPreset: windowPreferences.opacityPreset(for: glassID),
      usesCompactFileTiles: windowPreferences.usesCompactFileTiles(for: glassID),
      fileSortPreference: windowPreferences.fileSortPreference(for: glassID),
      putsFoldersFirst: windowPreferences.putsFoldersFirst(for: glassID),
      showsReconnect: showsReconnect,
      canReconnect: showsReconnect && model.canReconnectSource(glassID: glassID),
      canRevealConnectedFolder:
        Self.allowsConnectedFolderAction(for: entry)
        && model.canRevealConnectedFolder(glassID: glassID),
      canRename: model.canRenameGlass(glassID: glassID),
      canChangeSpacesBehavior: model.canChangeSpacesBehavior(glassID: glassID),
      canSnap: !model.isMutatingConfiguration,
      onTogglePositionLock: { [weak self] in
        self?.togglePositionLock(for: glassID)
      },
      onToggleKeepOnTop: { [weak self] in
        self?.toggleKeepOnTop(for: glassID)
      },
      onToggleSpacesBehavior: { [weak self] in
        guard let self,
          let currentEntry = self.model.glasses.first(where: { $0.id == glassID })
        else {
          return
        }
        Task {
          await self.model.setShowOnAllSpaces(
            glassID: glassID,
            showOnAllSpaces: !currentEntry.showOnAllSpaces
          )
        }
      },
      onSetOpacity: { [weak self] preset in
        self?.setOpacityPreset(preset, for: glassID)
      },
      onToggleCompactFileTiles: { [weak self] in
        self?.toggleCompactFileTiles(for: glassID)
      },
      onSetFileSort: { [weak self] preference in
        self?.setFileSortPreference(preference, for: glassID)
      },
      onToggleFoldersFirst: { [weak self] in
        self?.toggleFoldersFirst(for: glassID)
      },
      onReconnect: { [weak self] in
        guard let self else {
          return
        }
        Task {
          await self.model.reconnectGlassSource(glassID: glassID)
        }
      },
      onRevealConnectedFolder: { [weak self] in
        self?.model.revealConnectedFolder(glassID: glassID)
      },
      onRename: { [weak self] in
        self?.promptForRename(glassID: glassID)
      },
      onSnap: { [weak self] preset in
        self?.snapGlass(glassID: glassID, preset: preset)
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

  private func desktopGlassView(for glassID: GlassID) -> SchneeGlassDesktopGlassView {
    SchneeGlassDesktopGlassView(
      model: model,
      glassID: glassID,
      fileGridDensity:
        windowPreferences.usesCompactFileTiles(for: glassID) ? .compact : .comfortable,
      fileSortOrder: Self.presentationSortOrder(
        for: windowPreferences.fileSortPreference(for: glassID)
      ),
      foldersFirst: windowPreferences.putsFoldersFirst(for: glassID)
    )
  }

  private func refreshDesktopGlassContent(for panel: DesktopGlassPanel) {
    let rootView = desktopGlassView(for: panel.glassID)
    if let hostingView = panel.contentView as? NSHostingView<SchneeGlassDesktopGlassView> {
      hostingView.rootView = rootView
    } else {
      panel.contentView = NSHostingView(rootView: rootView)
    }
  }

  private func snapGlass(
    glassID: GlassID,
    preset: DesktopGlassSnapPreset
  ) {
    guard !model.isMutatingConfiguration,
      let panel = panels[glassID]?.panel,
      let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first
    else {
      return
    }

    let snappedFrame = DesktopGlassSnapPlanner.frame(
      currentFrame: panel.frame,
      visibleFrame: screen.visibleFrame,
      preset: preset
    )
    panel.suppressPlacementPersistence = true
    panel.setFrame(snappedFrame, display: true)
    panel.suppressPlacementPersistence = false
    schedulePlacementPersistence(for: panel, delayNanoseconds: 0)
  }

  private func promptForRename(glassID: GlassID) {
    guard model.canRenameGlass(glassID: glassID),
      let entry = model.glasses.first(where: { $0.id == glassID })
    else {
      return
    }

    let textField = NSTextField(string: entry.title)
    textField.frame = NSRect(x: 0, y: 0, width: 280, height: 24)

    let alert = NSAlert()
    alert.messageText = "Rename Glass"
    alert.informativeText =
      "This changes only the Glass display name. The connected folder itself will not be renamed."
    alert.accessoryView = textField
    alert.addButton(withTitle: "Rename")
    alert.addButton(withTitle: "Cancel")

    guard alert.runModal() == .alertFirstButtonReturn else {
      return
    }

    let proposedTitle = textField.stringValue
    Task {
      await model.renameGlass(
        glassID: glassID,
        title: proposedTitle
      )
    }
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

  private func setOpacityPreset(
    _ preset: DesktopGlassOpacityPreset,
    for glassID: GlassID
  ) {
    guard let panel = panels[glassID]?.panel else {
      return
    }

    windowPreferences.setOpacityPreset(preset, for: glassID)
    panel.alphaValue = CGFloat(preset.rawValue)
    guard let entry = model.glasses.first(where: { $0.id == glassID }) else {
      return
    }
    configureWindowControlsAccessory(for: panel, entry: entry)
  }

  private func toggleCompactFileTiles(for glassID: GlassID) {
    guard let panel = panels[glassID]?.panel else {
      return
    }

    let usesCompactFileTiles = !windowPreferences.usesCompactFileTiles(for: glassID)
    windowPreferences.setUsesCompactFileTiles(usesCompactFileTiles, for: glassID)
    refreshDesktopGlassContent(for: panel)
    guard let entry = model.glasses.first(where: { $0.id == glassID }) else {
      return
    }
    configureWindowControlsAccessory(for: panel, entry: entry)
  }

  private func setFileSortPreference(
    _ preference: DesktopGlassFileSortPreference,
    for glassID: GlassID
  ) {
    guard let panel = panels[glassID]?.panel else {
      return
    }

    windowPreferences.setFileSortPreference(preference, for: glassID)
    refreshDesktopGlassContent(for: panel)
    guard let entry = model.glasses.first(where: { $0.id == glassID }) else {
      return
    }
    configureWindowControlsAccessory(for: panel, entry: entry)
  }

  private func toggleFoldersFirst(for glassID: GlassID) {
    guard let panel = panels[glassID]?.panel else {
      return
    }

    let foldersFirst = !windowPreferences.putsFoldersFirst(for: glassID)
    windowPreferences.setFoldersFirst(foldersFirst, for: glassID)
    refreshDesktopGlassContent(for: panel)
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
    windowPreferences.removeOpacityPreset(for: glassID)
    windowPreferences.removeCompactFileTiles(for: glassID)
    windowPreferences.removeFileSortPreference(for: glassID)
    windowPreferences.removeFoldersFirst(for: glassID)
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
    guard !isTerminationFlushStarted else {
      return
    }

    let glassID = panel.glassID
    panels[glassID]?.persistenceTask?.cancel()

    guard let placement = Self.placement(for: panel) else {
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

  private static func presentationSortOrder(
    for preference: DesktopGlassFileSortPreference
  ) -> DesktopGlassFileSortOrder {
    switch preference {
    case .nameAscending:
      return .nameAscending
    case .modifiedNewest:
      return .modifiedNewest
    case .sizeLargest:
      return .sizeLargest
    }
  }

  private static func showsReconnect(for entry: GlassWorkspaceEntry) -> Bool {
    if case .unavailable = entry.contentState {
      return true
    }
    return false
  }

  private static func allowsConnectedFolderAction(for entry: GlassWorkspaceEntry) -> Bool {
    switch entry.contentState {
    case .loading, .ready, .empty:
      return true
    case .unavailable, .failed:
      return false
    }
  }

  private static func placement(for panel: DesktopGlassPanel) -> GlassPlacement? {
    let frame = panel.frame
    return try? GlassPlacement(
      x: frame.origin.x,
      y: frame.origin.y,
      width: frame.width,
      height: frame.height,
      displayHint: panel.screen?.localizedName
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
    abs(lhs.origin.x - rhs.origin.x) < 0.5 && abs(lhs.origin.y - rhs.origin.y) < 0.5
      && abs(lhs.width - rhs.width) < 0.5 && abs(lhs.height - rhs.height) < 0.5
  }
}

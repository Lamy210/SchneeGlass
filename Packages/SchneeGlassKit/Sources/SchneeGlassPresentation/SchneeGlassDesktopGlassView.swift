import FileDomain
import SchneeGlassApplication
import SchneeGlassDesignSystem
import SchneeGlassDomain
import SwiftUI

public struct SchneeGlassDesktopGlassView: View {
  @Bindable private var model: SchneeGlassWorkspaceModel
  private let glassID: GlassID
  private let fileGridDensity: DesktopGlassFileGridDensity
  private let fileSortOrder: DesktopGlassFileSortOrder
  private let foldersFirst: Bool
  private let persistedDisplayMode: GlassFileDisplayMode?
  private let onDisplayModeChange: (@MainActor (GlassFileDisplayMode) -> Void)?

  public init(
    model: SchneeGlassWorkspaceModel,
    glassID: GlassID,
    fileGridDensity: DesktopGlassFileGridDensity = .comfortable,
    fileSortOrder: DesktopGlassFileSortOrder = .nameAscending,
    foldersFirst: Bool = false,
    persistedDisplayMode: GlassFileDisplayMode? = nil,
    onDisplayModeChange: (@MainActor (GlassFileDisplayMode) -> Void)? = nil
  ) {
    self._model = Bindable(wrappedValue: model)
    self.glassID = glassID
    self.fileGridDensity = fileGridDensity
    self.fileSortOrder = fileSortOrder
    self.foldersFirst = foldersFirst
    self.persistedDisplayMode = persistedDisplayMode
    self.onDisplayModeChange = onDisplayModeChange
  }

  public var body: some View {
    Group {
      if let entry = model.glasses.first(where: { $0.id == glassID }) {
        DesktopGlassSurface(
          entry: entry,
          fileGridDensity: fileGridDensity,
          fileSortOrder: fileSortOrder,
          foldersFirst: foldersFirst,
          persistedDisplayMode: persistedDisplayMode,
          onDisplayModeChange: onDisplayModeChange,
          canChangeDisplayMode: model.hasAuthoritativeConfigurationSnapshot
            && !model.isMutatingConfiguration,
          canRemove: model.canMutateConfiguration
            && GlassInteractionPolicy.allowsRemoval(during: entry.interactionState),
          canRefresh: model.canRefreshGlass(glassID: entry.id),
          canReconnectSource: model.canReconnectSource(glassID: entry.id),
          onRefresh: {
            Task {
              await model.refreshGlass(glassID: entry.id)
            }
          },
          onReconnectSource: {
            Task {
              await model.reconnectGlassSource(glassID: entry.id)
            }
          },
          onOpen: model.open,
          onReveal: model.revealInFinder,
          onRemove: {
            Task {
              await model.removeGlass(id: entry.id)
            }
          },
          onPlanDrop: { urls in
            let plan = await model.planDrop(
              glassID: entry.id,
              sourceURLs: urls
            )
            if case .copy = plan {
              return true
            }
            return false
          },
          onCancelDrop: {
            model.cancelDrop(glassID: entry.id)
          },
          onCancelCopy: {
            Task {
              await model.cancelCopy(glassID: entry.id)
            }
          },
          onPerformDrop: { urls in
            _ = await model.performDrop(
              glassID: entry.id,
              sourceURLs: urls
            )
          }
        )
      } else {
        Color.clear
      }
    }
  }
}

struct DesktopGlassSurface: View {
  @Environment(\.locale) private var locale
  let entry: GlassWorkspaceEntry
  let fileGridDensity: DesktopGlassFileGridDensity
  let fileSortOrder: DesktopGlassFileSortOrder?
  let foldersFirst: Bool
  let persistedDisplayMode: GlassFileDisplayMode?
  let onDisplayModeChange: (@MainActor (GlassFileDisplayMode) -> Void)?
  let canChangeDisplayMode: Bool
  let canRemove: Bool
  let canRefresh: Bool
  let canReconnectSource: Bool
  let onRefresh: () -> Void
  let onReconnectSource: () -> Void
  let onOpen: (GlassItem) -> Void
  let onReveal: (GlassItem) -> Void
  let onRemove: () -> Void
  let onPlanDrop: @MainActor ([URL]) async -> Bool
  let onCancelDrop: @MainActor () -> Void
  let onCancelCopy: @MainActor () -> Void
  let onPerformDrop: @MainActor ([URL]) async -> Void

  @State private var showsRemoveConfirmation = false
  @State private var fileFilter = DesktopGlassFilterSession()
  @State private var localDisplayMode: GlassFileDisplayMode = .grid

  private var fileDisplayMode: GlassFileDisplayMode {
    persistedDisplayMode ?? localDisplayMode
  }

  private var allowsDisplayModeChange: Bool {
    canChangeDisplayMode
      && (persistedDisplayMode == nil || onDisplayModeChange != nil)
      && GlassFileDisplayMode.allowsChange(during: entry.interactionState)
  }
  @FocusState private var isFileFilterFocused: Bool

  init(
    entry: GlassWorkspaceEntry,
    fileGridDensity: DesktopGlassFileGridDensity = .comfortable,
    fileSortOrder: DesktopGlassFileSortOrder? = nil,
    foldersFirst: Bool = false,
    persistedDisplayMode: GlassFileDisplayMode? = nil,
    onDisplayModeChange: (@MainActor (GlassFileDisplayMode) -> Void)? = nil,
    canChangeDisplayMode: Bool = true,
    canRemove: Bool,
    canRefresh: Bool = false,
    canReconnectSource: Bool = false,
    onRefresh: @escaping () -> Void = {},
    onReconnectSource: @escaping () -> Void = {},
    onOpen: @escaping (GlassItem) -> Void,
    onReveal: @escaping (GlassItem) -> Void,
    onRemove: @escaping () -> Void,
    onPlanDrop: @escaping @MainActor ([URL]) async -> Bool,
    onCancelDrop: @escaping @MainActor () -> Void,
    onCancelCopy: @escaping @MainActor () -> Void,
    onPerformDrop: @escaping @MainActor ([URL]) async -> Void
  ) {
    self.entry = entry
    self.fileGridDensity = fileGridDensity
    self.fileSortOrder = fileSortOrder
    self.foldersFirst = foldersFirst
    self.persistedDisplayMode = persistedDisplayMode
    self.onDisplayModeChange = onDisplayModeChange
    self.canChangeDisplayMode = canChangeDisplayMode
    self.canRemove = canRemove
    self.canRefresh = canRefresh
    self.canReconnectSource = canReconnectSource
    self.onRefresh = onRefresh
    self.onReconnectSource = onReconnectSource
    self.onOpen = onOpen
    self.onReveal = onReveal
    self.onRemove = onRemove
    self.onPlanDrop = onPlanDrop
    self.onCancelDrop = onCancelDrop
    self.onCancelCopy = onCancelCopy
    self.onPerformDrop = onPerformDrop
  }

  var body: some View {
    VStack(alignment: .leading, spacing: SchneeGlassSpacing.surfaceContent) {
      header
      content
    }
    .padding(SchneeGlassPadding.desktopGlass)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(.regularMaterial)
    .overlay {
      RoundedRectangle(cornerRadius: SchneeGlassRadius.glassSurface, style: .continuous)
        .stroke(borderStyle, lineWidth: borderWidth)
    }
    .clipShape(
      RoundedRectangle(cornerRadius: SchneeGlassRadius.glassSurface, style: .continuous)
    )
    .overlay {
      FileURLDropTarget(
        onPlan: onPlanDrop,
        onExit: onCancelDrop,
        onPerform: onPerformDrop
      )
    }
    .overlay {
      interactionOverlay
        .allowsHitTesting(
          GlassInteractionPolicy.allowsCopyCancellation(
            during: entry.interactionState
          )
        )
    }
    .alert(
      GlassLocalizedText.removeGlassTitle.resolve(locale: locale),
      isPresented: $showsRemoveConfirmation
    ) {
      Button(GlassLocalizedText.cancelAction.resolve(locale: locale), role: .cancel) {}
      Button(
        GlassLocalizedText.removeGlassAction.resolve(locale: locale),
        role: .destructive,
        action: onRemove
      )
    } message: {
      Text(GlassLocalizedText.removeGlassDetail.resolve(locale: locale))
    }
    .accessibilityElement(children: .contain)
    .onChange(of: supportsFileFilter) { _, supported in
      if !supported {
        isFileFilterFocused = false
        fileFilter.discardFocusRequest()
      }
    }
  }

  private var supportsFileFilter: Bool {
    if case .ready = entry.contentState {
      return true
    }
    return false
  }

  private var header: some View {
    HStack(spacing: SchneeGlassSpacing.controlGroup) {
      Image(systemName: "folder")
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)

      Text(entry.title)
        .font(SchneeGlassTypography.surfaceTitle)
        .lineLimit(1)

      Spacer(minLength: SchneeGlassSpacing.controlGroup)
      statusLabel

      Menu {
        Button(GlassLocalizedText.refreshFiles.resolve(locale: locale), action: onRefresh)
          .disabled(!canRefresh)

        if DesktopGlassReconnectMenuPolicy.isVisible(for: entry.contentState) {
          Button(
            GlassLocalizedText.reconnectOriginalFolder.resolve(locale: locale),
            action: onReconnectSource
          )
          .disabled(
            !DesktopGlassReconnectMenuPolicy.isEnabled(
              for: entry.contentState,
              canReconnectSource: canReconnectSource
            )
          )
        }

        Button(
          (fileFilter.isVisible ? GlassLocalizedText.hideFileFilter : .filterFiles).resolve(
            locale: locale)
        ) {
          if fileFilter.isVisible {
            closeFileFilter()
          } else {
            fileFilter.open(ifSupported: supportsFileFilter)
          }
        }
        .disabled(!supportsFileFilter && !fileFilter.isVisible)

        Button(fileDisplayMode.localizedAlternateMenuTitle(locale: locale)) {
          guard allowsDisplayModeChange else { return }
          let next = fileDisplayMode.alternate
          if persistedDisplayMode != nil {
            onDisplayModeChange?(next)
          } else {
            localDisplayMode = next
          }
        }
        .disabled(!allowsDisplayModeChange)

        Divider()

        Button(GlassLocalizedText.removeGlassMenu.resolve(locale: locale), role: .destructive) {
          showsRemoveConfirmation = true
        }
        .disabled(!canRemove)
      } label: {
        Image(systemName: "ellipsis")
          .frame(
            width: SchneeGlassMetrics.menuIconFrame,
            height: SchneeGlassMetrics.menuIconFrame
          )
      }
      .menuStyle(.borderlessButton)
      .fixedSize()
      .accessibilityLabel(GlassLocalizedText.glassOptions.resolve(locale: locale))
    }
  }

  @ViewBuilder
  private var statusLabel: some View {
    if let presentation = GlassContentStatusPresentation.make(
      for: entry.contentState, locale: locale
    ) {
      Image(systemName: presentation.systemImage)
        .foregroundStyle(.secondary)
        .accessibilityLabel(presentation.label)
    } else {
      // The loading message in the content already supplies the VoiceOver status.
      ProgressView()
        .controlSize(.small)
        .accessibilityHidden(true)
    }
  }

  @ViewBuilder
  private var content: some View {
    switch entry.contentState {
    case .loading:
      HStack(spacing: SchneeGlassSpacing.controlGroup) {
        ProgressView()
          .controlSize(.small)
          .accessibilityHidden(true)
        Text(GlassLocalizedText.loadingFolder.resolve(locale: locale))
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)

    case .ready(let snapshot):
      if fileFilter.isVisible {
        VStack(spacing: SchneeGlassSpacing.controlGroup) {
          HStack(spacing: SchneeGlassSpacing.controlGroup) {
            TextField(
              GlassLocalizedText.filterFilesByName.resolve(locale: locale), text: $fileFilter.query
            )
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel(GlassLocalizedText.filterFilesByName.resolve(locale: locale))
            .focused($isFileFilterFocused)
            .onAppear {
              if fileFilter.consumeFocusRequest() {
                isFileFilterFocused = true
              }
            }
            .onExitCommand {
              if isFileFilterFocused {
                closeFileFilter()
              }
            }

            Button {
              closeFileFilter()
            } label: {
              Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(GlassLocalizedText.closeFileFilter.resolve(locale: locale))
          }

          Picker(GlassLocalizedText.fileType.resolve(locale: locale), selection: $fileFilter.kind) {
            ForEach(DesktopGlassFileKindFilter.allCases) { kind in
              Text(kind.localizedLabel(locale: locale)).tag(kind)
            }
          }
          .pickerStyle(.menu)
          .controlSize(.small)

          fileGridScrollView(snapshot: snapshot)
        }
      } else {
        fileGridScrollView(snapshot: snapshot)
      }

    case .empty:
      let presentation = DesktopGlassEmptyPresentation.make(locale: locale)
      VStack(spacing: SchneeGlassSpacing.controlGroup) {
        Spacer()
        SchneeGlassStateMessage(
          systemImage: "tray.and.arrow.down",
          title: presentation.title,
          detail: presentation.detail,
          detailAlignment: .center
        )
        Spacer()
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)

    case .unavailable(let reason):
      let presentation = GlassUnavailablePresentation.make(for: reason, locale: locale)
      VStack(spacing: SchneeGlassSpacing.controlGroup) {
        Spacer()
        SchneeGlassStateMessage(
          systemImage: "externaldrive.badge.exclamationmark",
          title: presentation.title,
          detail: presentation.detail,
          detailAlignment: .center
        )
        if DesktopGlassReconnectMenuPolicy.isEnabled(
          for: entry.contentState,
          canReconnectSource: canReconnectSource
        ) {
          Button(
            GlassLocalizedText.reconnectOriginalFolder.resolve(locale: locale),
            action: onReconnectSource
          )
          .buttonStyle(.borderedProminent)
        }
        Spacer()
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)

    case .failed(let error):
      let canRetryNow = GlassInlineRefreshPolicy.isVisible(
        for: entry.contentState, canRefresh: canRefresh
      )
      let presentation = GlassContentFailurePresentation.make(
        for: error, locale: locale, canRetryNow: canRetryNow
      )
      VStack(spacing: SchneeGlassSpacing.controlGroup) {
        Spacer()
        SchneeGlassStateMessage(
          systemImage: "arrow.clockwise.circle",
          title: presentation.title,
          detail: presentation.detail,
          detailAlignment: .center
        )
        if canRetryNow {
          Button(
            GlassLocalizedText.refreshFiles.resolve(locale: locale),
            action: onRefresh
          )
          .buttonStyle(.borderedProminent)
        }
        Spacer()
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private func closeFileFilter() {
    isFileFilterFocused = false
    fileFilter.close()
  }

  private func fileGridScrollView(snapshot: FolderSnapshot) -> some View {
    ScrollView {
      DesktopFileContent(
        snapshot: snapshot,
        displayMode: fileDisplayMode,
        density: fileGridDensity,
        sortOrder: fileSortOrder,
        foldersFirst: foldersFirst,
        filterQuery: fileFilter.effectiveQuery,
        kindFilter: fileFilter.effectiveKind,
        onOpen: onOpen,
        onReveal: onReveal
      )
    }
  }

  private var borderStyle: AnyShapeStyle {
    switch entry.interactionState {
    case .dropValid:
      return AnyShapeStyle(.tint.opacity(0.8))
    case .dropInvalid:
      return AnyShapeStyle(.secondary.opacity(0.8))
    case .copying:
      return AnyShapeStyle(.tint.opacity(0.55))
    case .idle, .hovered:
      return AnyShapeStyle(.separator.opacity(0.45))
    }
  }

  private var borderWidth: CGFloat {
    switch entry.interactionState {
    case .dropValid, .dropInvalid, .copying:
      return 2
    case .idle, .hovered:
      return 1
    }
  }

  @ViewBuilder
  private var interactionOverlay: some View {
    switch entry.interactionState {
    case .idle:
      EmptyView()

    case .hovered:
      let presentation = GlassInteractionPresentation.hovered(surface: .desktop, locale: locale)
      overlayCard(
        icon: symbolName(from: presentation) ?? "ellipsis",
        title: presentation.title,
        detail: presentation.detail
      )

    case .dropValid(let plan):
      if let presentation = GlassInteractionPresentation.dropValid(
        plan: plan,
        glassTitle: entry.title,
        surface: .desktop,
        locale: locale
      ) {
        overlayCard(
          icon: symbolName(from: presentation) ?? "doc.on.doc",
          title: presentation.title,
          detail: presentation.detail
        )
      }

    case .dropInvalid(let reason):
      let presentation = GlassInteractionPresentation.dropInvalid(
        reason: reason,
        glassTitle: entry.title,
        surface: .desktop,
        locale: locale
      )
      overlayCard(
        icon: symbolName(from: presentation) ?? "nosign",
        title: presentation.title,
        detail: presentation.detail
      )

    case .copying(let progress):
      let presentation = GlassInteractionPresentation.copying(
        progress: progress,
        glassTitle: entry.title,
        surface: .desktop,
        locale: locale
      )
      overlayCard(
        icon: "doc.on.doc",
        title: presentation.title,
        detail: presentation.detail,
        showsProgress: true,
        onCancelCopy: onCancelCopy
      )
    }
  }

  private func symbolName(from presentation: GlassInteractionPresentation) -> String? {
    guard case .symbol(let systemImage) = presentation.indicator else {
      return nil
    }
    return systemImage
  }

  private func overlayCard(
    icon: String,
    title: String,
    detail: String?,
    showsProgress: Bool = false,
    onCancelCopy: (() -> Void)? = nil
  ) -> some View {
    ZStack {
      Rectangle()
        .fill(.black.opacity(0.12))

      VStack(spacing: SchneeGlassSpacing.controlGroup) {
        if showsProgress {
          ProgressView()
            .controlSize(.small)
            .accessibilityHidden(true)
        } else {
          Image(systemName: icon)
            .font(SchneeGlassTypography.largeSymbol)
        }

        Text(title)
          .font(SchneeGlassTypography.strongBody)
          .multilineTextAlignment(.center)

        if let detail {
          Text(detail)
            .font(SchneeGlassTypography.supporting)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }

        if let onCancelCopy {
          Button(
            GlassLocalizedText.cancelCopy.resolve(locale: locale),
            role: .cancel, action: onCancelCopy
          )
          .buttonStyle(.bordered)
          .controlSize(.small)
          .accessibilityLabel(GlassLocalizedText.cancelCopy.resolve(locale: locale))
        }
      }
      .padding(SchneeGlassPadding.desktopOverlayContent)
      .background(
        .thickMaterial,
        in: RoundedRectangle(
          cornerRadius: SchneeGlassRadius.desktopDropOverlay,
          style: .continuous
        )
      )
      .padding(SchneeGlassPadding.desktopOverlayInset)
    }
  }
}

private struct DesktopFileContent: View {
  @Environment(\.locale) private var locale
  let snapshot: FolderSnapshot
  let displayMode: GlassFileDisplayMode
  let density: DesktopGlassFileGridDensity
  let sortOrder: DesktopGlassFileSortOrder?
  let foldersFirst: Bool
  let filterQuery: String
  let kindFilter: DesktopGlassFileKindFilter
  let onOpen: (GlassItem) -> Void
  let onReveal: (GlassItem) -> Void

  private var displayedItems: [GlassItem] {
    DesktopGlassDisplayedItems.make(
      snapshot.items, sortOrder: sortOrder, foldersFirst: foldersFirst,
      query: filterQuery, kind: kindFilter
    )
  }

  private var columns: [GridItem] {
    [
      GridItem(
        .adaptive(
          minimum: density.minimumTileWidth,
          maximum: density.maximumTileWidth
        ),
        spacing: density.columnSpacing,
        alignment: .top
      )
    ]
  }

  var body: some View {
    let items = displayedItems
    if let status = DesktopGlassFileNameFilter.statusText(
      query: filterQuery,
      loadedCount: snapshot.items.count,
      matchingCount: items.count,
      isTruncated: snapshot.isTruncated,
      kind: kindFilter,
      locale: locale
    ) {
      VStack(alignment: .leading, spacing: SchneeGlassSpacing.controlGroup) {
        Label(status, systemImage: "info.circle")
          .font(SchneeGlassTypography.supporting)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
        fileItems(items)
      }
    } else {
      fileItems(items)
    }
  }

  @ViewBuilder
  private func fileItems(_ items: [GlassItem]) -> some View {
    switch displayMode {
    case .grid:
      LazyVGrid(columns: columns, alignment: .leading, spacing: density.rowSpacing) {
        ForEach(items) { item in
          GlassInteractiveFileTile(item: item, onOpen: onOpen, onReveal: onReveal)
        }
      }
    case .list:
      LazyVStack(alignment: .leading, spacing: SchneeGlassSpacing.compactContent) {
        ForEach(items) { item in
          GlassInteractiveFileTile(
            item: item, onOpen: onOpen, onReveal: onReveal, displayMode: .list
          )
        }
      }
    }
  }
}

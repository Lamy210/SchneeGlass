import FileDomain
import SchneeGlassApplication
import SchneeGlassDesignSystem
import SchneeGlassDomain
import SwiftUI

public struct SchneeGlassWorkspaceView: View {
  @Environment(\.locale) private var locale
  @Bindable private var model: SchneeGlassWorkspaceModel

  public init(model: SchneeGlassWorkspaceModel) {
    self._model = Bindable(wrappedValue: model)
  }

  public var body: some View {
    WorkspaceSurface(
      glasses: model.glasses,
      isCreatingGlass: model.isCreatingGlass,
      isRestoring: model.isRestoring,
      isMutatingConfiguration: model.isMutatingConfiguration,
      canAddGlass: model.canAddGlass,
      requiresConfigurationRecovery: model.requiresConfigurationRecovery,
      userMessage: model.localizedUserMessage(locale: locale),
      onAddGlass: {
        Task {
          await model.addGlass()
        }
      },
      onDismissMessage: model.dismissMessage,
      onOpen: model.open,
      onReveal: model.revealInFinder,
      onRemove: { glassID in
        Task {
          await model.removeGlass(id: glassID)
        }
      },
      onPlanDrop: { glassID, urls in
        let plan = await model.planDrop(
          glassID: glassID,
          sourceURLs: urls
        )
        if case .copy = plan {
          return true
        }
        return false
      },
      onCancelDrop: { glassID in
        model.cancelDrop(glassID: glassID)
      },
      onCancelCopy: { glassID in
        Task {
          await model.cancelCopy(glassID: glassID)
        }
      },
      onPerformDrop: { glassID, urls in
        _ = await model.performDrop(
          glassID: glassID,
          sourceURLs: urls
        )
      },
      canReconnectSource: { model.canReconnectSource(glassID: $0) },
      onReconnectSource: { glassID in
        Task {
          await model.reconnectGlassSource(glassID: glassID)
        }
      },
      canRefresh: { model.canRefreshGlass(glassID: $0) },
      onRefresh: { glassID in
        Task {
          await model.refreshGlass(glassID: glassID)
        }
      },
      canRevealConnectedFolder: { glassID in
        model.canMutateConfiguration && model.canRevealConnectedFolder(glassID: glassID)
      },
      onRevealConnectedFolder: { glassID in
        guard model.canMutateConfiguration, model.canRevealConnectedFolder(glassID: glassID)
        else {
          return
        }
        model.revealConnectedFolder(glassID: glassID)
      },
      canRename: { model.canRenameGlass(glassID: $0) },
      onRename: { glassID, title in
        Task {
          await model.renameGlass(glassID: glassID, title: title)
        }
      },
      canRemove: { model.canRemoveGlass(glassID: $0) }
    )
  }
}

struct WorkspaceSurface: View {
  @Environment(\.locale) private var locale
  let glasses: [GlassWorkspaceEntry]
  let isCreatingGlass: Bool
  let isRestoring: Bool
  let isMutatingConfiguration: Bool
  let canAddGlass: Bool
  let requiresConfigurationRecovery: Bool
  let userMessage: String?
  let onAddGlass: @MainActor () -> Void
  let onDismissMessage: @MainActor () -> Void
  let onOpen: @MainActor (GlassItem) -> Void
  let onReveal: @MainActor (GlassItem) -> Void
  let onRemove: @MainActor (GlassID) -> Void
  let onPlanDrop: @MainActor (GlassID, [URL]) async -> Bool
  let onCancelDrop: @MainActor (GlassID) -> Void
  let onCancelCopy: @MainActor (GlassID) -> Void
  let onPerformDrop: @MainActor (GlassID, [URL]) async -> Void
  var canReconnectSource: @MainActor (GlassID) -> Bool = { _ in false }
  var onReconnectSource: @MainActor (GlassID) -> Void = { _ in }
  var canRefresh: @MainActor (GlassID) -> Bool = { _ in false }
  var onRefresh: @MainActor (GlassID) -> Void = { _ in }
  var canRevealConnectedFolder: @MainActor (GlassID) -> Bool = { _ in false }
  var onRevealConnectedFolder: @MainActor (GlassID) -> Void = { _ in }
  var canRename: @MainActor (GlassID) -> Bool = { _ in false }
  var onRename: @MainActor (GlassID, String) -> Void = { _, _ in }
  var canRemove: @MainActor (GlassID) -> Bool = { _ in true }

  @State private var isSearchVisible = false
  @State private var glassQuery = ""
  @State private var glassStatus: WorkspaceGlassStatusFilter = .all
  @FocusState private var isSearchFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      header
      if isSearchVisible && !glasses.isEmpty {
        searchBar
      }
      Divider()
      content
    }
    .frame(minWidth: 520, minHeight: 420)
    .background(.background)
    .onChange(of: glasses.isEmpty) { _, isEmpty in
      if isEmpty {
        closeSearch()
      }
    }
  }

  private func closeSearch() {
    isSearchFocused = false
    isSearchVisible = false
    resetSearchFilters()
  }

  private func resetSearchFilters() {
    glassQuery = ""
    glassStatus = .all
  }

  private var searchBar: some View {
    HStack(spacing: SchneeGlassSpacing.surfaceContent) {
      TextField(GlassLocalizedText.findGlassByName.resolve(locale: locale), text: $glassQuery)
        .textFieldStyle(.roundedBorder)
        .focused($isSearchFocused)
        .onAppear { isSearchFocused = true }
        .onExitCommand { closeSearch() }

      Picker(GlassLocalizedText.glassStatus.resolve(locale: locale), selection: $glassStatus) {
        ForEach(WorkspaceGlassStatusFilter.allCases) { status in
          Text(status.localizedLabel(locale: locale)).tag(status)
        }
      }
      .labelsHidden()
      .accessibilityLabel(GlassLocalizedText.glassStatus.resolve(locale: locale))
      .fixedSize()

      Button(GlassLocalizedText.clearSearch.resolve(locale: locale), action: resetSearchFilters)
        .disabled(glassQuery.isEmpty && glassStatus == .all)

      Button(GlassLocalizedText.doneSearch.resolve(locale: locale), action: closeSearch)
    }
    .padding(SchneeGlassPadding.workspaceContent)
  }

  private var header: some View {
    HStack(spacing: SchneeGlassSpacing.surfaceContent) {
      Image(systemName: "snowflake")
        .font(.title2.weight(.medium))
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 2) {
        Text("SchneeGlass")
          .font(SchneeGlassTypography.surfaceTitle)
        Text(GlassLocalizedText.workspaceTagline.resolve(locale: locale))
          .font(SchneeGlassTypography.supporting)
          .foregroundStyle(.secondary)
      }

      Spacer()

      if isRestoring {
        HStack(spacing: 7) {
          ProgressView()
            .controlSize(.small)
            .accessibilityHidden(true)
          Text(GlassLocalizedText.restoringStatus.resolve(locale: locale))
            .font(SchneeGlassTypography.supporting)
            .foregroundStyle(.secondary)
        }
      }

      if !glasses.isEmpty {
        Button {
          if isSearchVisible {
            isSearchFocused = true
          } else {
            isSearchVisible = true
          }
        } label: {
          Image(systemName: "magnifyingglass")
        }
        .keyboardShortcut("f", modifiers: .command)
        .accessibilityLabel(GlassLocalizedText.findGlass.resolve(locale: locale))
        .help(GlassLocalizedText.findGlassByName.resolve(locale: locale))
      }

      Button(action: onAddGlass) {
        if isCreatingGlass {
          ProgressView()
            .controlSize(.small)
            .accessibilityHidden(true)
        } else {
          Label(GlassLocalizedText.addGlass.resolve(locale: locale), systemImage: "plus")
        }
      }
      .disabled(!canAddGlass)
      .keyboardShortcut("n", modifiers: .command)
      .accessibilityLabel(
        isCreatingGlass
          ? GlassLocalizedText.creatingGlass.resolve(locale: locale)
          : GlassLocalizedText.addGlass.resolve(locale: locale)
      )
    }
    .padding(SchneeGlassPadding.workspaceContent)
  }

  @ViewBuilder
  private var content: some View {
    if glasses.isEmpty {
      emptyWorkspace
    } else {
      let visibleGlasses = WorkspaceGlassSearch.matchingEntries(
        glasses,
        query: isSearchVisible ? glassQuery : "",
        status: isSearchVisible ? glassStatus : .all
      )
      ScrollView {
        LazyVStack(spacing: SchneeGlassSpacing.workspaceSection) {
          if let userMessage {
            messageBanner(userMessage)
          }

          if isSearchVisible {
            Text(
              WorkspaceGlassSearch.resultSummary(
                visible: visibleGlasses.count, total: glasses.count, locale: locale)
            )
            .font(SchneeGlassTypography.supporting)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)

            if visibleGlasses.isEmpty {
              SchneeGlassStateMessage(
                systemImage: "magnifyingglass",
                title: GlassLocalizedText.noMatchingGlasses.resolve(locale: locale),
                detail: GlassLocalizedText.noMatchingGlassesDetail.resolve(locale: locale)
              )
            }
          }

          ForEach(visibleGlasses) { entry in
            GlassPreviewSurface(
              entry: entry,
              canRemove: !isMutatingConfiguration
                && !requiresConfigurationRecovery
                && canRemove(entry.id)
                && GlassInteractionPolicy.allowsRemoval(during: entry.interactionState),
              onOpen: onOpen,
              onReveal: onReveal,
              onRemove: {
                onRemove(entry.id)
              },
              onPlanDrop: { urls in
                await onPlanDrop(entry.id, urls)
              },
              onCancelDrop: {
                onCancelDrop(entry.id)
              },
              onCancelCopy: {
                onCancelCopy(entry.id)
              },
              onPerformDrop: { urls in
                await onPerformDrop(entry.id, urls)
              },
              canReconnectSource: canReconnectSource(entry.id),
              onReconnectSource: {
                onReconnectSource(entry.id)
              },
              canRefresh: canRefresh(entry.id),
              onRefresh: { onRefresh(entry.id) },
              canRevealConnectedFolder: canRevealConnectedFolder(entry.id),
              onRevealConnectedFolder: { onRevealConnectedFolder(entry.id) },
              canRename: canRename(entry.id),
              onRename: { title in onRename(entry.id, title) }
            )
          }
        }
        .padding(SchneeGlassPadding.workspaceContent)
      }
    }
  }

  private var emptyWorkspace: some View {
    VStack(spacing: SchneeGlassSpacing.workspaceSection) {
      Spacer()

      if isRestoring {
        ProgressView()
          .controlSize(.regular)
          .accessibilityHidden(true)
        Text(GlassLocalizedText.restoringGlasses.resolve(locale: locale))
          .font(SchneeGlassTypography.body)
          .foregroundStyle(.secondary)
      } else if requiresConfigurationRecovery {
        Image(systemName: "externaldrive.badge.exclamationmark")
          .font(.system(size: 44, weight: .regular))
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)

        VStack(spacing: SchneeGlassSpacing.compactContent) {
          Text(GlassLocalizedText.configurationRecoveryTitle.resolve(locale: locale))
            .font(SchneeGlassTypography.emptyStateTitle)
          Text(GlassLocalizedText.configurationRecoveryDetail.resolve(locale: locale))
            .font(SchneeGlassTypography.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 440)
        }
      } else {
        Image(systemName: "rectangle.stack.badge.plus")
          .font(.system(size: 44, weight: .regular))
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)

        VStack(spacing: SchneeGlassSpacing.compactContent) {
          Text(GlassLocalizedText.firstGlassTitle.resolve(locale: locale))
            .font(SchneeGlassTypography.emptyStateTitle)
          Text(GlassLocalizedText.firstGlassDetail.resolve(locale: locale))
            .font(SchneeGlassTypography.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 420)
        }

        Button(GlassLocalizedText.addGlass.resolve(locale: locale), action: onAddGlass)
          .buttonStyle(.borderedProminent)
          .disabled(!canAddGlass)
      }

      if let userMessage {
        messageBanner(userMessage)
          .frame(maxWidth: 440)
      }

      Spacer()
    }
    .padding(SchneeGlassPadding.emptyWorkspace)
  }

  private func messageBanner(_ message: String) -> some View {
    HStack(alignment: .top, spacing: SchneeGlassSpacing.messageContent) {
      Image(systemName: "exclamationmark.triangle")
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)

      Text(message)
        .font(SchneeGlassTypography.body)
        .frame(maxWidth: .infinity, alignment: .leading)

      Button(action: onDismissMessage) {
        Image(systemName: "xmark")
      }
      .buttonStyle(.plain)
      .accessibilityLabel(GlassLocalizedText.dismissMessage.resolve(locale: locale))
    }
    .padding(SchneeGlassPadding.messageBanner)
    .background(
      .regularMaterial,
      in: RoundedRectangle(cornerRadius: SchneeGlassRadius.messageBanner, style: .continuous)
    )
  }
}

private struct GlassPreviewSurface: View {
  @Environment(\.locale) private var locale
  let entry: GlassWorkspaceEntry
  let canRemove: Bool
  let onOpen: (GlassItem) -> Void
  let onReveal: (GlassItem) -> Void
  let onRemove: () -> Void
  let onPlanDrop: @MainActor ([URL]) async -> Bool
  let onCancelDrop: @MainActor () -> Void
  let onCancelCopy: @MainActor () -> Void
  let onPerformDrop: @MainActor ([URL]) async -> Void
  let canReconnectSource: Bool
  let onReconnectSource: @MainActor () -> Void
  let canRefresh: Bool
  let onRefresh: @MainActor () -> Void
  let canRevealConnectedFolder: Bool
  let onRevealConnectedFolder: @MainActor () -> Void
  let canRename: Bool
  let onRename: @MainActor (String) -> Void

  @State private var showsRemoveConfirmation = false
  @State private var showsRenamePrompt = false
  @State private var proposedTitle = ""

  var body: some View {
    VStack(alignment: .leading, spacing: SchneeGlassSpacing.surfaceContent) {
      HStack {
        Text(entry.title)
          .font(SchneeGlassTypography.surfaceTitle)
          .lineLimit(1)

        Spacer()

        statusLabel

        Menu {
          Button(GlassLocalizedText.renameGlassMenu.resolve(locale: locale)) {
            proposedTitle = entry.title
            showsRenamePrompt = true
          }
          .disabled(!canRename)

          Button(GlassLocalizedText.refreshFiles.resolve(locale: locale), action: onRefresh)
            .disabled(!canRefresh)

          if canRevealConnectedFolder {
            Button(
              GlassLocalizedText.showConnectedFolder.resolve(locale: locale),
              action: onRevealConnectedFolder
            )
          }

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

      stateContent
    }
    .padding(SchneeGlassPadding.glassPreview)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      .regularMaterial,
      in: RoundedRectangle(cornerRadius: SchneeGlassRadius.glassSurface, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: SchneeGlassRadius.glassSurface, style: .continuous)
        .stroke(borderStyle, lineWidth: borderWidth)
    }
    .overlay {
      interactionOverlay
        .allowsHitTesting(
          GlassInteractionPolicy.allowsCopyCancellation(
            during: entry.interactionState
          )
        )
    }
    .overlay {
      FileURLDropTarget(
        onPlan: onPlanDrop,
        onExit: onCancelDrop,
        onPerform: onPerformDrop
      )
      .accessibilityHidden(true)
    }
    .accessibilityElement(children: .contain)
    .alert(
      GlassLocalizedText.renameGlassTitle.resolve(locale: locale),
      isPresented: $showsRenamePrompt
    ) {
      TextField(GlassLocalizedText.glassName.resolve(locale: locale), text: $proposedTitle)
      Button(GlassLocalizedText.cancelAction.resolve(locale: locale), role: .cancel) {}
      Button(GlassLocalizedText.renameAction.resolve(locale: locale)) {
        if canRename {
          onRename(proposedTitle)
        }
      }
      .disabled(!canRename)
    } message: {
      Text(GlassLocalizedText.renameGlassDetail.resolve(locale: locale))
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
      let presentation = GlassInteractionPresentation.hovered(surface: .workspace, locale: locale)
      DropOverlaySurface {
        ProgressView()
          .controlSize(.small)
          .accessibilityHidden(true)
        Text(presentation.title)
          .font(SchneeGlassTypography.emphasizedBody)
      }

    case .dropValid(let plan):
      if let presentation = GlassInteractionPresentation.dropValid(
        plan: plan,
        glassTitle: entry.title,
        surface: .workspace,
        locale: locale
      ) {
        DropOverlaySurface {
          if case .symbol(let systemImage) = presentation.indicator {
            Image(systemName: systemImage)
              .font(SchneeGlassTypography.largeSymbol)
          }
          Text(presentation.title)
            .font(SchneeGlassTypography.strongBody)
          if let detail = presentation.detail {
            Text(detail)
              .font(SchneeGlassTypography.supporting)
              .foregroundStyle(.secondary)
          }
        }
      }

    case .dropInvalid(let reason):
      let presentation = GlassInteractionPresentation.dropInvalid(
        reason: reason,
        glassTitle: entry.title,
        surface: .workspace,
        locale: locale
      )
      DropOverlaySurface {
        if case .symbol(let systemImage) = presentation.indicator {
          Image(systemName: systemImage)
            .font(SchneeGlassTypography.largeSymbol)
        }
        Text(presentation.title)
          .font(SchneeGlassTypography.strongBody)
        if let detail = presentation.detail {
          Text(detail)
            .font(SchneeGlassTypography.supporting)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
      }

    case .copying(let progress):
      let presentation = GlassInteractionPresentation.copying(
        progress: progress,
        glassTitle: entry.title,
        surface: .workspace,
        locale: locale
      )
      DropOverlaySurface {
        ProgressView()
          .controlSize(.regular)
          .accessibilityHidden(true)
        Text(presentation.title)
          .font(SchneeGlassTypography.strongBody)
        if let detail = presentation.detail {
          Text(detail)
            .font(SchneeGlassTypography.supporting)
            .foregroundStyle(.secondary)
        }
        Button(
          GlassLocalizedText.cancelCopy.resolve(locale: locale),
          role: .cancel, action: onCancelCopy
        )
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityLabel(GlassLocalizedText.cancelCopy.resolve(locale: locale))
      }
    }
  }

  @ViewBuilder
  private var statusLabel: some View {
    if case .copying = entry.interactionState {
      Label(GlassLocalizedText.copyingStatus.resolve(locale: locale), systemImage: "doc.on.doc")
        .font(SchneeGlassTypography.status)
        .foregroundStyle(.secondary)
    } else if let presentation = GlassContentStatusPresentation.make(
      for: entry.contentState, locale: locale
    ) {
      Label(presentation.label, systemImage: presentation.systemImage)
        .font(SchneeGlassTypography.status)
        .foregroundStyle(.secondary)
    } else {
      // The loading message in the content already supplies the VoiceOver status.
      ProgressView()
        .controlSize(.small)
        .accessibilityHidden(true)
    }
  }

  @ViewBuilder
  private var stateContent: some View {
    switch entry.contentState {
    case .loading:
      HStack(spacing: SchneeGlassSpacing.controlGroup) {
        ProgressView()
          .controlSize(.small)
          .accessibilityHidden(true)
        Text(GlassLocalizedText.loadingFolder.resolve(locale: locale))
          .foregroundStyle(.secondary)
      }
      .frame(minHeight: 84)

    case .ready(let snapshot):
      FilePreviewGrid(
        snapshot: snapshot,
        onOpen: onOpen,
        onReveal: onReveal
      )

    case .empty:
      let presentation = DesktopGlassEmptyPresentation.make(locale: locale)
      SchneeGlassStateMessage(
        systemImage: "tray",
        title: presentation.title,
        detail: presentation.detail
      )
      .frame(maxWidth: .infinity, minHeight: 100)

    case .unavailable(let reason):
      let presentation = GlassUnavailablePresentation.make(for: reason, locale: locale)
      VStack(spacing: SchneeGlassSpacing.controlGroup) {
        SchneeGlassStateMessage(
          systemImage: "externaldrive.badge.exclamationmark",
          title: presentation.title,
          detail: presentation.detail
        )

        Button(
          GlassLocalizedText.reconnectOriginalFolder.resolve(locale: locale),
          action: onReconnectSource
        )
        .buttonStyle(.borderedProminent)
        .disabled(!canReconnectSource)
      }
      .frame(maxWidth: .infinity, minHeight: 100)

    case .failed(let error):
      let canRetryNow = GlassInlineRefreshPolicy.isVisible(
        for: entry.contentState, canRefresh: canRefresh
      )
      let presentation = GlassContentFailurePresentation.make(
        for: error, locale: locale, canRetryNow: canRetryNow
      )
      VStack(spacing: SchneeGlassSpacing.controlGroup) {
        SchneeGlassStateMessage(
          systemImage: "arrow.clockwise.circle",
          title: presentation.title,
          detail: presentation.detail
        )
        if canRetryNow {
          Button(
            GlassLocalizedText.refreshFiles.resolve(locale: locale),
            action: onRefresh
          )
          .buttonStyle(.bordered)
        }
      }
      .frame(maxWidth: .infinity, minHeight: 100)
    }
  }
}

private struct DropOverlaySurface<Content: View>: View {
  @ViewBuilder let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: SchneeGlassRadius.workspaceDropOverlay, style: .continuous)
        .fill(.regularMaterial)

      VStack(spacing: SchneeGlassSpacing.workspaceDropOverlayContent) {
        content
      }
      .padding(SchneeGlassPadding.workspaceOverlayContent)
    }
    .padding(SchneeGlassPadding.workspaceOverlayInset)
  }
}

private struct FilePreviewGrid: View {
  @Environment(\.locale) private var locale
  let snapshot: FolderSnapshot
  let onOpen: (GlassItem) -> Void
  let onReveal: (GlassItem) -> Void

  private let columns = [
    GridItem(
      .adaptive(
        minimum: SchneeGlassMetrics.workspaceFileTileMinimumWidth,
        maximum: SchneeGlassMetrics.fileTileMaximumWidth
      ),
      spacing: SchneeGlassSpacing.fileGridColumn,
      alignment: .top
    )
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: SchneeGlassSpacing.fileGridSection) {
      LazyVGrid(columns: columns, alignment: .leading, spacing: SchneeGlassSpacing.fileGrid) {
        ForEach(snapshot.items) { item in
          GlassInteractiveFileTile(item: item, onOpen: onOpen, onReveal: onReveal)
        }
      }

      if snapshot.isTruncated {
        Label(
          GlassLocalizedText.workspaceFirst500Items.resolve(locale: locale),
          systemImage: "ellipsis.circle"
        )
        .font(SchneeGlassTypography.supporting)
        .foregroundStyle(.secondary)
      }
    }
  }
}

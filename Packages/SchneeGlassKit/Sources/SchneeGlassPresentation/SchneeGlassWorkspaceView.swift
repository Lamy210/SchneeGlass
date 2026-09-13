import FileDomain
import SchneeGlassApplication
import SchneeGlassDesignSystem
import SchneeGlassDomain
import SwiftUI

public struct SchneeGlassWorkspaceView: View {
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
            userMessage: model.userMessage,
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
            }
        )
    }
}

struct WorkspaceSurface: View {
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

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 520, minHeight: 420)
        .background(.background)
    }

    private var header: some View {
        HStack(spacing: SchneeGlassSpacing.surfaceContent) {
            Image(systemName: "snowflake")
                .font(.title2.weight(.medium))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("SchneeGlass")
                    .font(SchneeGlassTypography.surfaceTitle)
                Text("Your folders, right where you need them.")
                    .font(SchneeGlassTypography.supporting)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isRestoring {
                HStack(spacing: 7) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Restoring…")
                        .font(SchneeGlassTypography.supporting)
                        .foregroundStyle(.secondary)
                }
            }

            Button(action: onAddGlass) {
                if isCreatingGlass {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Add Glass", systemImage: "plus")
                }
            }
            .disabled(!canAddGlass)
            .keyboardShortcut("n", modifiers: .command)
            .accessibilityLabel("Add Glass")
        }
        .padding(SchneeGlassPadding.workspaceContent)
    }

    @ViewBuilder
    private var content: some View {
        if glasses.isEmpty {
            emptyWorkspace
        } else {
            ScrollView {
                LazyVStack(spacing: SchneeGlassSpacing.workspaceSection) {
                    if let userMessage {
                        messageBanner(userMessage)
                    }

                    ForEach(glasses) { entry in
                        GlassPreviewSurface(
                            entry: entry,
                            canRemove: !isMutatingConfiguration
                                && !requiresConfigurationRecovery
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
                            }
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
                Text("Restoring your Glasses…")
                    .font(SchneeGlassTypography.body)
                    .foregroundStyle(.secondary)
            } else if requiresConfigurationRecovery {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                VStack(spacing: SchneeGlassSpacing.compactContent) {
                    Text("Configuration recovery required")
                        .font(SchneeGlassTypography.emptyStateTitle)
                    Text("SchneeGlass couldn't read its saved configuration. Open Settings and restore a valid Configuration Backup before adding or changing a Glass.")
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
                    Text("Put a folder on your desktop")
                        .font(SchneeGlassTypography.emptyStateTitle)
                    Text("Choose a folder to create your first Glass. SchneeGlass stores a reference to the folder; it does not take ownership of your files.")
                        .font(SchneeGlassTypography.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }

                Button("Add Glass", action: onAddGlass)
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
            .accessibilityLabel("Dismiss")
        }
        .padding(SchneeGlassPadding.messageBanner)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: SchneeGlassRadius.messageBanner, style: .continuous)
        )
    }
}

private struct GlassPreviewSurface: View {
    let entry: GlassWorkspaceEntry
    let canRemove: Bool
    let onOpen: (GlassItem) -> Void
    let onReveal: (GlassItem) -> Void
    let onRemove: () -> Void
    let onPlanDrop: @MainActor ([URL]) async -> Bool
    let onCancelDrop: @MainActor () -> Void
    let onCancelCopy: @MainActor () -> Void
    let onPerformDrop: @MainActor ([URL]) async -> Void

    @State private var showsRemoveConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: SchneeGlassSpacing.surfaceContent) {
            HStack {
                Text(entry.title)
                    .font(SchneeGlassTypography.surfaceTitle)
                    .lineLimit(1)

                Spacer()

                statusLabel

                Menu {
                    Button("Remove Glass…", role: .destructive) {
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
                .accessibilityLabel("Glass options")
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
        .alert("Remove Glass?", isPresented: $showsRemoveConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Remove Glass", role: .destructive, action: onRemove)
        } message: {
            Text("This removes the Glass only. The connected folder and its files will not be deleted or moved.")
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
            let presentation = GlassInteractionPresentation.hovered(surface: .workspace)
            DropOverlaySurface {
                ProgressView()
                    .controlSize(.small)
                Text(presentation.title)
                    .font(SchneeGlassTypography.emphasizedBody)
            }

        case let .dropValid(plan):
            if let presentation = GlassInteractionPresentation.dropValid(
                plan: plan,
                glassTitle: entry.title,
                surface: .workspace
            ) {
                DropOverlaySurface {
                    if case let .symbol(systemImage) = presentation.indicator {
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

        case let .dropInvalid(reason):
            let presentation = GlassInteractionPresentation.dropInvalid(
                reason: reason,
                glassTitle: entry.title,
                surface: .workspace
            )
            DropOverlaySurface {
                if case let .symbol(systemImage) = presentation.indicator {
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

        case let .copying(progress):
            let presentation = GlassInteractionPresentation.copying(
                progress: progress,
                glassTitle: entry.title,
                surface: .workspace
            )
            DropOverlaySurface {
                ProgressView()
                    .controlSize(.regular)
                Text(presentation.title)
                    .font(SchneeGlassTypography.strongBody)
                if let detail = presentation.detail {
                    Text(detail)
                        .font(SchneeGlassTypography.supporting)
                        .foregroundStyle(.secondary)
                }
                Button("Cancel Copy", role: .cancel, action: onCancelCopy)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Cancel Copy")
            }
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        if case .copying = entry.interactionState {
            Label("Copying", systemImage: "doc.on.doc")
                .font(SchneeGlassTypography.status)
                .foregroundStyle(.secondary)
        } else if let presentation = GlassContentStatusPresentation.make(for: entry.contentState) {
            Label(presentation.label, systemImage: presentation.systemImage)
                .font(SchneeGlassTypography.status)
                .foregroundStyle(.secondary)
        } else {
            ProgressView()
                .controlSize(.small)
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        switch entry.contentState {
        case .loading:
            HStack(spacing: SchneeGlassSpacing.controlGroup) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading folder…")
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 84)

        case let .ready(snapshot):
            FilePreviewGrid(
                snapshot: snapshot,
                onOpen: onOpen,
                onReveal: onReveal
            )

        case .empty:
            SchneeGlassStateMessage(
                systemImage: "tray",
                title: "Drop files here",
                detail: "Files are copied. Originals stay where they are."
            )
            .frame(maxWidth: .infinity, minHeight: 100)

        case .unavailable:
            let presentation = GlassUnavailablePresentation.current
            SchneeGlassStateMessage(
                systemImage: "externaldrive.badge.exclamationmark",
                title: presentation.title,
                detail: presentation.detail
            )
            .frame(maxWidth: .infinity, minHeight: 100)

        case let .failed(error):
            let presentation = GlassContentFailurePresentation.make(for: error)
            SchneeGlassStateMessage(
                systemImage: "arrow.clockwise.circle",
                title: presentation.title,
                detail: presentation.detail
            )
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
                    let presentation = GlassItemPresentation.make(for: item)
                    SchneeGlassFileTile(
                        systemImage: presentation.systemImage,
                        title: item.displayName
                    )
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        onOpen(item)
                    }
                    .contextMenu {
                        Button("Open") {
                            onOpen(item)
                        }
                        Button("Reveal in Finder") {
                            onReveal(item)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(presentation.accessibilityLabel)
                    .accessibilityHint("Double-click to open")
                }
            }

            if snapshot.isTruncated {
                Label("Showing the first 500 items", systemImage: "ellipsis.circle")
                    .font(SchneeGlassTypography.supporting)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

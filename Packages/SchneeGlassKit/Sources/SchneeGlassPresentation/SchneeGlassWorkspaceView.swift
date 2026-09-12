import FileDomain
import SchneeGlassApplication
import SchneeGlassDesignSystem
import SwiftUI

public struct SchneeGlassWorkspaceView: View {
    @Bindable private var model: SchneeGlassWorkspaceModel

    public init(model: SchneeGlassWorkspaceModel) {
        self._model = Bindable(wrappedValue: model)
    }

    public var body: some View {
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

            if model.isRestoring {
                HStack(spacing: 7) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Restoring…")
                        .font(SchneeGlassTypography.supporting)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                Task {
                    await model.addGlass()
                }
            } label: {
                if model.isCreatingGlass {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Add Glass", systemImage: "plus")
                }
            }
            .disabled(model.isMutatingConfiguration)
            .keyboardShortcut("n", modifiers: .command)
            .accessibilityLabel("Add Glass")
        }
        .padding(SchneeGlassPadding.workspaceContent)
    }

    @ViewBuilder
    private var content: some View {
        if model.glasses.isEmpty {
            emptyWorkspace
        } else {
            ScrollView {
                LazyVStack(spacing: SchneeGlassSpacing.workspaceSection) {
                    if let message = model.userMessage {
                        messageBanner(message)
                    }

                    ForEach(model.glasses) { entry in
                        GlassPreviewSurface(
                            entry: entry,
                            canRemove: !model.isMutatingConfiguration
                                && GlassInteractionPolicy.allowsRemoval(during: entry.interactionState),
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
                            onPerformDrop: { urls in
                                _ = await model.performDrop(
                                    glassID: entry.id,
                                    sourceURLs: urls
                                )
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

            if model.isRestoring {
                ProgressView()
                    .controlSize(.regular)
                Text("Restoring your Glasses…")
                    .font(SchneeGlassTypography.body)
                    .foregroundStyle(.secondary)
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

                Button("Add Glass") {
                    Task {
                        await model.addGlass()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isMutatingConfiguration)
            }

            if let message = model.userMessage {
                messageBanner(message)
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

            Button {
                model.dismissMessage()
            } label: {
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
                .allowsHitTesting(false)
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
            VStack(spacing: SchneeGlassSpacing.controlGroup) {
                Image(systemName: "tray")
                    .font(SchneeGlassTypography.largeSymbol)
                    .foregroundStyle(.secondary)
                Text("Drop files here")
                    .font(SchneeGlassTypography.emphasizedBody)
                Text("Files are copied. Originals stay where they are.")
                    .font(SchneeGlassTypography.supporting)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 100)

        case .unavailable:
            VStack(spacing: SchneeGlassSpacing.controlGroup) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(SchneeGlassTypography.largeSymbol)
                    .foregroundStyle(.secondary)
                Text("Folder unavailable")
                    .font(SchneeGlassTypography.emphasizedBody)
                Text("Reconnect support will be exposed through Recovery.")
                    .font(SchneeGlassTypography.supporting)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 100)

        case let .failed(error):
            let presentation = GlassContentFailurePresentation.make(for: error)
            VStack(spacing: SchneeGlassSpacing.controlGroup) {
                Image(systemName: "arrow.clockwise.circle")
                    .font(SchneeGlassTypography.largeSymbol)
                    .foregroundStyle(.secondary)
                Text(presentation.title)
                    .font(SchneeGlassTypography.emphasizedBody)
                Text(presentation.detail)
                    .font(SchneeGlassTypography.supporting)
                    .foregroundStyle(.secondary)
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
        VStack(alignment: .leading, spacing: SchneeGlassSpacing.messageContent) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: SchneeGlassSpacing.fileGrid) {
                ForEach(snapshot.items) { item in
                    VStack(spacing: SchneeGlassSpacing.compactContent) {
                        Image(systemName: symbolName(for: item.kind))
                            .font(.system(size: SchneeGlassMetrics.fileIconSize))
                            .foregroundStyle(.primary)
                            .frame(height: SchneeGlassMetrics.fileIconHeight)

                        Text(item.displayName)
                            .font(SchneeGlassTypography.supporting)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
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
                    .accessibilityLabel(accessibilityLabel(for: item))
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

    private func symbolName(for kind: FileKind) -> String {
        switch kind {
        case .regular:
            return "doc"
        case .directory:
            return "folder"
        case .package:
            return "shippingbox"
        case .alias:
            return "arrowshape.turn.up.right"
        case .symbolicLink:
            return "link"
        case .unsupported:
            return "questionmark.square"
        }
    }

    private func accessibilityLabel(for item: GlassItem) -> String {
        switch item.kind {
        case .directory:
            return "Folder, \(item.displayName)"
        case .package:
            return "Package, \(item.displayName)"
        case .alias:
            return "Alias, \(item.displayName)"
        case .symbolicLink:
            return "Symbolic link, \(item.displayName)"
        case .regular, .unsupported:
            return item.displayName
        }
    }
}

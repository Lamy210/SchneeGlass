import FileDomain
import SchneeGlassApplication
import SchneeGlassDesignSystem
import SchneeGlassDomain
import SwiftUI

public struct SchneeGlassDesktopGlassView: View {
    @Bindable private var model: SchneeGlassWorkspaceModel
    private let glassID: GlassID

    public init(model: SchneeGlassWorkspaceModel, glassID: GlassID) {
        self._model = Bindable(wrappedValue: model)
        self.glassID = glassID
    }

    public var body: some View {
        Group {
            if let entry = model.glasses.first(where: { $0.id == glassID }) {
                DesktopGlassSurface(
                    entry: entry,
                    canRemove: model.canMutateConfiguration
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
            } else {
                Color.clear
            }
        }
    }
}

struct DesktopGlassSurface: View {
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
                .allowsHitTesting(false)
        }
        .alert("Remove Glass?", isPresented: $showsRemoveConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Remove Glass", role: .destructive, action: onRemove)
        } message: {
            Text("This removes the Glass only. The connected folder and its files will not be deleted or moved.")
        }
        .accessibilityElement(children: .contain)
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
    }

    @ViewBuilder
    private var statusLabel: some View {
        if let presentation = GlassContentStatusPresentation.make(for: entry.contentState) {
            Image(systemName: presentation.systemImage)
                .foregroundStyle(.secondary)
                .accessibilityLabel(presentation.label)
        } else {
            ProgressView()
                .controlSize(.small)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch entry.contentState {
        case .loading:
            HStack(spacing: SchneeGlassSpacing.controlGroup) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading folder…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case let .ready(snapshot):
            ScrollView {
                DesktopFileGrid(
                    snapshot: snapshot,
                    onOpen: onOpen,
                    onReveal: onReveal
                )
            }

        case .empty:
            VStack(spacing: SchneeGlassSpacing.controlGroup) {
                Spacer()
                SchneeGlassStateMessage(
                    systemImage: "tray.and.arrow.down",
                    title: "Drop files here",
                    detail: "Files are copied. Originals stay where they are.",
                    detailAlignment: .center
                )
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .unavailable:
            VStack(spacing: SchneeGlassSpacing.controlGroup) {
                Spacer()
                SchneeGlassStateMessage(
                    systemImage: "externaldrive.badge.exclamationmark",
                    title: "Folder unavailable",
                    detail: "The Glass stays here so it can be reconnected without losing its layout.",
                    detailAlignment: .center
                )
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case let .failed(error):
            let presentation = GlassContentFailurePresentation.make(for: error)
            VStack(spacing: SchneeGlassSpacing.controlGroup) {
                Spacer()
                SchneeGlassStateMessage(
                    systemImage: "arrow.clockwise.circle",
                    title: presentation.title,
                    detail: presentation.detail,
                    detailAlignment: .center
                )
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            let presentation = GlassInteractionPresentation.hovered(surface: .desktop)
            overlayCard(
                icon: symbolName(from: presentation) ?? "ellipsis",
                title: presentation.title,
                detail: presentation.detail
            )

        case let .dropValid(plan):
            if let presentation = GlassInteractionPresentation.dropValid(
                plan: plan,
                glassTitle: entry.title,
                surface: .desktop
            ) {
                overlayCard(
                    icon: symbolName(from: presentation) ?? "doc.on.doc",
                    title: presentation.title,
                    detail: presentation.detail
                )
            }

        case let .dropInvalid(reason):
            let presentation = GlassInteractionPresentation.dropInvalid(
                reason: reason,
                glassTitle: entry.title,
                surface: .desktop
            )
            overlayCard(
                icon: symbolName(from: presentation) ?? "nosign",
                title: presentation.title,
                detail: presentation.detail
            )

        case let .copying(progress):
            let presentation = GlassInteractionPresentation.copying(
                progress: progress,
                glassTitle: entry.title,
                surface: .desktop
            )
            overlayCard(
                icon: "doc.on.doc",
                title: presentation.title,
                detail: presentation.detail,
                showsProgress: true
            )
        }
    }

    private func symbolName(from presentation: GlassInteractionPresentation) -> String? {
        guard case let .symbol(systemImage) = presentation.indicator else {
            return nil
        }
        return systemImage
    }

    private func overlayCard(
        icon: String,
        title: String,
        detail: String?,
        showsProgress: Bool = false
    ) -> some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.12))

            VStack(spacing: SchneeGlassSpacing.controlGroup) {
                if showsProgress {
                    ProgressView()
                        .controlSize(.small)
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

private struct DesktopFileGrid: View {
    let snapshot: FolderSnapshot
    let onOpen: (GlassItem) -> Void
    let onReveal: (GlassItem) -> Void

    private let columns = [
        GridItem(
            .adaptive(
                minimum: SchneeGlassMetrics.desktopFileTileMinimumWidth,
                maximum: SchneeGlassMetrics.fileTileMaximumWidth
            ),
            spacing: SchneeGlassSpacing.fileGridColumn,
            alignment: .top
        )
    ]

    var body: some View {
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

            if snapshot.isTruncated {
                Label("Showing the first 500 items", systemImage: "ellipsis.circle")
                    .font(SchneeGlassTypography.supporting)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

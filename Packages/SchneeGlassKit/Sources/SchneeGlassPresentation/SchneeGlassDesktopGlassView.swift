import FileDomain
import SchneeGlassApplication
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
            } else {
                Color.clear
            }
        }
    }
}

private struct DesktopGlassSurface: View {
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
        VStack(alignment: .leading, spacing: 12) {
            header
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial)
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(borderStyle, lineWidth: borderWidth)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
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
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(entry.title)
                .font(.headline)
                .lineLimit(1)

            Spacer(minLength: 8)
            statusLabel

            Menu {
                Button("Remove Glass…", role: .destructive) {
                    showsRemoveConfirmation = true
                }
                .disabled(!canRemove)
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("Glass options")
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch entry.contentState {
        case .loading:
            ProgressView()
                .controlSize(.small)
        case .ready:
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.secondary)
                .accessibilityLabel("Connected")
        case .empty:
            Image(systemName: "tray")
                .foregroundStyle(.secondary)
                .accessibilityLabel("Empty")
        case .unavailable:
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(.secondary)
                .accessibilityLabel("Unavailable")
        case let .failed(error):
            Image(systemName: "arrow.clockwise.circle")
                .foregroundStyle(.secondary)
                .accessibilityLabel(GlassContentFailurePresentation.make(for: error).status)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch entry.contentState {
        case .loading:
            HStack(spacing: 8) {
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
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "tray.and.arrow.down")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Drop files here")
                    .font(.callout.weight(.medium))
                Text("Files are copied. Originals stay where they are.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .unavailable:
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Folder unavailable")
                    .font(.callout.weight(.medium))
                Text("The Glass stays here so it can be reconnected without losing its layout.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case let .failed(error):
            let presentation = GlassContentFailurePresentation.make(for: error)
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "arrow.clockwise.circle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text(presentation.title)
                    .font(.callout.weight(.medium))
                Text(presentation.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
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
            overlayCard(icon: "ellipsis", title: "Checking files…", detail: nil)

        case let .dropValid(plan):
            switch plan {
            case let .copy(batch):
                let count = batch.items.count
                overlayCard(
                    icon: "doc.on.doc",
                    title: count == 1
                        ? "Copy \(batch.items[0].destinationFilename) to \(entry.title)"
                        : "Copy \(count) files to \(entry.title)",
                    detail: "Original files stay where they are."
                )
            case .noOperation, .reject:
                EmptyView()
            }

        case let .dropInvalid(reason):
            overlayCard(
                icon: "nosign",
                title: rejectionTitle(reason),
                detail: rejectionDetail(reason)
            )

        case let .copying(progress):
            overlayCard(
                icon: "doc.on.doc",
                title: progress.totalCount == 1
                    ? "Copying \(progress.currentFilename)…"
                    : "Copying \(progress.currentIndex) of \(progress.totalCount)…",
                detail: "Original files stay where they are.",
                showsProgress: true
            )
        }
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

            VStack(spacing: 8) {
                if showsProgress {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: icon)
                        .font(.title2)
                }

                Text(title)
                    .font(.callout.weight(.semibold))
                    .multilineTextAlignment(.center)

                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(16)
            .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(18)
        }
    }

    private func rejectionTitle(_ reason: DropRejection) -> String {
        switch reason {
        case .unsupportedFolder:
            return "Folders aren't supported yet"
        case .unsupportedPackage:
            return "Packages aren't supported yet"
        case .unsupportedSymbolicLink:
            return "Symbolic links aren't supported"
        case .unsupportedItem:
            return "This item can't be copied by SchneeGlass"
        case .tooManyItems:
            return "Too many files to copy at once"
        case .collision:
            return "A file with this name already exists"
        case .containsSameDirectoryItem:
            return "Already in \(entry.title)"
        case .destinationUnavailable:
            return "Folder unavailable"
        case .destinationReadOnly:
            return "Folder is read-only"
        case .destinationCopySafetyUnsupported:
            return "Copy isn't supported for this folder"
        case .networkDestinationUnsupported:
            return "Network destinations aren't supported yet"
        case .sourceUnavailable:
            return "A source file is unavailable"
        case .cloudPlaceholderUnavailable:
            return "Download the cloud file first"
        }
    }

    private func rejectionDetail(_ reason: DropRejection) -> String? {
        switch reason {
        case let .tooManyItems(maximum):
            return "SchneeGlass copies up to \(maximum) files per drop. Split this selection into smaller drops."
        case .collision:
            return "Nothing will be overwritten."
        case .cloudPlaceholderUnavailable:
            return "SchneeGlass won't start an unexpected cloud download."
        case .unsupportedFolder:
            return "v0.1 copies regular files only."
        case .destinationCopySafetyUnsupported:
            return "This filesystem doesn't provide the no-overwrite guarantees SchneeGlass requires."
        default:
            return nil
        }
    }
}

private struct DesktopFileGrid: View {
    let snapshot: FolderSnapshot
    let onOpen: (GlassItem) -> Void
    let onReveal: (GlassItem) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 74, maximum: 92), spacing: 10, alignment: .top)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            ForEach(snapshot.items) { item in
                VStack(spacing: 6) {
                    Image(systemName: symbolName(for: item.kind))
                        .font(.system(size: 28))
                        .foregroundStyle(.primary)
                        .frame(height: 32)

                    Text(item.displayName)
                        .font(.caption)
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

            if snapshot.isTruncated {
                Label("Showing the first 500 items", systemImage: "ellipsis.circle")
                    .font(.caption)
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

import FileDomain
import SchneeGlassApplication
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
        HStack(spacing: 12) {
            Image(systemName: "snowflake")
                .font(.title2.weight(.medium))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("SchneeGlass")
                    .font(.headline)
                Text("Your folders, right where you need them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if model.isRestoring {
                HStack(spacing: 7) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Restoring…")
                        .font(.caption)
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
        .padding(16)
    }

    @ViewBuilder
    private var content: some View {
        if model.glasses.isEmpty {
            emptyWorkspace
        } else {
            ScrollView {
                LazyVStack(spacing: 16) {
                    if let message = model.userMessage {
                        messageBanner(message)
                    }

                    ForEach(model.glasses) { entry in
                        GlassPreviewSurface(
                            entry: entry,
                            canRemove: !model.isMutatingConfiguration,
                            onOpen: model.open,
                            onReveal: model.revealInFinder,
                            onRemove: {
                                Task {
                                    await model.removeGlass(id: entry.id)
                                }
                            }
                        )
                    }
                }
                .padding(16)
            }
        }
    }

    private var emptyWorkspace: some View {
        VStack(spacing: 16) {
            Spacer()

            if model.isRestoring {
                ProgressView()
                    .controlSize(.regular)
                Text("Restoring your Glasses…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "rectangle.stack.badge.plus")
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                VStack(spacing: 6) {
                    Text("Put a folder on your desktop")
                        .font(.title3.weight(.semibold))
                    Text("Choose a folder to create your first Glass. SchneeGlass stores a reference to the folder; it does not take ownership of your files.")
                        .font(.callout)
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
        .padding(24)
    }

    private func messageBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(message)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                model.dismissMessage()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct GlassPreviewSurface: View {
    let entry: GlassWorkspaceEntry
    let canRemove: Bool
    let onOpen: (GlassItem) -> Void
    let onReveal: (GlassItem) -> Void
    let onRemove: () -> Void

    @State private var showsRemoveConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(entry.title)
                    .font(.headline)
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
                        .frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("Glass options")
            }

            stateContent
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.separator.opacity(0.45), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .alert("Remove Glass?", isPresented: $showsRemoveConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Remove Glass", role: .destructive, action: onRemove)
        } message: {
            Text("This removes the Glass only. The connected folder and its files will not be deleted or moved.")
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch entry.contentState {
        case .loading:
            ProgressView()
                .controlSize(.small)
        case .ready:
            Label("Connected", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .empty:
            Label("Empty", systemImage: "tray")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .unavailable:
            Label("Unavailable", systemImage: "exclamationmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed:
            Label("Refresh failed", systemImage: "arrow.clockwise.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        switch entry.contentState {
        case .loading:
            HStack(spacing: 8) {
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
            VStack(spacing: 8) {
                Image(systemName: "tray")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Drop files here")
                    .font(.callout.weight(.medium))
                Text("Copy drop support will be connected to this surface next.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 100)

        case .unavailable:
            VStack(spacing: 8) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Folder unavailable")
                    .font(.callout.weight(.medium))
                Text("Reconnect support will be exposed through Recovery.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 100)

        case .failed:
            VStack(spacing: 8) {
                Image(systemName: "arrow.clockwise.circle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Couldn't refresh this folder")
                    .font(.callout.weight(.medium))
                Text("SchneeGlass will try again when the folder changes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 100)
        }
    }
}

private struct FilePreviewGrid: View {
    let snapshot: FolderSnapshot
    let onOpen: (GlassItem) -> Void
    let onReveal: (GlassItem) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 76, maximum: 92), spacing: 10, alignment: .top)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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

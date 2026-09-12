import Foundation
import Testing
@testable import SchneeGlassPresentation

@Test
func contentStatusPresentationCoversEveryContentState() {
    let snapshot = makePresentationSnapshot()

    #expect(GlassContentStatusPresentation.make(for: .loading) == nil)
    #expect(
        GlassContentStatusPresentation.make(for: .ready(snapshot))
            == .init(label: "Connected", systemImage: "checkmark.circle")
    )
    #expect(
        GlassContentStatusPresentation.make(for: .empty(snapshot))
            == .init(label: "Empty", systemImage: "tray")
    )
    #expect(
        GlassContentStatusPresentation.make(for: .unavailable(.volumeUnavailable))
            == .init(label: "Unavailable", systemImage: "exclamationmark.circle")
    )
    #expect(
        GlassContentStatusPresentation.make(for: .failed(.enumerationFailed))
            == .init(label: "Refresh failed", systemImage: "arrow.clockwise.circle")
    )
    #expect(
        GlassContentStatusPresentation.make(for: .failed(.unexpected))
            == .init(label: "Needs reconnect", systemImage: "arrow.clockwise.circle")
    )
}

@Test
func dropRejectionPresentationPreservesWorkspaceAndDesktopCopy() {
    assertRejection(
        .unsupportedFolder,
        workspaceTitle: "Folders aren't supported yet",
        workspaceDetail: "v0.1 accepts regular files only.",
        desktopTitle: "Folders aren't supported yet",
        desktopDetail: "v0.1 copies regular files only."
    )
    assertRejection(
        .unsupportedPackage,
        workspaceTitle: "Packages aren't supported yet",
        workspaceDetail: "The dropped item was not changed.",
        desktopTitle: "Packages aren't supported yet",
        desktopDetail: nil
    )
    assertRejection(
        .unsupportedSymbolicLink,
        workspaceTitle: "Symbolic links aren't supported",
        workspaceDetail: "The dropped item was not changed.",
        desktopTitle: "Symbolic links aren't supported",
        desktopDetail: nil
    )
    assertRejection(
        .unsupportedItem,
        workspaceTitle: "This item can't be copied",
        workspaceDetail: "The dropped item was not changed.",
        desktopTitle: "This item can't be copied by SchneeGlass",
        desktopDetail: nil
    )
    assertRejection(
        .tooManyItems(maximum: 20),
        workspaceTitle: "Too many files to copy at once",
        workspaceDetail: "SchneeGlass copies up to 20 files per drop. Split this selection into smaller drops.",
        desktopTitle: "Too many files to copy at once",
        desktopDetail: "SchneeGlass copies up to 20 files per drop. Split this selection into smaller drops."
    )
    assertRejection(
        .collision,
        workspaceTitle: "A file with this name already exists",
        workspaceDetail: "Nothing will be overwritten.",
        desktopTitle: "A file with this name already exists",
        desktopDetail: "Nothing will be overwritten."
    )
    assertRejection(
        .containsSameDirectoryItem,
        workspaceTitle: "Already in Projects",
        workspaceDetail: "No copy is needed.",
        desktopTitle: "Already in Projects",
        desktopDetail: nil
    )
    assertRejection(
        .destinationUnavailable,
        workspaceTitle: "Folder unavailable",
        workspaceDetail: "Reconnect the Glass before copying files.",
        desktopTitle: "Folder unavailable",
        desktopDetail: nil
    )
    assertRejection(
        .destinationReadOnly,
        workspaceTitle: "Folder is read-only",
        workspaceDetail: "SchneeGlass can't write to this folder.",
        desktopTitle: "Folder is read-only",
        desktopDetail: nil
    )
    assertRejection(
        .destinationCopySafetyUnsupported,
        workspaceTitle: "Copy isn't supported for this folder",
        workspaceDetail: "This filesystem doesn't provide the no-overwrite guarantees SchneeGlass requires.",
        desktopTitle: "Copy isn't supported for this folder",
        desktopDetail: "This filesystem doesn't provide the no-overwrite guarantees SchneeGlass requires."
    )
    assertRejection(
        .networkDestinationUnsupported,
        workspaceTitle: "Network folders aren't supported for copy yet",
        workspaceDetail: "Open the folder in Finder instead.",
        desktopTitle: "Network destinations aren't supported yet",
        desktopDetail: nil
    )
    assertRejection(
        .sourceUnavailable,
        workspaceTitle: "A source file is unavailable",
        workspaceDetail: "The source may have moved or become inaccessible.",
        desktopTitle: "A source file is unavailable",
        desktopDetail: nil
    )
    assertRejection(
        .sourceCapacityReached(maximum: 64),
        workspaceTitle: "Copy capacity is busy",
        workspaceDetail: "SchneeGlass keeps up to 64 source files ready across active drops. Finish another copy and try again.",
        desktopTitle: "Copy capacity is busy",
        desktopDetail: "SchneeGlass keeps up to 64 source files ready across active drops. Finish another copy and try again."
    )
    assertRejection(
        .cloudPlaceholderUnavailable,
        workspaceTitle: "Download the cloud file first",
        workspaceDetail: "SchneeGlass won't start an unexpected cloud download.",
        desktopTitle: "Download the cloud file first",
        desktopDetail: "SchneeGlass won't start an unexpected cloud download."
    )
}

@Test
func copyProgressPresentationKeepsSurfaceSpecificInformationHierarchy() {
    let single = GlassInteractionPresentation.copying(
        progress: .init(currentIndex: 1, totalCount: 1, currentFilename: "Design.pdf"),
        glassTitle: "Projects",
        surface: .workspace
    )
    #expect(single.indicator == .progress)
    #expect(single.title == "Copying to Projects…")
    #expect(single.detail == "Design.pdf")

    let multiple = GlassInteractionPresentation.copying(
        progress: .init(currentIndex: 2, totalCount: 4, currentFilename: "Notes.txt"),
        glassTitle: "Projects",
        surface: .desktop
    )
    #expect(multiple.indicator == .progress)
    #expect(multiple.title == "Copying 2 of 4…")
    #expect(multiple.detail == "Original files stay where they are.")
}

@Test
func nonCopyDropPlanRemainsHiddenOnDesktopButKeepsWorkspaceFallback() {
    let workspace = GlassInteractionPresentation.dropValid(
        plan: .noOperation,
        glassTitle: "Projects",
        surface: .workspace
    )
    #expect(workspace?.indicator == .symbol("plus.circle.fill"))
    #expect(workspace?.title == "Copy to Projects")
    #expect(workspace?.detail == "Original files stay where they are.")

    #expect(
        GlassInteractionPresentation.dropValid(
            plan: .noOperation,
            glassTitle: "Projects",
            surface: .desktop
        ) == nil
    )
}

private func assertRejection(
    _ reason: DropRejection,
    workspaceTitle: String,
    workspaceDetail: String?,
    desktopTitle: String,
    desktopDetail: String?
) {
    let workspace = GlassInteractionPresentation.dropInvalid(
        reason: reason,
        glassTitle: "Projects",
        surface: .workspace
    )
    #expect(workspace.indicator == .symbol("nosign"))
    #expect(workspace.title == workspaceTitle)
    #expect(workspace.detail == workspaceDetail)

    let desktop = GlassInteractionPresentation.dropInvalid(
        reason: reason,
        glassTitle: "Projects",
        surface: .desktop
    )
    #expect(desktop.indicator == .symbol("nosign"))
    #expect(desktop.title == desktopTitle)
    #expect(desktop.detail == desktopDetail)
}

private func makePresentationSnapshot() -> FolderSnapshot {
    FolderSnapshot(
        folderIdentity: .init(
            resourceIdentifier: "presentation-test-folder",
            standardizedURL: URL(fileURLWithPath: "/tmp/SchneeGlassPresentationTests", isDirectory: true)
        ),
        items: [],
        isTruncated: false,
        observedAt: Date(timeIntervalSince1970: 1_700_000_000),
        generation: 1
    )
}

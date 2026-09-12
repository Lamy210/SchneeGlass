import FileDomain
import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import SwiftUI
import Testing
@testable import SchneeGlassPresentation

@MainActor
@Suite(.serialized)
struct WorkspaceVisualSnapshotTests {
    private let snapshotSize = CGSize(width: 720, height: 620)

    @Test
    func emptyLight() {
        guard VisualSnapshotHarness.isEnabled else {
            return
        }

        assertWorkspaceSnapshot(
            glasses: [],
            userMessage: nil,
            colorScheme: .light
        )
    }

    @Test
    func emptyWithMessageLight() {
        guard VisualSnapshotHarness.isEnabled else {
            return
        }

        assertWorkspaceSnapshot(
            glasses: [],
            userMessage: "SchneeGlass couldn't read its saved configuration. Use Recovery before making changes.",
            colorScheme: .light
        )
    }

    @Test
    func populatedLight() {
        guard VisualSnapshotHarness.isEnabled else {
            return
        }

        assertWorkspaceSnapshot(
            glasses: makePopulatedEntries(),
            userMessage: nil,
            colorScheme: .light
        )
    }

    @Test
    func populatedWithMessageLight() {
        guard VisualSnapshotHarness.isEnabled else {
            return
        }

        assertWorkspaceSnapshot(
            glasses: [makeReadyEntry(title: "Projects")],
            userMessage: "SchneeGlass couldn't save the new Glass position. Files and folders were not changed.",
            colorScheme: .light
        )
    }

    @Test
    func populatedDark() {
        guard VisualSnapshotHarness.isEnabled else {
            return
        }

        assertWorkspaceSnapshot(
            glasses: makePopulatedEntries(),
            userMessage: nil,
            colorScheme: .dark
        )
    }

    private var fixtureURL: URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("SchneeGlassWorkspaceVisualFixtures", isDirectory: true)
    }

    private func assertWorkspaceSnapshot(
        glasses: [GlassWorkspaceEntry],
        userMessage: String?,
        colorScheme: ColorScheme,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        VisualSnapshotHarness.assertView(
            size: snapshotSize,
            colorScheme: colorScheme,
            padding: 0,
            marker: "SCHNEEGLASS_WORKSPACE_SNAPSHOT_RESULT",
            fileID: fileID,
            filePath: filePath,
            testName: testName,
            line: line,
            column: column
        ) {
            WorkspaceSurface(
                glasses: glasses,
                isCreatingGlass: false,
                isRestoring: false,
                isMutatingConfiguration: false,
                userMessage: userMessage,
                onAddGlass: {},
                onDismissMessage: {},
                onOpen: { _ in },
                onReveal: { _ in },
                onRemove: { _ in },
                onPlanDrop: { _, _ in false },
                onCancelDrop: { _ in },
                onPerformDrop: { _, _ in }
            )
        }
    }

    private func makePopulatedEntries() -> [GlassWorkspaceEntry] {
        [
            makeReadyEntry(title: "Projects"),
            GlassWorkspaceEntry(
                id: GlassID(),
                title: "Archive",
                contentState: .unavailable(.volumeUnavailable)
            )
        ]
    }

    private func makeReadyEntry(title: String) -> GlassWorkspaceEntry {
        GlassWorkspaceEntry(
            id: GlassID(),
            title: title,
            contentState: .ready(makeSnapshot(items: makeItems()))
        )
    }

    private func makeSnapshot(items: [GlassItem]) -> FolderSnapshot {
        FolderSnapshot(
            folderIdentity: FolderIdentity(
                resourceIdentifier: "workspace-visual-fixture-folder",
                standardizedURL: fixtureURL
            ),
            items: items,
            isTruncated: false,
            observedAt: Date(timeIntervalSince1970: 1_700_000_000),
            generation: 1
        )
    }

    private func makeItems() -> [GlassItem] {
        [
            makeItem(name: "Design.pdf", kind: .regular, size: 524_288),
            makeItem(name: "Notes.txt", kind: .regular, size: 2_048),
            makeItem(name: "Assets", kind: .directory, size: nil),
            makeItem(name: "SchneeGlass.app", kind: .package, size: nil)
        ]
    }

    private func makeItem(name: String, kind: FileKind, size: Int64?) -> GlassItem {
        let url = fixtureURL.appendingPathComponent(name)
        return GlassItem(
            id: FileIdentity(
                resourceIdentifier: "workspace-visual-\(name)",
                standardizedURL: url
            ),
            url: url,
            displayName: name,
            kind: kind,
            modificationDate: Date(timeIntervalSince1970: 1_700_000_000),
            fileSize: size,
            isHidden: false
        )
    }
}

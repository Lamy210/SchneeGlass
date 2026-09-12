import Foundation
import SchneeGlassDesignSystem
import SwiftUI
import Testing

@MainActor
@Suite(.serialized)
struct DesignSystemComponentVisualSnapshotTests {
    private let stateMessageSize = CGSize(width: 360, height: 180)
    private let fileTileSize = CGSize(width: 124, height: 112)

    @Test
    func stateMessageDetailLight() {
        guard VisualSnapshotHarness.isEnabled else {
            return
        }

        assertComponentSnapshot(
            size: stateMessageSize,
            colorScheme: .light
        ) {
            SchneeGlassStateMessage(
                systemImage: "externaldrive.badge.exclamationmark",
                title: "Folder unavailable",
                detail: "The Glass stays here so it can be reconnected without losing its layout.",
                detailAlignment: .center
            )
        }
    }

    @Test
    func stateMessageNoDetailDark() {
        guard VisualSnapshotHarness.isEnabled else {
            return
        }

        assertComponentSnapshot(
            size: stateMessageSize,
            colorScheme: .dark
        ) {
            SchneeGlassStateMessage(
                systemImage: "tray.and.arrow.down",
                title: "Drop files here"
            )
        }
    }

    @Test
    func fileTileRegularLight() {
        guard VisualSnapshotHarness.isEnabled else {
            return
        }

        assertFileTileSnapshot(
            systemImage: "doc",
            title: "Design.pdf",
            colorScheme: .light
        )
    }

    @Test
    func fileTileDirectoryLight() {
        guard VisualSnapshotHarness.isEnabled else {
            return
        }

        assertFileTileSnapshot(
            systemImage: "folder",
            title: "Assets",
            colorScheme: .light
        )
    }

    @Test
    func fileTilePackageDark() {
        guard VisualSnapshotHarness.isEnabled else {
            return
        }

        assertFileTileSnapshot(
            systemImage: "shippingbox",
            title: "SchneeGlass.app",
            colorScheme: .dark
        )
    }

    @Test
    func fileTileLongNameLight() {
        guard VisualSnapshotHarness.isEnabled else {
            return
        }

        assertFileTileSnapshot(
            systemImage: "doc",
            title: "Quarterly Design Review Notes.pdf",
            colorScheme: .light
        )
    }

    private func assertFileTileSnapshot(
        systemImage: String,
        title: String,
        colorScheme: ColorScheme,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        assertComponentSnapshot(
            size: fileTileSize,
            colorScheme: colorScheme,
            fileID: fileID,
            filePath: filePath,
            testName: testName,
            line: line,
            column: column
        ) {
            SchneeGlassFileTile(
                systemImage: systemImage,
                title: title
            )
        }
    }

    private func assertComponentSnapshot<Content: View>(
        size: CGSize,
        colorScheme: ColorScheme,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column,
        @ViewBuilder content: () -> Content
    ) {
        VisualSnapshotHarness.assertView(
            size: size,
            colorScheme: colorScheme,
            padding: 20,
            marker: "SCHNEEGLASS_DESIGN_SYSTEM_SNAPSHOT_RESULT",
            fileID: fileID,
            filePath: filePath,
            testName: testName,
            line: line,
            column: column,
            content: content
        )
    }
}

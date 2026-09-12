import AppKit
import Foundation
import SchneeGlassDesignSystem
import SnapshotTesting
import SwiftUI
import Testing

@MainActor
@Suite(.serialized)
struct DesignSystemComponentVisualSnapshotTests {
    private let stateMessageSize = CGSize(width: 360, height: 180)
    private let fileTileSize = CGSize(width: 124, height: 112)

    @Test
    func stateMessageDetailLight() {
        guard visualSnapshotsAreEnabled else {
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
        guard visualSnapshotsAreEnabled else {
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
        guard visualSnapshotsAreEnabled else {
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
        guard visualSnapshotsAreEnabled else {
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
        guard visualSnapshotsAreEnabled else {
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
        guard visualSnapshotsAreEnabled else {
            return
        }

        assertFileTileSnapshot(
            systemImage: "doc",
            title: "Quarterly Design Review Notes.pdf",
            colorScheme: .light
        )
    }

    private var visualSnapshotsAreEnabled: Bool {
        ProcessInfo.processInfo.environment["SCHNEEGLASS_VISUAL_SNAPSHOTS"] == "1"
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
        let rootView = ZStack {
            Color(nsColor: .windowBackgroundColor)

            content()
                .padding(20)
        }
        .frame(width: size.width, height: size.height)
        .environment(\.colorScheme, colorScheme)
        .environment(\.locale, Locale(identifier: "en_US_POSIX"))
        .transaction { transaction in
            transaction.disablesAnimations = true
        }

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.appearance = NSAppearance(
            named: colorScheme == .dark ? .darkAqua : .aqua
        )
        hostingView.layoutSubtreeIfNeeded()

        print("SCHNEEGLASS_DESIGN_SYSTEM_SNAPSHOT_RESULT \(testName)")
        assertSnapshot(
            of: hostingView,
            as: .image(
                precision: 0.995,
                perceptualPrecision: 0.99,
                size: size
            ),
            named: "macos-26-xcode-26.6",
            fileID: fileID,
            file: filePath,
            testName: testName,
            line: line,
            column: column
        )
    }
}

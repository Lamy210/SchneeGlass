import AppKit
import FileDomain
import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import SnapshotTesting
import SwiftUI
import Testing
@testable import SchneeGlassPresentation

@MainActor
@Suite(.serialized)
struct DesktopGlassVisualSnapshotTests {
    private let snapshotSize = CGSize(width: 440, height: 320)

    @Test
    func emptyLight() {
        guard visualSnapshotsAreEnabled else {
            return
        }

        assertGlassSnapshot(
            entry: makeEntry(contentState: .empty(makeSnapshot(items: []))),
            colorScheme: .light
        )
    }

    @Test
    func readyLight() {
        guard visualSnapshotsAreEnabled else {
            return
        }

        assertGlassSnapshot(
            entry: makeEntry(contentState: .ready(makeSnapshot(items: makeItems()))),
            colorScheme: .light
        )
    }

    @Test
    func unavailableLight() {
        guard visualSnapshotsAreEnabled else {
            return
        }

        assertGlassSnapshot(
            entry: makeEntry(contentState: .unavailable(.volumeUnavailable)),
            colorScheme: .light
        )
    }

    @Test
    func failedLight() {
        guard visualSnapshotsAreEnabled else {
            return
        }

        assertGlassSnapshot(
            entry: makeEntry(contentState: .failed(.enumerationFailed)),
            colorScheme: .light
        )
    }

    @Test
    func dropValidLight() throws {
        guard visualSnapshotsAreEnabled else {
            return
        }

        let plan = try CopyBatchPlan(
            destination: makeDestination(),
            items: [
                CopyItemPlan(
                    sourceURL: fixtureURL.appendingPathComponent("Design.pdf"),
                    originalFilename: "Design.pdf",
                    destinationFilename: "Design.pdf",
                    expectedSize: 524_288
                )
            ],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        assertGlassSnapshot(
            entry: makeEntry(
                contentState: .ready(makeSnapshot(items: makeItems())),
                interactionState: .dropValid(.copy(plan))
            ),
            colorScheme: .light
        )
    }

    @Test
    func dropInvalidLight() {
        guard visualSnapshotsAreEnabled else {
            return
        }

        assertGlassSnapshot(
            entry: makeEntry(
                contentState: .ready(makeSnapshot(items: makeItems())),
                interactionState: .dropInvalid(.collision)
            ),
            colorScheme: .light
        )
    }

    @Test
    func emptyDark() {
        guard visualSnapshotsAreEnabled else {
            return
        }

        assertGlassSnapshot(
            entry: makeEntry(contentState: .empty(makeSnapshot(items: []))),
            colorScheme: .dark
        )
    }

    @Test
    func readyDark() {
        guard visualSnapshotsAreEnabled else {
            return
        }

        assertGlassSnapshot(
            entry: makeEntry(contentState: .ready(makeSnapshot(items: makeItems()))),
            colorScheme: .dark
        )
    }

    private var visualSnapshotsAreEnabled: Bool {
        ProcessInfo.processInfo.environment["SCHNEEGLASS_VISUAL_SNAPSHOTS"] == "1"
    }

    private var fixtureURL: URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("SchneeGlassVisualFixtures", isDirectory: true)
    }

    private func assertGlassSnapshot(
        entry: GlassWorkspaceEntry,
        colorScheme: ColorScheme,
        fileID: StaticString = #fileID,
        filePath: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        let rootView = ZStack {
            Color(nsColor: .windowBackgroundColor)

            DesktopGlassSurface(
                entry: entry,
                canRemove: true,
                onOpen: { _ in },
                onReveal: { _ in },
                onRemove: {},
                onPlanDrop: { _ in false },
                onCancelDrop: {},
                onPerformDrop: { _ in }
            )
            .padding(24)
        }
        .frame(width: snapshotSize.width, height: snapshotSize.height)
        .environment(\.colorScheme, colorScheme)
        .environment(\.locale, Locale(identifier: "en_US_POSIX"))
        .transaction { transaction in
            transaction.disablesAnimations = true
        }

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = NSRect(origin: .zero, size: snapshotSize)
        hostingView.appearance = NSAppearance(
            named: colorScheme == .dark ? .darkAqua : .aqua
        )
        hostingView.layoutSubtreeIfNeeded()

        print("SCHNEEGLASS_VISUAL_SNAPSHOT_RESULT \(testName)")
        assertSnapshot(
            of: hostingView,
            as: .image(
                precision: 0.995,
                perceptualPrecision: 0.99,
                size: snapshotSize
            ),
            named: "macos-26-xcode-26.6",
            fileID: fileID,
            file: filePath,
            testName: testName,
            line: line,
            column: column
        )
    }

    private func makeEntry(
        contentState: GlassContentState,
        interactionState: InteractionState = .idle
    ) -> GlassWorkspaceEntry {
        GlassWorkspaceEntry(
            id: GlassID(),
            title: "Projects",
            contentState: contentState,
            interactionState: interactionState
        )
    }

    private func makeSnapshot(items: [GlassItem]) -> FolderSnapshot {
        FolderSnapshot(
            folderIdentity: FolderIdentity(
                resourceIdentifier: "visual-fixture-folder",
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
            id: FileIdentity(resourceIdentifier: "visual-\(name)", standardizedURL: url),
            url: url,
            displayName: name,
            kind: kind,
            modificationDate: Date(timeIntervalSince1970: 1_700_000_000),
            fileSize: size,
            isHidden: false
        )
    }

    private func makeDestination() -> DestinationDescriptor {
        DestinationDescriptor(
            glassID: GlassID(),
            folderIdentity: FolderIdentity(
                resourceIdentifier: "visual-fixture-folder",
                standardizedURL: fixtureURL
            ),
            url: fixtureURL,
            capabilities: StorageCapabilities(
                locationKind: .localFixed,
                isWritable: true,
                supportsCaseSensitiveNames: true,
                supportsSafeDestinationCommit: true
            )
        )
    }
}

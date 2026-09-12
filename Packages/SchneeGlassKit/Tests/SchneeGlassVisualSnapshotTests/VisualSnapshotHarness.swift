import AppKit
import Foundation
import SnapshotTesting
import SwiftUI

@MainActor
enum VisualSnapshotHarness {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["SCHNEEGLASS_VISUAL_SNAPSHOTS"] == "1"
    }

    static func assertView<Content: View>(
        size: CGSize,
        colorScheme: ColorScheme,
        padding: CGFloat,
        marker: String,
        fileID: StaticString,
        filePath: StaticString,
        testName: String,
        line: UInt,
        column: UInt,
        @ViewBuilder content: () -> Content
    ) {
        let rootView = ZStack {
            Color(nsColor: .windowBackgroundColor)

            content()
                .padding(padding)
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

        print("\(marker) \(testName)")
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

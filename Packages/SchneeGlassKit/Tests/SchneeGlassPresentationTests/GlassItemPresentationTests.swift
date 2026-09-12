import FileDomain
import Foundation
import Testing
@testable import SchneeGlassPresentation

@Test
func glassItemPresentationCoversEveryFileKind() {
    assertItemPresentation(
        kind: .regular,
        systemImage: "doc",
        accessibilityLabel: "Example"
    )
    assertItemPresentation(
        kind: .directory,
        systemImage: "folder",
        accessibilityLabel: "Folder, Example"
    )
    assertItemPresentation(
        kind: .package,
        systemImage: "shippingbox",
        accessibilityLabel: "Package, Example"
    )
    assertItemPresentation(
        kind: .alias,
        systemImage: "arrowshape.turn.up.right",
        accessibilityLabel: "Alias, Example"
    )
    assertItemPresentation(
        kind: .symbolicLink,
        systemImage: "link",
        accessibilityLabel: "Symbolic link, Example"
    )
    assertItemPresentation(
        kind: .unsupported,
        systemImage: "questionmark.square",
        accessibilityLabel: "Example"
    )
}

private func assertItemPresentation(
    kind: FileKind,
    systemImage: String,
    accessibilityLabel: String
) {
    let item = GlassItem(
        id: FileIdentity(
            resourceIdentifier: "presentation-\(systemImage)",
            standardizedURL: URL(fileURLWithPath: "/tmp/SchneeGlassPresentationTests/Example")
        ),
        url: URL(fileURLWithPath: "/tmp/SchneeGlassPresentationTests/Example"),
        displayName: "Example",
        kind: kind,
        modificationDate: Date(timeIntervalSince1970: 1_700_000_000),
        fileSize: nil,
        isHidden: false
    )

    #expect(
        GlassItemPresentation.make(for: item)
            == .init(systemImage: systemImage, accessibilityLabel: accessibilityLabel)
    )
}

import FileDomain
import Foundation

struct GlassItemPresentation: Equatable {
    let systemImage: String
    let accessibilityLabel: String

    static func make(for item: GlassItem, locale: Locale = Locale(identifier: "en")) -> Self {
        Self(
            systemImage: systemImage(for: item.kind),
            accessibilityLabel: accessibilityLabel(for: item, locale: locale)
        )
    }

    private static func systemImage(for kind: FileKind) -> String {
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

    private static func accessibilityLabel(for item: GlassItem, locale: Locale) -> String {
        let key: GlassLocalizedText
        switch item.kind {
        case .directory:
            key = .tileFolder
        case .package:
            key = .tilePackage
        case .alias:
            key = .tileAlias
        case .symbolicLink:
            key = .tileSymbolicLink
        case .regular, .unsupported:
            return item.displayName
        }
        return String(format: key.resolve(locale: locale), locale: locale, item.displayName)
    }
}

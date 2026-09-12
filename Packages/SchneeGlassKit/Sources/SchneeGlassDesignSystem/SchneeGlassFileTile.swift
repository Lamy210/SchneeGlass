#if canImport(SwiftUI)
import SwiftUI

public struct SchneeGlassFileTile: View {
    private let systemImage: String
    private let title: String
    private let accessibilityLabel: String
    private let accessibilityHint: String

    public init(
        systemImage: String,
        title: String,
        accessibilityLabel: String,
        accessibilityHint: String
    ) {
        self.systemImage = systemImage
        self.title = title
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
    }

    public var body: some View {
        VStack(spacing: SchneeGlassSpacing.compactContent) {
            Image(systemName: systemImage)
                .font(.system(size: SchneeGlassMetrics.fileIconSize))
                .foregroundStyle(.primary)
                .frame(height: SchneeGlassMetrics.fileIconHeight)

            Text(title)
                .font(SchneeGlassTypography.supporting)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }
}
#endif

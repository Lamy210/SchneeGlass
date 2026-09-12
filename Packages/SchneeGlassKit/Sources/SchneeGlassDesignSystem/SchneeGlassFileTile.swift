#if canImport(SwiftUI)
import SwiftUI

public struct SchneeGlassFileTile: View {
    private let systemImage: String
    private let title: String

    public init(systemImage: String, title: String) {
        self.systemImage = systemImage
        self.title = title
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
    }
}
#endif

#if canImport(SwiftUI)
import SwiftUI

public struct SchneeGlassStateMessage: View {
    private let systemImage: String
    private let title: String
    private let detail: String?
    private let detailAlignment: TextAlignment

    public init(
        systemImage: String,
        title: String,
        detail: String? = nil,
        detailAlignment: TextAlignment = .leading
    ) {
        self.systemImage = systemImage
        self.title = title
        self.detail = detail
        self.detailAlignment = detailAlignment
    }

    public var body: some View {
        VStack(spacing: SchneeGlassSpacing.controlGroup) {
            Image(systemName: systemImage)
                .font(SchneeGlassTypography.largeSymbol)
                .foregroundStyle(.secondary)

            Text(title)
                .font(SchneeGlassTypography.emphasizedBody)

            if let detail {
                Text(detail)
                    .font(SchneeGlassTypography.supporting)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(detailAlignment)
            }
        }
    }
}
#endif

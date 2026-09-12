#if canImport(SwiftUI)
import SwiftUI

@available(*, deprecated, message: "Use the semantic SchneeGlassSpacing, SchneeGlassRadius, and SchneeGlassMetrics tokens instead.")
public enum SchneeGlassDesignTokens {
    public static let cornerRadius = SchneeGlassRadius.glassSurface
    public static let innerSpacing = SchneeGlassSpacing.surfaceContent
    public static let gridSpacing = SchneeGlassSpacing.fileGridColumn
    public static let headerHeight = SchneeGlassMetrics.headerHeight
    public static let minimumHitTarget = SchneeGlassMetrics.minimumControlHitTarget
}
#endif

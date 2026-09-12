#if canImport(SwiftUI)
import SwiftUI

public enum SchneeGlassTypography {
    public static let surfaceTitle = Font.headline
    public static let status = Font.caption
    public static let body = Font.callout
    public static let emphasizedBody = Font.callout.weight(.medium)
    public static let strongBody = Font.callout.weight(.semibold)
    public static let supporting = Font.caption
    public static let emptyStateTitle = Font.title3.weight(.semibold)
    public static let largeSymbol = Font.title2
}
#endif

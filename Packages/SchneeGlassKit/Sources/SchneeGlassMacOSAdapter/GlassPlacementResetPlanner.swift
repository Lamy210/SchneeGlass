import CoreGraphics
import SchneeGlassDomain

public struct GlassPlacementResetItem: Hashable, Sendable {
    public let id: GlassID
    public let currentPlacement: GlassPlacement?

    public init(id: GlassID, currentPlacement: GlassPlacement?) {
        self.id = id
        self.currentPlacement = currentPlacement
    }
}

public enum GlassPlacementResetPlanningError: Error, Hashable, Sendable {
    case screenTooSmall
}

/// Produces a deterministic rescue layout on one visible display.
///
/// Existing sizes are preserved whenever they fit. Oversized Glasses are reduced only as far as
/// the current visible frame requires, never below the domain minimum. The result is a cascade
/// from the top-left and every planned frame is fully contained in the supplied visible frame.
public enum GlassPlacementResetPlanner {
    private static let preferredMargin = 24.0
    private static let cascadeStep = 28.0

    public static func plan(
        items: [GlassPlacementResetItem],
        visibleFrame: CGRect,
        displayHint: String?
    ) throws -> [GlassID: GlassPlacement] {
        let screenWidth = Double(visibleFrame.width)
        let screenHeight = Double(visibleFrame.height)

        guard screenWidth >= GlassPlacement.minimumWidth,
              screenHeight >= GlassPlacement.minimumHeight
        else {
            throw GlassPlacementResetPlanningError.screenTooSmall
        }

        var placements: [GlassID: GlassPlacement] = [:]
        placements.reserveCapacity(items.count)

        for (index, item) in items.enumerated() {
            let requestedWidth = item.currentPlacement?.width ?? GlassPlacement.defaultWidth
            let requestedHeight = item.currentPlacement?.height ?? GlassPlacement.defaultHeight
            let width = min(requestedWidth, screenWidth)
            let height = min(requestedHeight, screenHeight)

            let minX = Double(visibleFrame.minX)
            let minY = Double(visibleFrame.minY)
            let maxXOrigin = Double(visibleFrame.maxX) - width
            let maxYOrigin = Double(visibleFrame.maxY) - height
            let horizontalRoom = max(0, maxXOrigin - minX)
            let verticalRoom = max(0, maxYOrigin - minY)

            let leftMargin = min(preferredMargin, horizontalRoom)
            let topMargin = min(preferredMargin, verticalRoom)
            let baseX = minX + leftMargin
            let baseY = maxYOrigin - topMargin

            let horizontalSteps = Int(max(0, floor((maxXOrigin - baseX) / cascadeStep)))
            let verticalSteps = Int(max(0, floor((baseY - minY) / cascadeStep)))
            let maximumCascadeSlot = min(horizontalSteps, verticalSteps)
            let slot = maximumCascadeSlot > 0 ? index % (maximumCascadeSlot + 1) : 0

            placements[item.id] = try GlassPlacement(
                x: baseX + Double(slot) * cascadeStep,
                y: baseY - Double(slot) * cascadeStep,
                width: width,
                height: height,
                displayHint: displayHint
            )
        }

        return placements
    }
}

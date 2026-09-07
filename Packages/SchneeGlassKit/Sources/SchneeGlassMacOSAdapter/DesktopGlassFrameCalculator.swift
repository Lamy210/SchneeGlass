import Foundation
import SchneeGlassDomain

public enum DesktopGlassFrameCalculator {
    public static let minimumRecoverableVisibleWidth = 80.0
    public static let minimumRecoverableVisibleHeight = 40.0

    public static func recoveredFrame(
        requestedFrame: CGRect,
        visibleFrames: [CGRect],
        preferredVisibleFrame: CGRect? = nil
    ) -> CGRect {
        guard !visibleFrames.isEmpty else {
            return requestedFrame
        }

        if visibleFrames.contains(where: { frame in
            let intersection = frame.intersection(requestedFrame)
            return !intersection.isNull &&
                intersection.width >= minimumRecoverableVisibleWidth &&
                intersection.height >= minimumRecoverableVisibleHeight
        }) {
            return requestedFrame
        }

        let target = preferredVisibleFrame.flatMap { preferred in
            visibleFrames.first(where: { approximatelyEqual($0, preferred) })
        } ?? visibleFrames[0]

        let width = min(
            max(requestedFrame.width, GlassPlacement.minimumWidth),
            target.width
        )
        let height = min(
            max(requestedFrame.height, GlassPlacement.minimumHeight),
            target.height
        )
        let x = min(max(requestedFrame.origin.x, target.minX), target.maxX - width)
        let y = min(max(requestedFrame.origin.y, target.minY), target.maxY - height)

        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func approximatelyEqual(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) < 0.5 &&
            abs(lhs.origin.y - rhs.origin.y) < 0.5 &&
            abs(lhs.width - rhs.width) < 0.5 &&
            abs(lhs.height - rhs.height) < 0.5
    }
}

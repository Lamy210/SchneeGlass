import CoreGraphics

public enum DesktopGlassDragConstraint {
  public static let minimumVisibleWidth =
    DesktopGlassFrameCalculator.minimumRecoverableVisibleWidth
  public static let minimumVisibleHeight =
    DesktopGlassFrameCalculator.minimumRecoverableVisibleHeight

  public static func constrainedFrame(
    requestedFrame: CGRect,
    visibleFrames: [CGRect],
    preferredVisibleFrame: CGRect? = nil
  ) -> CGRect {
    guard !visibleFrames.isEmpty else {
      return requestedFrame
    }

    if visibleFrames.contains(where: { hasMinimumVisibleArea(requestedFrame, in: $0) }) {
      return requestedFrame
    }

    let target = targetVisibleFrame(
      for: requestedFrame,
      visibleFrames: visibleFrames,
      preferredVisibleFrame: preferredVisibleFrame
    )
    let requiredWidth = min(minimumVisibleWidth, max(0, requestedFrame.width), target.width)
    let requiredHeight = min(minimumVisibleHeight, max(0, requestedFrame.height), target.height)

    let minimumX = target.minX - requestedFrame.width + requiredWidth
    let maximumX = target.maxX - requiredWidth
    let minimumY = target.minY - requestedFrame.height + requiredHeight
    let maximumY = target.maxY - requiredHeight

    return CGRect(
      x: clamp(requestedFrame.minX, lower: minimumX, upper: maximumX),
      y: clamp(requestedFrame.minY, lower: minimumY, upper: maximumY),
      width: requestedFrame.width,
      height: requestedFrame.height
    )
  }

  private static func hasMinimumVisibleArea(_ frame: CGRect, in visibleFrame: CGRect) -> Bool {
    let intersection = frame.intersection(visibleFrame)
    return !intersection.isNull
      && intersection.width >= min(minimumVisibleWidth, frame.width)
      && intersection.height >= min(minimumVisibleHeight, frame.height)
  }

  private static func targetVisibleFrame(
    for requestedFrame: CGRect,
    visibleFrames: [CGRect],
    preferredVisibleFrame: CGRect?
  ) -> CGRect {
    if let preferredVisibleFrame,
      let matching = visibleFrames.first(where: { approximatelyEqual($0, preferredVisibleFrame) })
    {
      return matching
    }

    return visibleFrames.max { lhs, rhs in
      intersectionArea(requestedFrame, lhs) < intersectionArea(requestedFrame, rhs)
    } ?? visibleFrames[0]
  }

  private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
    let intersection = lhs.intersection(rhs)
    guard !intersection.isNull else {
      return 0
    }
    return intersection.width * intersection.height
  }

  private static func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
    guard lower <= upper else {
      return lower
    }
    return min(max(value, lower), upper)
  }

  private static func approximatelyEqual(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
    abs(lhs.origin.x - rhs.origin.x) < 0.5 && abs(lhs.origin.y - rhs.origin.y) < 0.5
      && abs(lhs.width - rhs.width) < 0.5 && abs(lhs.height - rhs.height) < 0.5
  }
}

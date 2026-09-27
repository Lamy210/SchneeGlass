import Foundation

public enum DesktopGlassSnapPreset: String, CaseIterable, Sendable {
  case topLeft
  case topRight
  case bottomLeft
  case bottomRight
  case center
}

public enum DesktopGlassSnapPlanner {
  public static let defaultMargin: CGFloat = 16

  public static func frame(
    currentFrame: CGRect,
    visibleFrame: CGRect,
    preset: DesktopGlassSnapPreset,
    margin: CGFloat = defaultMargin
  ) -> CGRect {
    let width = min(max(currentFrame.width, 1), visibleFrame.width)
    let height = min(max(currentFrame.height, 1), visibleFrame.height)
    let horizontalMargin = min(
      max(margin, 0),
      max((visibleFrame.width - width) / 2, 0)
    )
    let verticalMargin = min(
      max(margin, 0),
      max((visibleFrame.height - height) / 2, 0)
    )

    let left = visibleFrame.minX + horizontalMargin
    let right = visibleFrame.maxX - width - horizontalMargin
    let bottom = visibleFrame.minY + verticalMargin
    let top = visibleFrame.maxY - height - verticalMargin
    let centerX = visibleFrame.midX - (width / 2)
    let centerY = visibleFrame.midY - (height / 2)

    let origin: CGPoint
    switch preset {
    case .topLeft:
      origin = CGPoint(x: left, y: top)
    case .topRight:
      origin = CGPoint(x: right, y: top)
    case .bottomLeft:
      origin = CGPoint(x: left, y: bottom)
    case .bottomRight:
      origin = CGPoint(x: right, y: bottom)
    case .center:
      origin = CGPoint(x: centerX, y: centerY)
    }

    return CGRect(
      x: origin.x,
      y: origin.y,
      width: width,
      height: height
    )
  }
}

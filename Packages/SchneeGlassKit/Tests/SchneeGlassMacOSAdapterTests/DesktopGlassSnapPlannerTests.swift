import Foundation
import SchneeGlassMacOSAdapter
import Testing

@Test
func topLeftSnapUsesVisibleFrameOriginAndMargin() {
  let visible = CGRect(x: 100, y: 50, width: 1200, height: 800)
  let current = CGRect(x: 500, y: 400, width: 360, height: 260)

  let result = DesktopGlassSnapPlanner.frame(
    currentFrame: current,
    visibleFrame: visible,
    preset: .topLeft
  )

  #expect(result == CGRect(x: 116, y: 574, width: 360, height: 260))
}

@Test
func bottomRightSnapRespectsNonZeroDisplayOrigin() {
  let visible = CGRect(x: 1440, y: -120, width: 1000, height: 700)
  let current = CGRect(x: 1600, y: 100, width: 420, height: 300)

  let result = DesktopGlassSnapPlanner.frame(
    currentFrame: current,
    visibleFrame: visible,
    preset: .bottomRight
  )

  #expect(result == CGRect(x: 2004, y: -104, width: 420, height: 300))
}

@Test
func centerSnapPreservesCurrentSize() {
  let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
  let current = CGRect(x: 20, y: 20, width: 500, height: 320)

  let result = DesktopGlassSnapPlanner.frame(
    currentFrame: current,
    visibleFrame: visible,
    preset: .center
  )

  #expect(result == CGRect(x: 470, y: 290, width: 500, height: 320))
}

@Test
func oversizedFrameIsBoundedToVisibleFrame() {
  let visible = CGRect(x: 100, y: 50, width: 800, height: 600)
  let current = CGRect(x: 0, y: 0, width: 1600, height: 1200)

  let result = DesktopGlassSnapPlanner.frame(
    currentFrame: current,
    visibleFrame: visible,
    preset: .bottomRight
  )

  #expect(result == visible)
}

@Test
func excessiveMarginIsClampedWithoutPushingFrameOffscreen() {
  let visible = CGRect(x: 0, y: 0, width: 500, height: 400)
  let current = CGRect(x: 0, y: 0, width: 460, height: 360)

  let result = DesktopGlassSnapPlanner.frame(
    currentFrame: current,
    visibleFrame: visible,
    preset: .topRight,
    margin: 100
  )

  #expect(result == CGRect(x: 20, y: 20, width: 460, height: 360))
  #expect(visible.contains(result))
}

@Test
func negativeMarginIsTreatedAsZero() {
  let visible = CGRect(x: 0, y: 0, width: 800, height: 600)
  let current = CGRect(x: 200, y: 200, width: 300, height: 200)

  let result = DesktopGlassSnapPlanner.frame(
    currentFrame: current,
    visibleFrame: visible,
    preset: .bottomLeft,
    margin: -10
  )

  #expect(result == CGRect(x: 0, y: 0, width: 300, height: 200))
}

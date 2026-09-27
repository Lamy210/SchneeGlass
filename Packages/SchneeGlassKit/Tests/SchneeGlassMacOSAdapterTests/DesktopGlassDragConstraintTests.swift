import CoreGraphics
import Testing

@testable import SchneeGlassMacOSAdapter

@Test
func reachableFrameIsUnchanged() {
  let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
  let requested = CGRect(x: 100, y: 120, width: 360, height: 260)

  let constrained = DesktopGlassDragConstraint.constrainedFrame(
    requestedFrame: requested,
    visibleFrames: [screen]
  )

  #expect(constrained == requested)
}

@Test
func mostlyOffscreenFrameKeepsMinimumReachableArea() {
  let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
  let requested = CGRect(x: 1400, y: 870, width: 360, height: 260)

  let constrained = DesktopGlassDragConstraint.constrainedFrame(
    requestedFrame: requested,
    visibleFrames: [screen]
  )
  let intersection = constrained.intersection(screen)

  #expect(constrained.size == requested.size)
  #expect(intersection.width >= DesktopGlassDragConstraint.minimumVisibleWidth)
  #expect(intersection.height >= DesktopGlassDragConstraint.minimumVisibleHeight)
}

@Test
func frameVisibleOnSecondDisplayIsNotPulledBackToPreferredDisplay() {
  let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
  let secondary = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
  let requested = CGRect(x: 1600, y: 300, width: 360, height: 260)

  let constrained = DesktopGlassDragConstraint.constrainedFrame(
    requestedFrame: requested,
    visibleFrames: [primary, secondary],
    preferredVisibleFrame: primary
  )

  #expect(constrained == requested)
}

@Test
func completelyOffscreenFrameUsesPreferredDisplayForRescue() {
  let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
  let secondary = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
  let requested = CGRect(x: -4000, y: -4000, width: 360, height: 260)

  let constrained = DesktopGlassDragConstraint.constrainedFrame(
    requestedFrame: requested,
    visibleFrames: [primary, secondary],
    preferredVisibleFrame: secondary
  )
  let intersection = constrained.intersection(secondary)

  #expect(intersection.width >= DesktopGlassDragConstraint.minimumVisibleWidth)
  #expect(intersection.height >= DesktopGlassDragConstraint.minimumVisibleHeight)
  #expect(constrained.size == requested.size)
}

@Test
func noVisibleFramesLeavesRequestedFrameUnchanged() {
  let requested = CGRect(x: -4000, y: -4000, width: 360, height: 260)

  let constrained = DesktopGlassDragConstraint.constrainedFrame(
    requestedFrame: requested,
    visibleFrames: []
  )

  #expect(constrained == requested)
}

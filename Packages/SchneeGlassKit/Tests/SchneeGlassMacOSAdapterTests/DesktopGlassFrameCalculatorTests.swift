import Foundation
import SchneeGlassMacOSAdapter
import Testing

@Test
func visibleFrameIsPreservedWithoutClamping() {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let requested = CGRect(x: 100, y: 100, width: 360, height: 260)

    let result = DesktopGlassFrameCalculator.recoveredFrame(
        requestedFrame: requested,
        visibleFrames: [screen],
        preferredVisibleFrame: screen
    )

    #expect(result == requested)
}

@Test
func tinyOffscreenSliverIsRecoveredIntoPreferredDisplay() {
    let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let requested = CGRect(x: 1425, y: 890, width: 360, height: 260)

    let result = DesktopGlassFrameCalculator.recoveredFrame(
        requestedFrame: requested,
        visibleFrames: [primary],
        preferredVisibleFrame: primary
    )

    #expect(result.maxX <= primary.maxX)
    #expect(result.maxY <= primary.maxY)
    #expect(result.minX >= primary.minX)
    #expect(result.minY >= primary.minY)
}

@Test
func meaningfulPartialVisibilityIsPreserved() {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let requested = CGRect(x: -250, y: 100, width: 360, height: 260)

    let result = DesktopGlassFrameCalculator.recoveredFrame(
        requestedFrame: requested,
        visibleFrames: [screen],
        preferredVisibleFrame: screen
    )

    #expect(result == requested)
}

@Test
func missingExternalDisplayRecoversToCurrentPrimaryWithoutChangingRequestedSize() {
    let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let requested = CGRect(x: 3000, y: 300, width: 420, height: 300)

    let result = DesktopGlassFrameCalculator.recoveredFrame(
        requestedFrame: requested,
        visibleFrames: [primary],
        preferredVisibleFrame: primary
    )

    #expect(result.size == requested.size)
    #expect(primary.contains(result))
}

@Test
func oversizedSavedFrameIsBoundedToAvailableDisplay() {
    let screen = CGRect(x: 0, y: 0, width: 800, height: 600)
    let requested = CGRect(x: 2000, y: 0, width: 1600, height: 1200)

    let result = DesktopGlassFrameCalculator.recoveredFrame(
        requestedFrame: requested,
        visibleFrames: [screen],
        preferredVisibleFrame: screen
    )

    #expect(result == screen)
}

@Test
func noScreensLeavesRequestedFrameUntouched() {
    let requested = CGRect(x: 2000, y: 500, width: 360, height: 260)

    let result = DesktopGlassFrameCalculator.recoveredFrame(
        requestedFrame: requested,
        visibleFrames: []
    )

    #expect(result == requested)
}

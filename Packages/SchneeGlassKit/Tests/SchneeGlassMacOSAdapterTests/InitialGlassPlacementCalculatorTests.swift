import CoreGraphics
@testable import SchneeGlassMacOSAdapter
import Testing

@Test
func centersDefaultPlacementInsideVisibleFrame() throws {
    let frame = CGRect(x: 100, y: 200, width: 1200, height: 800)

    let placement = try InitialGlassPlacementCalculator.placement(in: frame)

    #expect(placement.width == 360)
    #expect(placement.height == 260)
    #expect(placement.x == 520)
    #expect(placement.y == 470)
}

@Test
func rejectsVisibleFrameSmallerThanMinimumGlassSize() {
    let frame = CGRect(x: 0, y: 0, width: 200, height: 120)

    #expect(throws: InitialGlassPlacementError.screenTooSmall) {
        _ = try InitialGlassPlacementCalculator.placement(in: frame)
    }
}

@Test
func placementUsesFullAvailableFrameWhenItMatchesMinimumSize() throws {
    let frame = CGRect(
        x: 40,
        y: 60,
        width: 240,
        height: 160
    )

    let placement = try InitialGlassPlacementCalculator.placement(in: frame)

    #expect(placement.x == frame.minX)
    #expect(placement.y == frame.minY)
    #expect(placement.width == frame.width)
    #expect(placement.height == frame.height)
}

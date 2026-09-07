import CoreGraphics
@testable import SchneeGlassMacOSAdapter
import Testing

private let placementTolerance = 0.001

@Test
func centersDefaultPlacementInsideVisibleFrame() throws {
    let frame = CGRect(x: 100, y: 200, width: 1200, height: 800)

    let placement = try InitialGlassPlacementCalculator.placement(in: frame)

    #expect(abs(placement.width - 360) < placementTolerance)
    #expect(abs(placement.height - 260) < placementTolerance)
    #expect(abs(placement.x - 520) < placementTolerance)
    #expect(abs(placement.y - 470) < placementTolerance)
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

    #expect(abs(placement.x - Double(frame.minX)) < placementTolerance)
    #expect(abs(placement.y - Double(frame.minY)) < placementTolerance)
    #expect(abs(placement.width - Double(frame.width)) < placementTolerance)
    #expect(abs(placement.height - Double(frame.height)) < placementTolerance)
}

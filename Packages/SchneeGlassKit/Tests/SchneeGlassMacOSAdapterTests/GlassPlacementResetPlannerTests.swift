import CoreGraphics
import SchneeGlassDomain
@testable import SchneeGlassMacOSAdapter
import Testing

@Test
func resetPlannerCascadesGlassesInsideVisibleFrame() throws {
    let ids = [GlassID(), GlassID(), GlassID()]
    let items = try ids.enumerated().map { index, id in
        GlassPlacementResetItem(
            id: id,
            currentPlacement: try GlassPlacement(
                x: Double(index) * 100,
                y: Double(index) * 100,
                width: 360,
                height: 260
            )
        )
    }
    let visibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)

    let planned = try GlassPlacementResetPlanner.plan(
        items: items,
        visibleFrame: visibleFrame,
        displayHint: "Built-in Display"
    )

    #expect(planned.count == 3)
    let first = try #require(planned[ids[0]])
    let second = try #require(planned[ids[1]])
    let third = try #require(planned[ids[2]])

    #expect(first.x == 24)
    #expect(second.x == 52)
    #expect(third.x == 80)
    #expect(first.y == 616)
    #expect(second.y == 588)
    #expect(third.y == 560)
    #expect(planned.values.allSatisfy { placement in
        placement.x >= Double(visibleFrame.minX) &&
            placement.y >= Double(visibleFrame.minY) &&
            placement.x + placement.width <= Double(visibleFrame.maxX) &&
            placement.y + placement.height <= Double(visibleFrame.maxY)
    })
    #expect(planned.values.allSatisfy { $0.displayHint == "Built-in Display" })
}

@Test
func resetPlannerPreservesSizesThatFitAndClampsOversizedGlass() throws {
    let normalID = GlassID()
    let oversizedID = GlassID()
    let visibleFrame = CGRect(x: 100, y: 50, width: 800, height: 600)
    let items = [
        GlassPlacementResetItem(
            id: normalID,
            currentPlacement: try GlassPlacement(x: -2000, y: 9000, width: 420, height: 320)
        ),
        GlassPlacementResetItem(
            id: oversizedID,
            currentPlacement: try GlassPlacement(x: 0, y: 0, width: 1600, height: 1200)
        ),
    ]

    let planned = try GlassPlacementResetPlanner.plan(
        items: items,
        visibleFrame: visibleFrame,
        displayHint: "Main"
    )

    let normal = try #require(planned[normalID])
    let oversized = try #require(planned[oversizedID])
    #expect(normal.width == 420)
    #expect(normal.height == 320)
    #expect(oversized.width == 800)
    #expect(oversized.height == 600)
    #expect(oversized.x == 100)
    #expect(oversized.y == 50)
}

@Test
func resetPlannerUsesDefaultSizeWhenPlacementIsUnavailable() throws {
    let id = GlassID()

    let planned = try GlassPlacementResetPlanner.plan(
        items: [GlassPlacementResetItem(id: id, currentPlacement: nil)],
        visibleFrame: CGRect(x: 0, y: 0, width: 1024, height: 768),
        displayHint: nil
    )

    let placement = try #require(planned[id])
    #expect(placement.width == GlassPlacement.defaultWidth)
    #expect(placement.height == GlassPlacement.defaultHeight)
}

@Test
func resetPlannerRejectsScreenBelowDomainMinimum() throws {
    do {
        _ = try GlassPlacementResetPlanner.plan(
            items: [GlassPlacementResetItem(id: GlassID(), currentPlacement: nil)],
            visibleFrame: CGRect(x: 0, y: 0, width: 200, height: 120),
            displayHint: nil
        )
        Issue.record("Expected screenTooSmall")
    } catch let error as GlassPlacementResetPlanningError {
        #expect(error == .screenTooSmall)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

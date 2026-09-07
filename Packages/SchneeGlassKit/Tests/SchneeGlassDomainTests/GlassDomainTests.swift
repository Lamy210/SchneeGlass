import Foundation
import Testing
@testable import SchneeGlassDomain

@Test
func glassConfigurationNormalizesTitle() throws {
    let placement = try GlassPlacement(x: 0, y: 0)
    let source = FolderSource(bookmarkData: Data([0x01]), lastKnownPath: "/example")

    let configuration = try GlassConfiguration(
        title: "  Projects  ",
        source: source,
        placement: placement
    )

    #expect(configuration.title == "Projects")
}

@Test
func glassPlacementRejectsTooSmallWidth() {
    #expect(throws: GlassPlacementValidationError.widthBelowMinimum) {
        _ = try GlassPlacement(x: 0, y: 0, width: 239, height: 160)
    }
}

@Test
func decodedGlassPlacementStillEnforcesMinimumSize() {
    let invalidJSON = Data(#"{"x":0,"y":0,"width":100,"height":260}"#.utf8)

    #expect(throws: GlassPlacementValidationError.widthBelowMinimum) {
        _ = try JSONDecoder().decode(GlassPlacement.self, from: invalidJSON)
    }
}

@Test
func decodedGlassConfigurationStillEnforcesTitleInvariant() throws {
    let placement = try GlassPlacement(x: 0, y: 0)
    let source = FolderSource(bookmarkData: Data([0x01]), lastKnownPath: "/example")
    let valid = try GlassConfiguration(title: "Projects", source: source, placement: placement)
    var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(valid)) as? [String: Any])
    object["title"] = "   "
    let invalidData = try JSONSerialization.data(withJSONObject: object)

    #expect(throws: GlassConfigurationValidationError.emptyTitle) {
        _ = try JSONDecoder().decode(GlassConfiguration.self, from: invalidData)
    }
}

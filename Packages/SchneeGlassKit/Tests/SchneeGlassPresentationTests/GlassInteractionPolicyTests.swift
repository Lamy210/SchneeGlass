import Testing
@testable import SchneeGlassPresentation

@Test
func removalAvailabilityMatchesDropInteractionHandoff() {
    #expect(GlassInteractionPolicy.allowsRemoval(during: .idle))
    #expect(GlassInteractionPolicy.allowsRemoval(during: .dropInvalid(.collision)))
    #expect(!GlassInteractionPolicy.allowsRemoval(during: .hovered))
    #expect(!GlassInteractionPolicy.allowsRemoval(during: .dropValid(.noOperation)))
    #expect(
        !GlassInteractionPolicy.allowsRemoval(
            during: .copying(
                .init(
                    currentIndex: 1,
                    totalCount: 1,
                    currentFilename: "source.txt"
                )
            )
        )
    )
}

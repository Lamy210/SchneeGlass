import SchneeGlassApplication
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

@Test
func copyCancellationIsAvailableOnlyWhileCopying() {
    let copying = InteractionState.copying(
        .init(
            currentIndex: 1,
            totalCount: 2,
            currentFilename: "source.txt"
        )
    )

    #expect(GlassInteractionPolicy.allowsCopyCancellation(during: copying))
    #expect(!GlassInteractionPolicy.allowsCopyCancellation(during: .idle))
    #expect(!GlassInteractionPolicy.allowsCopyCancellation(during: .hovered))
    #expect(!GlassInteractionPolicy.allowsCopyCancellation(during: .dropValid(.noOperation)))
    #expect(!GlassInteractionPolicy.allowsCopyCancellation(during: .dropInvalid(.collision)))
}

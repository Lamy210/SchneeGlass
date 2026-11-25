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

@Test
func overlappingDropRejectionDoesNotHideActiveCopyOrExecutionReservation() {
  let copying = InteractionState.copying(
    .init(
      currentIndex: 1,
      totalCount: 2,
      currentFilename: "example.txt"
    )
  )

  // A second hover/Drop can be rejected while the first execution is active.
  // Its unavailable feedback must not replace progress and Cancel Copy.
  #expect(
    !GlassInteractionPolicy.allowsRejectedDropFeedback(
      during: copying,
      hasActiveExecution: true
    )
  )
  // Keep the copying UI even if the execution gate has just been released.
  #expect(
    !GlassInteractionPolicy.allowsRejectedDropFeedback(
      during: copying,
      hasActiveExecution: false
    )
  )
  // Reservation starts before the asynchronous copy plan finishes.
  #expect(
    !GlassInteractionPolicy.allowsRejectedDropFeedback(
      during: .hovered,
      hasActiveExecution: true
    )
  )
  #expect(
    !GlassInteractionPolicy.allowsRejectedDropFeedback(
      during: .idle,
      hasActiveExecution: true
    )
  )

  // Ordinary inactive Drop rejections should still explain why they failed.
  for state in [
    InteractionState.idle,
    .hovered,
    .dropValid(.noOperation),
    .dropInvalid(.collision),
  ] {
    #expect(
      GlassInteractionPolicy.allowsRejectedDropFeedback(
        during: state,
        hasActiveExecution: false
      )
    )
  }
}

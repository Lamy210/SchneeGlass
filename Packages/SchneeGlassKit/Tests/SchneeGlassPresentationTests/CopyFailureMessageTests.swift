import Foundation
import SchneeGlassApplication
import Testing

@testable import SchneeGlassPresentation

@Test
@MainActor
func commitStateUnknownMessageDoesNotClaimNothingWasCopied() {
  let failure = CopyItemFailure(
    operationID: UUID(),
    reason: .commitStateUnknown
  )

  let message = SchneeGlassWorkspaceModel.copyFailureMessage(
    failure,
    succeededCount: 0
  )

  #expect(message.contains("may have created the current destination file"))
  #expect(message.contains("Check Recovery before retrying"))
  #expect(!message.contains("Nothing was copied"))
}

@Test
@MainActor
func commitStateUnknownMessagePreservesPriorSuccessCount() {
  let failure = CopyItemFailure(
    operationID: UUID(),
    reason: .commitStateUnknown
  )

  let message = SchneeGlassWorkspaceModel.copyFailureMessage(
    failure,
    succeededCount: 2
  )

  #expect(message.contains("2 file(s) were copied before the operation stopped."))
  #expect(message.contains("may have created the current destination file"))
  #expect(message.contains("Check Recovery before retrying"))
}

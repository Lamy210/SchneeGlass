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

  #expect(message.contains("may have created the destination file"))
  #expect(message.contains("Check Recovery before retrying"))
  #expect(!message.contains("Nothing was copied"))
}

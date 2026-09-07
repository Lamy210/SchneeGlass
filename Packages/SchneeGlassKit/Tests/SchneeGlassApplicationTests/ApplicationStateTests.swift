import Foundation
import Testing
@testable import SchneeGlassApplication
import FileDomain

@Test
func batchResultRepresentsPartialSuccessWithoutRollback() {
    let batchID = UUID()
    let successID = UUID()
    let failedID = UUID()
    let pending = CopyItemPlan(
        sourceURL: URL(fileURLWithPath: "/tmp/source-d.txt"),
        originalFilename: "source-d.txt",
        destinationFilename: "source-d.txt"
    )

    let result = CopyBatchResult(
        batchID: batchID,
        succeeded: [
            CopyItemSuccess(
                operationID: successID,
                destinationURL: URL(fileURLWithPath: "/tmp/destination-a.txt")
            )
        ],
        failed: CopyItemFailure(operationID: failedID, reason: .insufficientSpace),
        notAttempted: [pending]
    )

    #expect(result.succeeded.count == 1)
    #expect(result.failed?.reason == .insufficientSpace)
    #expect(result.notAttempted == [pending])
}

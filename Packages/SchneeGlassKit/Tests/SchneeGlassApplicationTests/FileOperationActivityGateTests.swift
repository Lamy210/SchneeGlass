import FileDomain
import Foundation
@testable import SchneeGlassApplication
import SchneeGlassDomain
import Testing

private actor ActivityGateCopyDelegate: FileCopying {
    private var callCount = 0

    func copy(_ request: AuthorizedCopyBatchRequest) async -> CopyBatchResult {
        callCount += 1
        let first = request.plan.items[0]
        return CopyBatchResult(
            batchID: request.plan.batchID,
            succeeded: [
                CopyItemSuccess(
                    operationID: first.operationID,
                    destinationURL: request.plan.destination.url
                        .appendingPathComponent(first.destinationFilename)
                )
            ],
            failed: nil,
            notAttempted: []
        )
    }

    func calls() -> Int { callCount }
}

private func activityGateRequest() throws -> AuthorizedCopyBatchRequest {
    let glassID = GlassID()
    let destinationURL = URL(fileURLWithPath: "/tmp/SchneeGlass-Destination", isDirectory: true)
    let destination = DestinationDescriptor(
        glassID: glassID,
        folderIdentity: FolderIdentity(resourceIdentifier: nil, standardizedURL: destinationURL),
        url: destinationURL,
        capabilities: StorageCapabilities(locationKind: .localFixed, isWritable: true)
    )
    let plan = try CopyBatchPlan(
        destination: destination,
        items: [
            CopyItemPlan(
                sourceURL: URL(fileURLWithPath: "/tmp/source.txt"),
                originalFilename: "source.txt",
                destinationFilename: "source.txt",
                expectedSize: 1
            )
        ]
    )
    return AuthorizedCopyBatchRequest(
        plan: plan,
        destinationAccess: FolderAccessHandle(glassID: glassID, url: destinationURL)
    )
}

@Test
func fileOperationGateRejectsRecoveryWhileCopyIsActive() async {
    let gate = FileOperationActivityGate()

    #expect(await gate.beginCopy())
    #expect(await gate.beginRecoveryMutation() == .copyInProgress)
    await gate.endCopy()

    #expect(await gate.beginRecoveryMutation() == .granted)
    await gate.endRecoveryMutation()
}

@Test
func activityTrackedCopyIsRejectedBeforeDelegateDuringRecoveryMutation() async throws {
    let gate = FileOperationActivityGate()
    let delegate = ActivityGateCopyDelegate()
    let tracked = ActivityTrackedFileCopying(delegate: delegate, activityGate: gate)
    let request = try activityGateRequest()

    #expect(await gate.beginRecoveryMutation() == .granted)
    let blocked = await tracked.copy(request)

    #expect(await delegate.calls() == 0)
    #expect(blocked.succeeded.isEmpty)
    #expect(blocked.failed?.reason == .cancelled)
    #expect(blocked.failed?.operationID == request.plan.items[0].operationID)

    await gate.endRecoveryMutation()

    let allowed = await tracked.copy(request)
    #expect(await delegate.calls() == 1)
    #expect(allowed.failed == nil)
    #expect(allowed.succeeded.count == 1)
    #expect(!(await gate.hasActiveCopies()))
}

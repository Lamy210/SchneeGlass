import FileDomain
import Foundation
@testable import SchneeGlassApplication
import SchneeGlassDomain
import Testing

private actor ActivityGateCopyDelegate: FileCopying, AuthorizedCopyBatchAbandoning {
    private var callCount = 0
    private var abandonedOperationIDs: [[UUID]] = []

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

    func abandon(_ request: AuthorizedCopyBatchRequest) async {
        abandonedOperationIDs.append(request.plan.items.map(\.operationID))
    }

    func calls() -> Int { callCount }
    func abandoned() -> [[UUID]] { abandonedOperationIDs }
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
func activityTrackedCopyReleasesAuthorityBeforeRejectingDuringRecoveryMutation() async throws {
    let gate = FileOperationActivityGate()
    let delegate = ActivityGateCopyDelegate()
    let tracked = ActivityTrackedFileCopying(
        delegate: delegate,
        abandoner: delegate,
        activityGate: gate
    )
    let request = try activityGateRequest()

    #expect(await gate.beginRecoveryMutation() == .granted)
    let blocked = await tracked.copy(request)

    #expect(await delegate.calls() == 0)
    #expect(await delegate.abandoned() == [request.plan.items.map(\.operationID)])
    #expect(blocked.succeeded.isEmpty)
    #expect(blocked.failed?.reason == .cancelled)
    #expect(blocked.failed?.operationID == request.plan.items[0].operationID)

    await gate.endRecoveryMutation()

    let allowed = await tracked.copy(request)
    #expect(await delegate.calls() == 1)
    #expect(await delegate.abandoned() == [request.plan.items.map(\.operationID)])
    #expect(allowed.failed == nil)
    #expect(allowed.succeeded.count == 1)
    #expect(!(await gate.hasActiveCopies()))
}

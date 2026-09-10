import Foundation
@testable import FileDomain
import SchneeGlassDomain
import Testing

private func destination(
    url: URL = URL(fileURLWithPath: "/tmp/SchneeGlassDestination", isDirectory: true),
    locationKind: StorageLocationKind = .localFixed,
    isWritable: Bool = true,
    supportsSafeDestinationCommit: Bool? = true
) -> DestinationDescriptor {
    DestinationDescriptor(
        glassID: GlassID(),
        folderIdentity: FolderIdentity(resourceIdentifier: nil, standardizedURL: url),
        url: url,
        capabilities: StorageCapabilities(
            locationKind: locationKind,
            isWritable: isWritable,
            supportsSafeDestinationCommit: supportsSafeDestinationCommit
        )
    )
}

private func candidate(
    _ path: String = "/tmp/SchneeGlassSource/sample.txt",
    kind: FileKind = .regular,
    size: Int64? = 10
) -> DropCandidate {
    DropCandidate(url: URL(fileURLWithPath: path), kind: kind, size: size)
}

@Test("regular local file produces a copy plan")
func regularFileProducesCopyPlan() throws {
    let result = DropPlanner.plan(
        DropPlanningContext(
            candidates: [candidate()],
            destination: destination()
        )
    )

    guard case let .copy(plan) = result else {
        Issue.record("Expected a copy plan")
        return
    }

    #expect(plan.items.count == 1)
    #expect(plan.items[0].destinationFilename == "sample.txt")
    #expect(plan.items[0].expectedSize == 10)
}

@Test(
    "unsupported item kinds are rejected",
    arguments: [
        (FileKind.directory, DropRejection.unsupportedFolder),
        (FileKind.package, DropRejection.unsupportedPackage),
        (FileKind.symbolicLink, DropRejection.unsupportedSymbolicLink),
        (FileKind.alias, DropRejection.unsupportedItem),
        (FileKind.unsupported, DropRejection.unsupportedItem),
    ]
)
func unsupportedKindsAreRejected(kind: FileKind, expected: DropRejection) {
    let result = DropPlanner.plan(
        DropPlanningContext(
            candidates: [candidate(kind: kind)],
            destination: destination()
        )
    )

    #expect(result == .reject(expected))
}

@Test("network destination is rejected")
func networkDestinationIsRejected() {
    let result = DropPlanner.plan(
        DropPlanningContext(
            candidates: [candidate()],
            destination: destination(locationKind: .network)
        )
    )
    #expect(result == .reject(.networkDestinationUnsupported))
}

@Test("read-only destination is rejected")
func readOnlyDestinationIsRejected() {
    let result = DropPlanner.plan(
        DropPlanningContext(
            candidates: [candidate()],
            destination: destination(isWritable: false)
        )
    )
    #expect(result == .reject(.destinationReadOnly))
}

@Test(
    "unsafe or unknown destination commit support is rejected",
    arguments: [false, nil] as [Bool?]
)
func unsafeDestinationCommitIsRejected(supportsSafeDestinationCommit: Bool?) {
    let result = DropPlanner.plan(
        DropPlanningContext(
            candidates: [candidate()],
            destination: destination(
                supportsSafeDestinationCommit: supportsSafeDestinationCommit
            )
        )
    )
    #expect(result == .reject(.destinationUnavailable))
}

@Test("a source marked as colliding is rejected")
func collisionIsRejected() {
    let item = candidate()
    let result = DropPlanner.plan(
        DropPlanningContext(
            candidates: [item],
            destination: destination(),
            collidingSourceURLs: [item.url.standardizedFileURL]
        )
    )
    #expect(result == .reject(.collision))
}

@Test("all items already in destination produce no operation")
func allSameDirectoryIsNoOperation() {
    let destinationURL = URL(fileURLWithPath: "/tmp/SchneeGlassDestination", isDirectory: true)
    let result = DropPlanner.plan(
        DropPlanningContext(
            candidates: [
                candidate("/tmp/SchneeGlassDestination/a.txt"),
                candidate("/tmp/SchneeGlassDestination/b.txt"),
            ],
            destination: destination(url: destinationURL)
        )
    )
    #expect(result == .noOperation)
}

@Test("mixed same-directory and external items reject the full batch")
func mixedSameDirectoryIsRejected() {
    let destinationURL = URL(fileURLWithPath: "/tmp/SchneeGlassDestination", isDirectory: true)
    let result = DropPlanner.plan(
        DropPlanningContext(
            candidates: [
                candidate("/tmp/SchneeGlassDestination/a.txt"),
                candidate("/tmp/Elsewhere/b.txt"),
            ],
            destination: destination(url: destinationURL)
        )
    )
    #expect(result == .reject(.containsSameDirectoryItem))
}

@Test(
    "unavailable sources are rejected",
    arguments: [
        (DropCandidateAvailability.sourceUnavailable, DropRejection.sourceUnavailable),
        (DropCandidateAvailability.cloudPlaceholderUnavailable, DropRejection.cloudPlaceholderUnavailable),
    ]
)
func unavailableSourcesAreRejected(
    availability: DropCandidateAvailability,
    expected: DropRejection
) {
    let item = candidate()
    let result = DropPlanner.plan(
        DropPlanningContext(
            candidates: [item],
            destination: destination(),
            availabilityBySourceURL: [item.url.standardizedFileURL: availability]
        )
    )
    #expect(result == .reject(expected))
}

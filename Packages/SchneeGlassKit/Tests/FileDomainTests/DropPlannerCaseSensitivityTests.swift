import Foundation
@testable import FileDomain
import SchneeGlassDomain
import Testing

private func caseSensitivityDestination(
    supportsCaseSensitiveNames: Bool?
) -> DestinationDescriptor {
    let url = URL(fileURLWithPath: "/tmp/DropDestination", isDirectory: true)
    return DestinationDescriptor(
        glassID: GlassID(),
        folderIdentity: FolderIdentity(resourceIdentifier: nil, standardizedURL: url),
        url: url,
        capabilities: StorageCapabilities(
            locationKind: .localFixed,
            isWritable: true,
            supportsCaseSensitiveNames: supportsCaseSensitiveNames
        )
    )
}

@Test
func caseInsensitiveDestinationRejectsBatchNamesDifferingOnlyByCase() {
    let candidates = [
        DropCandidate(
            url: URL(fileURLWithPath: "/tmp/A/Report.txt"),
            kind: .regular,
            size: 1
        ),
        DropCandidate(
            url: URL(fileURLWithPath: "/tmp/B/report.txt"),
            kind: .regular,
            size: 1
        ),
    ]

    let result = DropPlanner.plan(
        DropPlanningContext(
            candidates: candidates,
            destination: caseSensitivityDestination(supportsCaseSensitiveNames: false)
        )
    )

    #expect(result == .reject(.collision))
}

@Test
func unknownDestinationCaseSensitivityUsesConservativeCollisionPolicy() {
    let candidates = [
        DropCandidate(
            url: URL(fileURLWithPath: "/tmp/A/Café.txt"),
            kind: .regular,
            size: 1
        ),
        DropCandidate(
            url: URL(fileURLWithPath: "/tmp/B/Cafe\u{301}.txt"),
            kind: .regular,
            size: 1
        ),
    ]

    let result = DropPlanner.plan(
        DropPlanningContext(
            candidates: candidates,
            destination: caseSensitivityDestination(supportsCaseSensitiveNames: nil)
        )
    )

    #expect(result == .reject(.collision))
}

@Test
func caseSensitiveDestinationAllowsNamesDifferingOnlyByCase() throws {
    let candidates = [
        DropCandidate(
            url: URL(fileURLWithPath: "/tmp/A/Report.txt"),
            kind: .regular,
            size: 1
        ),
        DropCandidate(
            url: URL(fileURLWithPath: "/tmp/B/report.txt"),
            kind: .regular,
            size: 1
        ),
    ]

    let result = DropPlanner.plan(
        DropPlanningContext(
            candidates: candidates,
            destination: caseSensitivityDestination(supportsCaseSensitiveNames: true)
        )
    )

    guard case let .copy(plan) = result else {
        Issue.record("Expected copy plan on a case-sensitive destination")
        return
    }
    #expect(plan.items.map(\.destinationFilename) == ["Report.txt", "report.txt"])
}

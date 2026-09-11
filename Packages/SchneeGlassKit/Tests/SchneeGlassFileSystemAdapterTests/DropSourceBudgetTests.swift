import FileDomain
import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing
@testable import SchneeGlassFileSystemAdapter

private actor SourceBudgetDropInspector: DropFileSystemInspecting {
    private var destinationCalls = 0
    private var sourceCalls = 0
    private var existenceCalls = 0

    func inspectSource(at url: URL) async -> DropSourceInspection {
        sourceCalls += 1
        return DropSourceInspection(
            candidate: DropCandidate(url: url, kind: .regular, size: 1),
            availability: .available
        )
    }

    func destinationDescriptor(for access: FolderAccessHandle) async -> DestinationDescriptor? {
        destinationCalls += 1
        return DestinationDescriptor(
            glassID: access.glassID,
            folderIdentity: FolderIdentity(
                resourceIdentifier: "destination",
                standardizedURL: access.url
            ),
            url: access.url,
            capabilities: StorageCapabilities(
                locationKind: .localFixed,
                isWritable: true,
                supportsCaseSensitiveNames: true,
                supportsSafeDestinationCommit: true
            )
        )
    }

    func itemExists(at url: URL) async -> Bool {
        _ = url
        existenceCalls += 1
        return false
    }

    func counts() -> (destination: Int, source: Int, existence: Int) {
        (destinationCalls, sourceCalls, existenceCalls)
    }
}

private func sourceBudgetURLs(count: Int) -> [URL] {
    (0..<count).map { index in
        URL(fileURLWithPath: "/tmp/schneeglass-budget-source-\(index).txt")
    }
}

@Test
func authoritativePlanningAcceptsTheSourceBudgetBoundary() async throws {
    let inspector = SourceBudgetDropInspector()
    let planner = NativeDropPlanningAdapter(inspector: inspector)
    let destination = FolderAccessHandle(
        glassID: GlassID(),
        url: URL(fileURLWithPath: "/tmp/schneeglass-budget-destination", isDirectory: true)
    )

    let result = await planner.plan(
        sourceURLs: sourceBudgetURLs(count: NativeDropPlanningAdapter.maximumSourceItemsPerPlan),
        destinationAccess: destination
    )

    guard case let .copy(plan) = result else {
        Issue.record("Expected the maximum supported source count to remain plannable")
        return
    }

    #expect(plan.items.count == NativeDropPlanningAdapter.maximumSourceItemsPerPlan)
    let counts = await inspector.counts()
    #expect(counts.destination == 1)
    #expect(counts.source == NativeDropPlanningAdapter.maximumSourceItemsPerPlan)
    #expect(counts.existence == NativeDropPlanningAdapter.maximumSourceItemsPerPlan)
}

@Test
func oversizedAuthoritativePlanningRejectsBeforeAnyFilesystemInspection() async {
    let inspector = SourceBudgetDropInspector()
    let planner = NativeDropPlanningAdapter(inspector: inspector)
    let destination = FolderAccessHandle(
        glassID: GlassID(),
        url: URL(fileURLWithPath: "/tmp/schneeglass-budget-destination", isDirectory: true)
    )

    let result = await planner.plan(
        sourceURLs: sourceBudgetURLs(
            count: NativeDropPlanningAdapter.maximumSourceItemsPerPlan + 1
        ),
        destinationAccess: destination
    )

    #expect(
        result == .reject(
            .tooManyItems(maximum: NativeDropPlanningAdapter.maximumSourceItemsPerPlan)
        )
    )
    let counts = await inspector.counts()
    #expect(counts.destination == 0)
    #expect(counts.source == 0)
    #expect(counts.existence == 0)
}

@Test
func oversizedPreviewAlsoRejectsBeforeAnyFilesystemInspection() async {
    let inspector = SourceBudgetDropInspector()
    let planner = NativeDropPlanningAdapter(inspector: inspector)
    let destination = FolderAccessHandle(
        glassID: GlassID(),
        url: URL(fileURLWithPath: "/tmp/schneeglass-budget-destination", isDirectory: true)
    )

    let result = await planner.preview(
        sourceURLs: sourceBudgetURLs(
            count: NativeDropPlanningAdapter.maximumSourceItemsPerPlan + 1
        ),
        destinationAccess: destination
    )

    #expect(
        result == .reject(
            .tooManyItems(maximum: NativeDropPlanningAdapter.maximumSourceItemsPerPlan)
        )
    )
    let counts = await inspector.counts()
    #expect(counts.destination == 0)
    #expect(counts.source == 0)
    #expect(counts.existence == 0)
}

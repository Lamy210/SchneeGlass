import FileDomain
import Foundation
import SchneeGlassApplication

/// Production Drop-planning facade that keeps hover validation lease-free while reflecting the
/// current shared source-descriptor budget before presenting a Drop as executable.
///
/// The preview result is advisory only: capacity can still change before authoritative planning,
/// where `NativeDropPlanningAdapter.plan` remains the final admission point and performs the actual
/// source pinning. This facade never acquires source descriptors during hover.
public actor PinnedDropPlanningFacade: DropPlanning {
    private let delegate: any DropPlanning
    private let sourceLeases: SourceFileLeaseRegistry
    private let maximumActiveLeases: Int

    init(
        delegate: any DropPlanning,
        sourceLeases: SourceFileLeaseRegistry,
        maximumActiveLeases: Int = SourceFileLeaseRegistry.defaultMaximumActiveLeases
    ) {
        precondition(maximumActiveLeases > 0, "Source lease capacity must be positive")
        self.delegate = delegate
        self.sourceLeases = sourceLeases
        self.maximumActiveLeases = maximumActiveLeases
    }

    public func preview(
        sourceURLs: [URL],
        destinationAccess: FolderAccessHandle
    ) async -> DropPlan {
        let result = await delegate.preview(
            sourceURLs: sourceURLs,
            destinationAccess: destinationAccess
        )

        guard case let .copy(plan) = result else {
            return result
        }

        let activeLeaseCount = await sourceLeases.activeLeaseCount()
        let available = max(0, maximumActiveLeases - activeLeaseCount)

        guard plan.items.count <= available else {
            return .reject(.sourceCapacityReached(maximum: maximumActiveLeases))
        }

        return result
    }

    public func plan(
        sourceURLs: [URL],
        destinationAccess: FolderAccessHandle
    ) async -> DropPlan {
        await delegate.plan(
            sourceURLs: sourceURLs,
            destinationAccess: destinationAccess
        )
    }
}

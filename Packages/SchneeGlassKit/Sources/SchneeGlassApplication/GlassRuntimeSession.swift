import Foundation
import FileDomain
import SchneeGlassDomain

public enum GlassRuntimeSessionError: Error, Hashable, Sendable {
    case alreadyStarted
    case stopped
}

public actor GlassRuntimeSession {
    private enum Lifecycle: Equatable {
        case idle
        case running
        case stopping
        case stopped
    }

    public let configuration: GlassConfiguration

    private let access: FolderAccessHandle
    private let eventSubscription: FileEventSubscription
    private let eventStreaming: any FileEventStreaming
    private let snapshotReader: any FolderSnapshotReading
    private let accessController: any FolderAccessControlling
    private let dropPlanning: any DropPlanning
    private let fileCopying: any FileCopying
    private let initialSnapshot: FolderSnapshot

    private var generation: UInt64
    private var lifecycle: Lifecycle = .idle
    private var stateContinuation: AsyncStream<GlassContentState>.Continuation?
    private var eventTask: Task<Void, Never>?
    private var activeCopyTask: Task<CopyBatchResult, Never>?
    private var pendingAuthoritativePlans: [UUID: CopyBatchPlan] = [:]
    private var stopWaiters: [CheckedContinuation<Void, Never>] = []
    private var accessReleased = false
    private var subscriptionStopped = false

    public init(
        seed: CreatedGlassRuntimeSeed,
        eventStreaming: any FileEventStreaming,
        snapshotReader: any FolderSnapshotReading,
        accessController: any FolderAccessControlling,
        dropPlanning: any DropPlanning,
        fileCopying: any FileCopying
    ) {
        self.configuration = seed.configuration
        self.access = seed.access
        self.eventSubscription = seed.eventSubscription
        self.eventStreaming = eventStreaming
        self.snapshotReader = snapshotReader
        self.accessController = accessController
        self.dropPlanning = dropPlanning
        self.fileCopying = fileCopying
        self.initialSnapshot = seed.snapshot
        self.generation = seed.snapshot.generation
    }

    public func start() throws -> AsyncStream<GlassContentState> {
        switch lifecycle {
        case .idle:
            break
        case .running:
            throw GlassRuntimeSessionError.alreadyStarted
        case .stopping, .stopped:
            throw GlassRuntimeSessionError.stopped
        }

        let pair = AsyncStream<GlassContentState>.makeStream()
        stateContinuation = pair.continuation
        lifecycle = .running
        pair.continuation.yield(Self.contentState(for: initialSnapshot))
        pair.continuation.onTermination = { [weak self] _ in
            guard let self else {
                return
            }
            Task {
                await self.stop()
            }
        }

        eventTask = Task { [weak self] in
            await self?.consumeEvents()
        }

        return pair.stream
    }

    public func previewDrop(sourceURLs: [URL]) async -> DropPlan {
        guard lifecycle == .running else {
            return .reject(.destinationUnavailable)
        }

        let plan = await dropPlanning.preview(
            sourceURLs: sourceURLs,
            destinationAccess: access
        )

        guard lifecycle == .running else {
            return .reject(.destinationUnavailable)
        }
        return plan
    }

    public func planDrop(sourceURLs: [URL]) async -> DropPlan {
        guard lifecycle == .running else {
            return .reject(.destinationUnavailable)
        }

        let plan = await dropPlanning.plan(
            sourceURLs: sourceURLs,
            destinationAccess: access
        )

        guard lifecycle == .running else {
            if case let .copy(copyPlan) = plan {
                await dropPlanning.abandon(
                    AuthorizedCopyBatchRequest(
                        plan: copyPlan,
                        destinationAccess: access
                    )
                )
            }
            return .reject(.destinationUnavailable)
        }

        if case let .copy(copyPlan) = plan {
            pendingAuthoritativePlans[copyPlan.batchID] = copyPlan
        }
        return plan
    }

    /// Releases planning-time authority for a copy plan that the presentation layer no longer
    /// intends to execute. The operation is idempotent; stale or already-consumed plans are ignored.
    public func abandonCopyPlan(_ plan: CopyBatchPlan) async {
        await abandonPendingPlanIfOwned(plan)
    }

    public func executeCopy(_ plan: CopyBatchPlan) async throws -> CopyBatchResult {
        try await executeCopy(plan, onProgress: { _ in })
    }

    public func executeCopy(
        _ plan: CopyBatchPlan,
        onProgress: @escaping CopyProgressHandler
    ) async throws -> CopyBatchResult {
        guard lifecycle == .running else {
            await abandonPendingPlanIfOwned(plan)
            throw GlassCopyExecutionError.sessionNotRunning
        }
        guard activeCopyTask == nil else {
            await abandonPendingPlanIfOwned(plan)
            throw GlassCopyExecutionError.copyInProgress
        }
        guard plan.destination.glassID == access.glassID,
              plan.destination.url.standardizedFileURL == access.url.standardizedFileURL
        else {
            await abandonPendingPlanIfOwned(plan)
            throw GlassCopyExecutionError.destinationMismatch
        }

        transferPendingPlanIfOwned(plan)

        let request = AuthorizedCopyBatchRequest(
            plan: plan,
            destinationAccess: access
        )
        let fileCopying = self.fileCopying
        let task = Task {
            await fileCopying.copy(request, onProgress: onProgress)
        }
        activeCopyTask = task

        let result = await task.value
        activeCopyTask = nil
        return result
    }

    public func stop() async {
        switch lifecycle {
        case .stopped:
            return
        case .stopping:
            // Every caller of this async API gets the same completion guarantee. A second stop must
            // join the in-progress shutdown instead of returning while security-scoped access or
            // copy/planning authority is still being released by the first caller.
            await withCheckedContinuation { continuation in
                stopWaiters.append(continuation)
            }
            return
        case .idle, .running:
            lifecycle = .stopping
        }

        let task = eventTask
        task?.cancel()
        stateContinuation?.finish()
        stateContinuation = nil

        await stopSubscriptionIfNeeded()

        if let task {
            await task.value
            eventTask = nil
        }

        await abandonAllPendingPlans()
        await waitForActiveCopyIfNeeded()
        await releaseAccessIfNeeded()
        finishStop()
    }

    private func consumeEvents() async {
        for await event in eventSubscription.events {
            if Task.isCancelled || lifecycle != .running {
                return
            }

            switch event {
            case .rootChanged:
                stateContinuation?.yield(.unavailable(.sourceMissing))
                await stopFromEventLoop()
                return

            case .changed, .requiresFullRescan:
                generation &+= 1
                do {
                    let snapshot = try await snapshotReader.snapshot(
                        for: access,
                        generation: generation
                    )
                    guard !Task.isCancelled, lifecycle == .running else {
                        return
                    }
                    stateContinuation?.yield(Self.contentState(for: snapshot))
                } catch let error as FolderSnapshotReadError {
                    guard !Task.isCancelled, lifecycle == .running else {
                        return
                    }

                    switch error {
                    case .rootIdentityMismatch:
                        stateContinuation?.yield(.unavailable(.replacementDetected))
                        await stopFromEventLoop()
                        return
                    }
                } catch {
                    guard !Task.isCancelled, lifecycle == .running else {
                        return
                    }
                    stateContinuation?.yield(.failed(.enumerationFailed))
                }
            }
        }

        if !Task.isCancelled, lifecycle == .running {
            stateContinuation?.yield(.failed(.unexpected))
            await stopFromEventLoop()
        }
    }

    private func stopFromEventLoop() async {
        guard lifecycle == .running else {
            return
        }
        lifecycle = .stopping

        stateContinuation?.finish()
        stateContinuation = nil
        await stopSubscriptionIfNeeded()
        await abandonAllPendingPlans()
        await waitForActiveCopyIfNeeded()
        await releaseAccessIfNeeded()

        eventTask = nil
        finishStop()
    }

    private func finishStop() {
        lifecycle = .stopped
        let waiters = stopWaiters
        stopWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters {
            waiter.resume()
        }
    }

    private func transferPendingPlanIfOwned(_ plan: CopyBatchPlan) {
        guard pendingAuthoritativePlans[plan.batchID] == plan else {
            return
        }
        pendingAuthoritativePlans.removeValue(forKey: plan.batchID)
    }

    private func abandonPendingPlanIfOwned(_ plan: CopyBatchPlan) async {
        guard pendingAuthoritativePlans[plan.batchID] == plan else {
            return
        }
        pendingAuthoritativePlans.removeValue(forKey: plan.batchID)
        await dropPlanning.abandon(
            AuthorizedCopyBatchRequest(
                plan: plan,
                destinationAccess: access
            )
        )
    }

    private func abandonAllPendingPlans() async {
        guard !pendingAuthoritativePlans.isEmpty else {
            return
        }

        let plans = Array(pendingAuthoritativePlans.values)
        pendingAuthoritativePlans.removeAll(keepingCapacity: false)
        for plan in plans {
            await dropPlanning.abandon(
                AuthorizedCopyBatchRequest(
                    plan: plan,
                    destinationAccess: access
                )
            )
        }
    }

    private func waitForActiveCopyIfNeeded() async {
        if let activeCopyTask {
            _ = await activeCopyTask.value
            self.activeCopyTask = nil
        }
    }

    private func stopSubscriptionIfNeeded() async {
        guard !subscriptionStopped else {
            return
        }
        subscriptionStopped = true
        await eventStreaming.stop(subscriptionID: eventSubscription.id)
    }

    private func releaseAccessIfNeeded() async {
        guard !accessReleased else {
            return
        }
        accessReleased = true
        await accessController.release(handleID: access.id)
    }

    private static func contentState(for snapshot: FolderSnapshot) -> GlassContentState {
        snapshot.items.isEmpty ? .empty(snapshot) : .ready(snapshot)
    }
}

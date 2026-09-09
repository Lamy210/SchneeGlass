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
        return await dropPlanning.preview(
            sourceURLs: sourceURLs,
            destinationAccess: access
        )
    }

    public func planDrop(sourceURLs: [URL]) async -> DropPlan {
        guard lifecycle == .running else {
            return .reject(.destinationUnavailable)
        }
        return await dropPlanning.plan(
            sourceURLs: sourceURLs,
            destinationAccess: access
        )
    }

    public func executeCopy(_ plan: CopyBatchPlan) async throws -> CopyBatchResult {
        guard lifecycle == .running else {
            throw GlassCopyExecutionError.sessionNotRunning
        }
        guard activeCopyTask == nil else {
            throw GlassCopyExecutionError.copyInProgress
        }
        guard plan.destination.glassID == access.glassID,
              plan.destination.url.standardizedFileURL == access.url.standardizedFileURL
        else {
            throw GlassCopyExecutionError.destinationMismatch
        }

        let request = AuthorizedCopyBatchRequest(
            plan: plan,
            destinationAccess: access
        )
        let fileCopying = self.fileCopying
        let task = Task {
            await fileCopying.copy(request)
        }
        activeCopyTask = task

        let result = await task.value
        activeCopyTask = nil
        return result
    }

    public func stop() async {
        switch lifecycle {
        case .stopped, .stopping:
            return
        case .idle, .running:
            lifecycle = .stopping
        }

        eventTask?.cancel()
        eventTask = nil
        stateContinuation?.finish()
        stateContinuation = nil

        await stopSubscriptionIfNeeded()

        if let activeCopyTask {
            _ = await activeCopyTask.value
            self.activeCopyTask = nil
        }

        await releaseAccessIfNeeded()
        lifecycle = .stopped
    }

    private func consumeEvents() async {
        for await event in eventSubscription.events {
            if Task.isCancelled || lifecycle != .running {
                return
            }

            switch event {
            case .rootChanged:
                stateContinuation?.yield(.unavailable(.sourceMissing))
                await stop()
                return

            case .changed, .requiresFullRescan:
                generation &+= 1
                do {
                    let snapshot = try await snapshotReader.snapshot(
                        for: access,
                        generation: generation
                    )
                    stateContinuation?.yield(Self.contentState(for: snapshot))
                } catch {
                    stateContinuation?.yield(.failed(.enumerationFailed))
                }
            }
        }

        if !Task.isCancelled, lifecycle == .running {
            await stop()
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

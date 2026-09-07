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
        case stopped
    }

    public let configuration: GlassConfiguration

    private let access: FolderAccessHandle
    private let eventSubscription: FileEventSubscription
    private let eventStreaming: any FileEventStreaming
    private let snapshotReader: any FolderSnapshotReading
    private let accessController: any FolderAccessControlling
    private let initialSnapshot: FolderSnapshot

    private var generation: UInt64
    private var lifecycle: Lifecycle = .idle
    private var stateContinuation: AsyncStream<GlassContentState>.Continuation?
    private var eventTask: Task<Void, Never>?
    private var accessReleased = false
    private var subscriptionStopped = false

    public init(
        seed: CreatedGlassRuntimeSeed,
        eventStreaming: any FileEventStreaming,
        snapshotReader: any FolderSnapshotReading,
        accessController: any FolderAccessControlling
    ) {
        self.configuration = seed.configuration
        self.access = seed.access
        self.eventSubscription = seed.eventSubscription
        self.eventStreaming = eventStreaming
        self.snapshotReader = snapshotReader
        self.accessController = accessController
        self.initialSnapshot = seed.snapshot
        self.generation = seed.snapshot.generation
    }

    public func start() throws -> AsyncStream<GlassContentState> {
        switch lifecycle {
        case .idle:
            break
        case .running:
            throw GlassRuntimeSessionError.alreadyStarted
        case .stopped:
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

    public func stop() async {
        guard lifecycle != .stopped else {
            return
        }

        lifecycle = .stopped
        eventTask?.cancel()
        eventTask = nil
        stateContinuation?.finish()
        stateContinuation = nil
        await stopSubscriptionIfNeeded()
        await releaseAccessIfNeeded()
    }

    private func consumeEvents() async {
        for await event in eventSubscription.events {
            if Task.isCancelled || lifecycle != .running {
                return
            }

            switch event {
            case .rootChanged:
                stateContinuation?.yield(.unavailable(.sourceMissing))
                await finishAfterEventStreamTermination()
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
            await finishAfterEventStreamTermination()
        }
    }

    private func finishAfterEventStreamTermination() async {
        guard lifecycle != .stopped else {
            return
        }
        lifecycle = .stopped
        eventTask = nil
        stateContinuation?.finish()
        stateContinuation = nil
        await stopSubscriptionIfNeeded()
        await releaseAccessIfNeeded()
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

import Foundation
import FileDomain
import SchneeGlassDomain

public enum GlassRuntimeSessionError: Error, Hashable, Sendable {
    case alreadyStarted
    case stopped
}

public actor GlassRuntimeSession {
    private enum Lifecycle {
        case idle
        case running
        case stopped
    }

    public let configuration: GlassConfiguration

    private let access: FolderAccessHandle
    private let events: AsyncStream<FileEvent>
    private let snapshotReader: any FolderSnapshotReading
    private let accessController: any FolderAccessControlling

    private var generation: UInt64
    private var lifecycle: Lifecycle = .idle
    private var stateContinuation: AsyncStream<GlassContentState>.Continuation?
    private var eventTask: Task<Void, Never>?
    private var accessReleased = false

    public init(
        seed: CreatedGlassRuntimeSeed,
        snapshotReader: any FolderSnapshotReading,
        accessController: any FolderAccessControlling
    ) {
        self.configuration = seed.configuration
        self.access = seed.access
        self.events = seed.events
        self.snapshotReader = snapshotReader
        self.accessController = accessController
        self.generation = seed.snapshot.generation
        self.initialSnapshot = seed.snapshot
    }

    private let initialSnapshot: FolderSnapshot

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
        await releaseAccessIfNeeded()
    }

    private func consumeEvents() async {
        for await event in events {
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
        await releaseAccessIfNeeded()
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

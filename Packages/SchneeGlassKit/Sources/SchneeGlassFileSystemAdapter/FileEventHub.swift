import CoreServices
import Foundation
import SchneeGlassApplication

public enum FileEventHubError: Error, Hashable, Sendable {
    case streamCreationFailed
    case streamStartFailed
}

final class FSEventCallbackBox {
    let continuation: AsyncStream<FileEvent>.Continuation

    init(continuation: AsyncStream<FileEvent>.Continuation) {
        self.continuation = continuation
    }
}

enum FSEventCallbackContextOwnership {
    static func retain(_ info: UnsafeRawPointer?) -> UnsafeRawPointer? {
        guard let info else {
            return nil
        }
        _ = Unmanaged<FSEventCallbackBox>.fromOpaque(info).retain()
        return info
    }

    static func release(_ info: UnsafeRawPointer?) {
        guard let info else {
            return
        }
        Unmanaged<FSEventCallbackBox>.fromOpaque(info).release()
    }
}

private let schneeGlassFSEventCallback: FSEventStreamCallback = {
    _, callbackInfo, numberOfEvents, _, eventFlags, _ in
    guard let callbackInfo, numberOfEvents > 0 else {
        return
    }

    let box = Unmanaged<FSEventCallbackBox>
        .fromOpaque(callbackInfo)
        .takeUnretainedValue()

    var strongestEvent: FileEvent = .changed
    for index in 0..<numberOfEvents {
        let event = FileEventFlagMapper.map(eventFlags[index])
        if event == .rootChanged {
            strongestEvent = .rootChanged
            break
        }
        if event == .requiresFullRescan {
            strongestEvent = .requiresFullRescan
        }
    }

    box.continuation.yield(strongestEvent)
}

enum FileEventFlagMapper {
    static func map(_ flags: FSEventStreamEventFlags) -> FileEvent {
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged) != 0 {
            return .rootChanged
        }

        let requiresFullRescan =
            flags & FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs) != 0
            || flags & FSEventStreamEventFlags(kFSEventStreamEventFlagKernelDropped) != 0
            || flags & FSEventStreamEventFlags(kFSEventStreamEventFlagUserDropped) != 0

        if requiresFullRescan {
            return .requiresFullRescan
        }

        return .changed
    }
}

public actor FileEventHub: FileEventStreaming {
    public static let defaultLatency: TimeInterval = 0.2

    private struct Session {
        let stream: FSEventStreamRef
        let continuation: AsyncStream<FileEvent>.Continuation
    }

    private let callbackQueue: DispatchQueue
    private let latency: TimeInterval
    private var sessions: [UUID: Session] = [:]

    public init(latency: TimeInterval = FileEventHub.defaultLatency) {
        self.latency = latency
        self.callbackQueue = DispatchQueue(
            label: "dev.schneeglass.filesystem-events",
            qos: .utility
        )
    }

    public func subscribe(for access: FolderAccessHandle) async throws -> FileEventSubscription {
        let subscriptionID = UUID()
        let pair = AsyncStream<FileEvent>.makeStream()
        let callbackBox = FSEventCallbackBox(continuation: pair.continuation)
        let callbackInfo = Unmanaged.passUnretained(callbackBox).toOpaque()

        var context = FSEventStreamContext(
            version: 0,
            info: callbackInfo,
            retain: { info in
                FSEventCallbackContextOwnership.retain(info)
            },
            release: { info in
                FSEventCallbackContextOwnership.release(info)
            },
            copyDescription: nil
        )

        let creationFlags =
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagWatchRoot)
            | FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents)
            | FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes)

        let createdStream = withExtendedLifetime(callbackBox) {
            FSEventStreamCreate(
                kCFAllocatorDefault,
                schneeGlassFSEventCallback,
                &context,
                [access.url.path] as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                latency,
                creationFlags
            )
        }
        guard let stream = createdStream else {
            throw FileEventHubError.streamCreationFailed
        }

        FSEventStreamSetDispatchQueue(stream, callbackQueue)

        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            throw FileEventHubError.streamStartFailed
        }

        sessions[subscriptionID] = Session(
            stream: stream,
            continuation: pair.continuation
        )

        pair.continuation.onTermination = { [weak self] _ in
            guard let self else {
                return
            }
            Task {
                await self.stop(subscriptionID: subscriptionID)
            }
        }

        return FileEventSubscription(
            id: subscriptionID,
            events: pair.stream
        )
    }

    public func stop(subscriptionID: UUID) {
        stopSession(subscriptionID: subscriptionID)
    }

    public func stopAll() {
        let activeSubscriptionIDs = Array(sessions.keys)
        for subscriptionID in activeSubscriptionIDs {
            stopSession(subscriptionID: subscriptionID)
        }
    }

    private func stopSession(subscriptionID: UUID) {
        guard let session = sessions.removeValue(forKey: subscriptionID) else {
            return
        }

        FSEventStreamStop(session.stream)
        FSEventStreamInvalidate(session.stream)
        // The stream owns its callback context through FSEventStreamContext retain/release callbacks.
        // Releasing the stream therefore releases the box only when CoreServices is finished with the
        // context, rather than guessing callback lifetime from the actor's stop timing.
        FSEventStreamRelease(session.stream)
        session.continuation.finish()
    }
}

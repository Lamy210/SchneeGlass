import CoreServices
import Foundation
import SchneeGlassApplication

public enum FileEventHubError: Error, Hashable, Sendable {
    case streamCreationFailed
    case streamStartFailed
}

private final class FSEventCallbackBox {
    let continuation: AsyncStream<FileEvent>.Continuation

    init(continuation: AsyncStream<FileEvent>.Continuation) {
        self.continuation = continuation
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
        let callbackInfo: UnsafeMutableRawPointer
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
        let retainedBox = Unmanaged.passRetained(callbackBox)
        let callbackInfo = retainedBox.toOpaque()

        var context = FSEventStreamContext(
            version: 0,
            info: callbackInfo,
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let creationFlags =
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagWatchRoot)
            | FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents)
            | FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes)

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            schneeGlassFSEventCallback,
            &context,
            [access.url.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            creationFlags
        ) else {
            retainedBox.release()
            throw FileEventHubError.streamCreationFailed
        }

        FSEventStreamSetDispatchQueue(stream, callbackQueue)

        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            retainedBox.release()
            throw FileEventHubError.streamStartFailed
        }

        sessions[subscriptionID] = Session(
            stream: stream,
            callbackInfo: callbackInfo,
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
        FSEventStreamRelease(session.stream)
        Unmanaged<FSEventCallbackBox>.fromOpaque(session.callbackInfo).release()
        session.continuation.finish()
    }
}

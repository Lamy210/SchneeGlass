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
    guard let callbackInfo else {
        return
    }

    let box = Unmanaged<FSEventCallbackBox>
        .fromOpaque(callbackInfo)
        .takeUnretainedValue()

    for index in 0..<numberOfEvents {
        box.continuation.yield(FileEventFlagMapper.map(eventFlags[index]))
    }
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

    public func events(for access: FolderAccessHandle) async throws -> AsyncStream<FileEvent> {
        let sessionID = UUID()
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

        sessions[sessionID] = Session(
            stream: stream,
            callbackInfo: callbackInfo,
            continuation: pair.continuation
        )

        pair.continuation.onTermination = { [weak self] _ in
            guard let self else {
                return
            }
            Task {
                await self.stop(sessionID: sessionID)
            }
        }

        return pair.stream
    }

    public func stopAll() {
        let activeSessionIDs = Array(sessions.keys)
        for sessionID in activeSessionIDs {
            stop(sessionID: sessionID)
        }
    }

    private func stop(sessionID: UUID) {
        guard let session = sessions.removeValue(forKey: sessionID) else {
            return
        }

        FSEventStreamStop(session.stream)
        FSEventStreamInvalidate(session.stream)
        FSEventStreamRelease(session.stream)
        Unmanaged<FSEventCallbackBox>.fromOpaque(session.callbackInfo).release()
        session.continuation.finish()
    }
}

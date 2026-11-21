import Foundation
import Testing

@testable import SchneeGlassPresentation

@MainActor
private final class SharedShutdownStopProbe {
  private(set) var stopCalls = 0
  private var finished = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func stop() async {
    if finished {
      return
    }
    stopCalls += 1
    await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }

  func finishStop() {
    finished = true
    let pending = waiters
    waiters.removeAll()
    for waiter in pending {
      waiter.resume()
    }
  }
}

@MainActor
private final class SharedShutdownRegistry {
  var sessions: [Int: SharedShutdownStopProbe] = [:]

  func shutdown() async {
    let active = Array(sessions)
    for (key, session) in active {
      await WorkspaceSessionRetirement.stopAndRemove(
        stop: { await session.stop() },
        isCurrent: { self.sessions[key] === session },
        remove: { self.sessions[key] = nil }
      )
    }
  }
}

@MainActor
private func waitForStopCalls(_ probe: SharedShutdownStopProbe, count: Int) async -> Bool {
  for _ in 0..<2_000 {
    if probe.stopCalls >= count {
      return true
    }
    await Task.yield()
  }
  return false
}

@Test
@MainActor
func overlappingShutdownKeepsSessionRegisteredUntilBothStopsJoin() async {
  let registry = SharedShutdownRegistry()
  let session = SharedShutdownStopProbe()
  registry.sessions[1] = session
  var firstDone = false
  var secondDone = false
  let first = Task {
    await registry.shutdown()
    firstDone = true
  }

  let firstEntered = await waitForStopCalls(session, count: 1)
  if !firstEntered {
    session.finishStop()
    await first.value
    Issue.record("First shutdown never entered session cleanup")
    return
  }
  #expect(registry.sessions[1] === session)

  let second = Task {
    await registry.shutdown()
    secondDone = true
  }
  let secondEntered = await waitForStopCalls(session, count: 2)
  #expect(secondEntered)
  #expect(registry.sessions[1] === session)
  #expect(!firstDone)
  #expect(!secondDone)

  session.finishStop()
  await first.value
  await second.value
  #expect(firstDone && secondDone)
  #expect(registry.sessions.isEmpty)
}

@Test
@MainActor
func sessionRetirementDoesNotRemoveReplacedSessionDuringShutdown() async {
  let registry = SharedShutdownRegistry()
  let old = SharedShutdownStopProbe()
  let replacement = SharedShutdownStopProbe()
  registry.sessions[1] = old

  let first = Task { await registry.shutdown() }
  let entered = await waitForStopCalls(old, count: 1)
  if !entered {
    old.finishStop()
    await first.value
    Issue.record("Old session cleanup never started")
    return
  }
  registry.sessions[1] = replacement
  old.finishStop()
  await first.value

  #expect(registry.sessions[1] === replacement)
  let second = Task { await registry.shutdown() }
  let newEntered = await waitForStopCalls(replacement, count: 1)
  #expect(newEntered)
  replacement.finishStop()
  await second.value
  #expect(registry.sessions.isEmpty)
}

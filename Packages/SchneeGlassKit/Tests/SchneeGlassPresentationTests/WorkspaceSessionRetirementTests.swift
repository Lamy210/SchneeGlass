import Foundation
import Testing

@testable import SchneeGlassPresentation

@MainActor
private final class BlockingRetirementSession {
  private(set) var stopStarted = false
  private var unblock: CheckedContinuation<Void, Never>?

  func stop() async {
    stopStarted = true
    await withCheckedContinuation { continuation in
      unblock = continuation
    }
  }

  func finishStop() {
    unblock?.resume()
    unblock = nil
  }
}

@MainActor
private final class RetirementSessionRegistry {
  var current: BlockingRetirementSession?

  func retire(_ session: BlockingRetirementSession) async {
    await WorkspaceSessionRetirement.stopAndRemove(
      stop: { await session.stop() },
      isCurrent: { self.current === session },
      remove: { self.current = nil }
    )
  }
}

@MainActor
private func waitForRetirementStart(_ session: BlockingRetirementSession) async -> Bool {
  for _ in 0..<2_000 {
    if session.stopStarted {
      return true
    }
    await Task.yield()
  }
  return false
}

@Test
@MainActor
func retiringWorkspaceSessionRemainsDiscoverableUntilStopCompletes() async {
  let registry = RetirementSessionRegistry()
  let session = BlockingRetirementSession()
  registry.current = session

  let stopping = Task {
    await registry.retire(session)
  }
  let started = await waitForRetirementStart(session)
  #expect(started)
  #expect(registry.current === session)
  // A concurrent shutdown snapshots the same still-active session and can join stop().
  let shutdownVisibleSession = registry.current
  #expect(shutdownVisibleSession === session)

  session.finishStop()
  await stopping.value
  #expect(registry.current == nil)
}

@Test
@MainActor
func delayedWorkspaceRetirementCannotEraseReplacementSession() async {
  let registry = RetirementSessionRegistry()
  let old = BlockingRetirementSession()
  let replacement = BlockingRetirementSession()
  registry.current = old

  let stopping = Task {
    await registry.retire(old)
  }
  let started = await waitForRetirementStart(old)
  #expect(started)
  #expect(registry.current === old)

  // Even if another path swaps the session while the old stop is suspended,
  // completion must not clear the replacement.
  registry.current = replacement
  old.finishStop()
  await stopping.value
  #expect(registry.current === replacement)
}

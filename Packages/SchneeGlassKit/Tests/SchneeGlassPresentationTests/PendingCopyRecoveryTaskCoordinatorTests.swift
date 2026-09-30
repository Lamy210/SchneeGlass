import Testing

@testable import SchneeGlassPresentation

@Test
@MainActor
func pendingRecoveryCoordinatorCancellationWaitsForCleanup() async {
  let coordinator = PendingCopyRecoveryTaskCoordinator()
  let started = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
  var cleanupFinished = false

  let runTask = Task { @MainActor in
    await coordinator.run(ifBusy: false) {
      started.continuation.yield(())
      do {
        try await Task.sleep(nanoseconds: 10_000_000_000)
      } catch is CancellationError {
        cleanupFinished = true
      } catch {
        Issue.record("Unexpected error: \(error)")
      }
      return true
    }
  }

  var iterator = started.stream.makeAsyncIterator()
  _ = await iterator.next()
  #expect(coordinator.isRunning)

  await coordinator.cancelAndWait()

  #expect(cleanupFinished)
  #expect(!coordinator.isRunning)
  #expect(await runTask.value)
}

@Test
@MainActor
func pendingRecoveryCoordinatorCanStartReplacementImmediatelyAfterCancellationWait() async {
  let coordinator = PendingCopyRecoveryTaskCoordinator()
  let started = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))

  let firstTask = Task { @MainActor in
    await coordinator.run(ifBusy: "busy") {
      started.continuation.yield(())
      do {
        try await Task.sleep(nanoseconds: 10_000_000_000)
      } catch is CancellationError {
        return "cancelled"
      } catch {
        Issue.record("Unexpected error: \(error)")
      }
      return "first"
    }
  }

  var iterator = started.stream.makeAsyncIterator()
  _ = await iterator.next()

  await coordinator.cancelAndWait()

  #expect(!coordinator.isRunning)
  let replacement = await coordinator.run(ifBusy: "busy") {
    "replacement"
  }

  #expect(replacement == "replacement")
  #expect(await firstTask.value == "cancelled")
  #expect(!coordinator.isRunning)
}

@Test
@MainActor
func concurrentPendingRecoveryOperationReturnsBusyFallback() async {
  let coordinator = PendingCopyRecoveryTaskCoordinator()
  let started = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
  let release = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))

  let firstTask = Task { @MainActor in
    await coordinator.run(ifBusy: "busy") {
      started.continuation.yield(())
      var iterator = release.stream.makeAsyncIterator()
      _ = await iterator.next()
      return "first"
    }
  }

  var startedIterator = started.stream.makeAsyncIterator()
  _ = await startedIterator.next()

  let second = await coordinator.run(ifBusy: "busy") {
    "second"
  }

  #expect(second == "busy")
  release.continuation.yield(())
  #expect(await firstTask.value == "first")
}

import Testing

@testable import SchneeGlassPresentation

@Test
@MainActor
func initialRestoreCoordinatorCancellationWaitsForOperationCleanup() async {
  let coordinator = WorkspaceInitialRestoreTaskCoordinator()
  let started = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
  var didFinishCancellationCleanup = false

  let runTask = Task { @MainActor in
    await coordinator.run {
      started.continuation.yield(())
      do {
        try await Task.sleep(nanoseconds: 10_000_000_000)
      } catch is CancellationError {
        await Task.yield()
        didFinishCancellationCleanup = true
      } catch {
        Issue.record("Unexpected error: \(error)")
      }
    }
  }

  var iterator = started.stream.makeAsyncIterator()
  _ = await iterator.next()
  #expect(coordinator.isRunning)

  await coordinator.cancelAndWait()

  #expect(didFinishCancellationCleanup)
  await runTask.value
  #expect(!coordinator.isRunning)
}

@Test
@MainActor
func cancellingInitialRestoreCallerCancelsTrackedOperation() async {
  let coordinator = WorkspaceInitialRestoreTaskCoordinator()
  let started = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
  var didObserveCancellation = false

  let runTask = Task { @MainActor in
    await coordinator.run {
      started.continuation.yield(())
      do {
        try await Task.sleep(nanoseconds: 10_000_000_000)
      } catch is CancellationError {
        didObserveCancellation = true
      } catch {
        Issue.record("Unexpected error: \(error)")
      }
    }
  }

  var iterator = started.stream.makeAsyncIterator()
  _ = await iterator.next()
  runTask.cancel()
  await runTask.value

  #expect(didObserveCancellation)
  #expect(!coordinator.isRunning)
}

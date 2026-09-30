import Testing

@testable import SchneeGlassPresentation

@Test
@MainActor
func configurationMutationCoordinatorCancellationWaitsForOperationCleanup() async {
  let coordinator = WorkspaceConfigurationMutationTaskCoordinator()
  let started = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
  var didFinishCancellationCleanup = false

  let runTask = Task { @MainActor in
    await coordinator.run(ifBusy: false) {
      started.continuation.yield(())
      do {
        try await Task.sleep(nanoseconds: 10_000_000_000)
      } catch is CancellationError {
        await Task.yield()
        didFinishCancellationCleanup = true
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

  #expect(didFinishCancellationCleanup)
  #expect(await runTask.value)
  #expect(!coordinator.isRunning)
}

@Test
@MainActor
func cancellingConfigurationMutationCallerCancelsTrackedOperation() async {
  let coordinator = WorkspaceConfigurationMutationTaskCoordinator()
  let started = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
  var didObserveCancellation = false

  let runTask = Task { @MainActor in
    await coordinator.run(ifBusy: false) {
      started.continuation.yield(())
      do {
        try await Task.sleep(nanoseconds: 10_000_000_000)
      } catch is CancellationError {
        didObserveCancellation = true
      } catch {
        Issue.record("Unexpected error: \(error)")
      }
      return true
    }
  }

  var iterator = started.stream.makeAsyncIterator()
  _ = await iterator.next()
  runTask.cancel()
  #expect(await runTask.value)

  #expect(didObserveCancellation)
  #expect(!coordinator.isRunning)
}

@Test
@MainActor
func concurrentConfigurationMutationReturnsBusyFallbackWithoutStartingSecondOperation() async {
  let coordinator = WorkspaceConfigurationMutationTaskCoordinator()
  let started = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
  let release = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
  var firstOperationCount = 0
  var secondOperationCount = 0

  let firstTask = Task { @MainActor in
    await coordinator.run(ifBusy: "busy") {
      firstOperationCount += 1
      started.continuation.yield(())
      var iterator = release.stream.makeAsyncIterator()
      _ = await iterator.next()
      return "first"
    }
  }

  var startedIterator = started.stream.makeAsyncIterator()
  _ = await startedIterator.next()

  let secondResult = await coordinator.run(ifBusy: "busy") {
    secondOperationCount += 1
    return "second"
  }

  #expect(secondResult == "busy")
  #expect(secondOperationCount == 0)

  release.continuation.yield(())
  #expect(await firstTask.value == "first")
  #expect(firstOperationCount == 1)
  #expect(!coordinator.isRunning)
}

@Test
@MainActor
func duplicateConfigurationMutationCancellationWaitersObserveSameCleanup() async {
  let coordinator = WorkspaceConfigurationMutationTaskCoordinator()
  let started = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
  var cleanupCount = 0

  let runTask = Task { @MainActor in
    await coordinator.run(ifBusy: false) {
      started.continuation.yield(())
      do {
        try await Task.sleep(nanoseconds: 10_000_000_000)
      } catch is CancellationError {
        await Task.yield()
        cleanupCount += 1
      } catch {
        Issue.record("Unexpected error: \(error)")
      }
      return true
    }
  }

  var iterator = started.stream.makeAsyncIterator()
  _ = await iterator.next()

  async let firstCancel: Void = coordinator.cancelAndWait()
  async let secondCancel: Void = coordinator.cancelAndWait()
  _ = await (firstCancel, secondCancel)

  #expect(cleanupCount == 1)
  #expect(await runTask.value)
  #expect(!coordinator.isRunning)
}

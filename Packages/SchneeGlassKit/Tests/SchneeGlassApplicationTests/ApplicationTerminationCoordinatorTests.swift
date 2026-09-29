import Testing

@testable import SchneeGlassApplication

@MainActor
private func waitForTerminationCondition(
  _ condition: () -> Bool
) async -> Bool {
  for _ in 0..<2_000 {
    if condition() {
      return true
    }
    await Task.yield()
  }
  return false
}

@Test
@MainActor
func terminationWithoutShutdownOperationTerminatesImmediately() {
  let coordinator = ApplicationTerminationCoordinator()
  var replies: [Bool] = []

  let decision = coordinator.requestTermination { replies.append($0) }

  #expect(decision == .terminateNow)
  #expect(replies.isEmpty)
}

@Test
@MainActor
func terminationWaitsForShutdownAndRepliesOnce() async {
  let gate = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
  var shutdownCount = 0
  var replies: [Bool] = []
  let coordinator = ApplicationTerminationCoordinator {
    shutdownCount += 1
    var iterator = gate.stream.makeAsyncIterator()
    _ = await iterator.next()
  }

  let firstDecision = coordinator.requestTermination { replies.append($0) }
  let repeatedDecision = coordinator.requestTermination { replies.append($0) }

  #expect(firstDecision == .terminateLater)
  #expect(repeatedDecision == .terminateLater)
  #expect(await waitForTerminationCondition { shutdownCount == 1 })
  #expect(replies.isEmpty)

  gate.continuation.yield(())
  gate.continuation.finish()

  #expect(await waitForTerminationCondition { replies == [true] })
  #expect(shutdownCount == 1)

  let afterApproval = coordinator.requestTermination { replies.append($0) }
  #expect(afterApproval == .terminateNow)
  #expect(shutdownCount == 1)
  #expect(replies == [true])
}

@Test
@MainActor
func configuredShutdownOperationIsUsedForTermination() async {
  var shutdownCount = 0
  var replies: [Bool] = []
  let coordinator = ApplicationTerminationCoordinator()

  coordinator.configure {
    shutdownCount += 1
  }

  #expect(
    coordinator.requestTermination { replies.append($0) }
      == .terminateLater
  )
  #expect(await waitForTerminationCondition { replies == [true] })
  #expect(shutdownCount == 1)
}

@Test
@MainActor
func reconfigurationDuringPendingTerminationDoesNotReplaceShutdown() async {
  let gate = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
  var firstShutdownCount = 0
  var replacementShutdownCount = 0
  var replies: [Bool] = []
  let coordinator = ApplicationTerminationCoordinator {
    firstShutdownCount += 1
    var iterator = gate.stream.makeAsyncIterator()
    _ = await iterator.next()
  }

  #expect(
    coordinator.requestTermination { replies.append($0) }
      == .terminateLater
  )
  #expect(await waitForTerminationCondition { firstShutdownCount == 1 })

  coordinator.configure {
    replacementShutdownCount += 1
  }

  gate.continuation.yield(())
  gate.continuation.finish()

  #expect(await waitForTerminationCondition { replies == [true] })
  #expect(firstShutdownCount == 1)
  #expect(replacementShutdownCount == 0)
}

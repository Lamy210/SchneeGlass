import Foundation

@MainActor
final class WorkspaceConfigurationMutationTaskCoordinator {
  private struct RunningTask {
    let cancel: () -> Void
    let wait: () async -> Void
  }

  private var runningTask: RunningTask?

  var isRunning: Bool {
    runningTask != nil
  }

  func run<Value: Sendable>(
    ifBusy fallback: Value,
    operation: @escaping @MainActor () async -> Value
  ) async -> Value {
    guard runningTask == nil else {
      return fallback
    }

    let task = Task { @MainActor in
      guard !Task.isCancelled else {
        return fallback
      }
      return await operation()
    }
    runningTask = RunningTask(
      cancel: {
        task.cancel()
      },
      wait: {
        _ = await task.value
      }
    )

    let result = await withTaskCancellationHandler {
      await task.value
    } onCancel: {
      task.cancel()
    }

    runningTask = nil
    return result
  }

  func cancelAndWait() async {
    guard let runningTask else {
      return
    }

    runningTask.cancel()
    await runningTask.wait()
  }
}

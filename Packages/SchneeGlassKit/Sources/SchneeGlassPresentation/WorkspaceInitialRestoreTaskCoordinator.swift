@MainActor
final class WorkspaceInitialRestoreTaskCoordinator {
  private var task: Task<Void, Never>?

  var isRunning: Bool {
    task != nil
  }

  func run(
    operation: @escaping @MainActor () async -> Void
  ) async {
    guard task == nil else {
      return
    }

    let task = Task { @MainActor in
      await operation()
    }
    self.task = task

    await withTaskCancellationHandler {
      await task.value
    } onCancel: {
      task.cancel()
    }

    self.task = nil
  }

  func cancelAndWait() async {
    guard let task else {
      return
    }

    task.cancel()
    await task.value
  }
}

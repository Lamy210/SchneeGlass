import Foundation

public enum ApplicationTerminationDecision: Equatable, Sendable {
  case terminateNow
  case terminateLater
}

@MainActor
public final class ApplicationTerminationCoordinator {
  private enum State {
    case idle
    case waitingForShutdown
    case approved
  }

  private var state: State = .idle
  private var shutdownOperation: (@MainActor () async -> Void)?
  private var shutdownTask: Task<Void, Never>?

  public init(
    shutdownOperation: (@MainActor () async -> Void)? = nil
  ) {
    self.shutdownOperation = shutdownOperation
  }

  public func configure(
    shutdownOperation: @escaping @MainActor () async -> Void
  ) {
    guard state == .idle else {
      return
    }
    self.shutdownOperation = shutdownOperation
  }

  public func requestTermination(
    reply: @escaping @MainActor (Bool) -> Void
  ) -> ApplicationTerminationDecision {
    switch state {
    case .approved:
      return .terminateNow
    case .waitingForShutdown:
      return .terminateLater
    case .idle:
      guard let shutdownOperation else {
        state = .approved
        return .terminateNow
      }

      state = .waitingForShutdown
      shutdownTask = Task { @MainActor [weak self] in
        await shutdownOperation()

        guard let self,
          self.state == .waitingForShutdown
        else {
          return
        }

        self.state = .approved
        self.shutdownTask = nil
        reply(true)
      }
      return .terminateLater
    }
  }
}

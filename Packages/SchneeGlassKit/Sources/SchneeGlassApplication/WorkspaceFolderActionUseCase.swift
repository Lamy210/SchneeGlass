import Foundation

@MainActor
public final class WorkspaceFolderActionUseCase {
  private let actor: any WorkspaceFileActing

  public init(actor: any WorkspaceFileActing) {
    self.actor = actor
  }

  public func revealConnectedFolder(url: URL) {
    actor.reveal(url: url.standardizedFileURL)
  }
}

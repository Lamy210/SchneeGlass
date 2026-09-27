import Foundation
import Testing

@testable import SchneeGlassApplication

@MainActor
private final class FolderActionRecorder: WorkspaceFileActing {
  private(set) var revealedURLs: [URL] = []

  func open(url: URL) -> Bool {
    false
  }

  func reveal(url: URL) {
    revealedURLs.append(url)
  }
}

@Test
@MainActor
func connectedFolderRevealUsesStandardizedURL() {
  let recorder = FolderActionRecorder()
  let useCase = WorkspaceFolderActionUseCase(actor: recorder)
  let input = URL(fileURLWithPath: "/tmp/Projects/../Projects", isDirectory: true)

  useCase.revealConnectedFolder(url: input)

  #expect(recorder.revealedURLs == [input.standardizedFileURL])
}

import Foundation
@testable import SchneeGlassMacOSAdapter
import Testing

@MainActor
private final class FakeWorkspaceOpener: WorkspaceOpening {
    var openResult = true
    private(set) var openedURLs: [URL] = []
    private(set) var revealedURLs: [URL] = []

    func open(_ url: URL) -> Bool {
        openedURLs.append(url)
        return openResult
    }

    func reveal(_ url: URL) {
        revealedURLs.append(url)
    }
}

@Test
@MainActor
func workspaceAdapterStandardizesURLBeforeOpening() {
    let opener = FakeWorkspaceOpener()
    let adapter = NSWorkspaceFileActionAdapter(opener: opener)
    let input = URL(fileURLWithPath: "/tmp/Folder/../report.txt")

    let result = adapter.open(url: input)

    #expect(result)
    #expect(opener.openedURLs == [input.standardizedFileURL])
}

@Test
@MainActor
func workspaceAdapterPreservesOpenFailure() {
    let opener = FakeWorkspaceOpener()
    opener.openResult = false
    let adapter = NSWorkspaceFileActionAdapter(opener: opener)

    let result = adapter.open(url: URL(fileURLWithPath: "/tmp/missing.txt"))

    #expect(!result)
}

@Test
@MainActor
func workspaceAdapterStandardizesURLBeforeReveal() {
    let opener = FakeWorkspaceOpener()
    let adapter = NSWorkspaceFileActionAdapter(opener: opener)
    let input = URL(fileURLWithPath: "/tmp/Folder/../report.txt")

    adapter.reveal(url: input)

    #expect(opener.revealedURLs == [input.standardizedFileURL])
}

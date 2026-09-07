import AppKit
import Foundation
import SchneeGlassApplication

@MainActor
protocol WorkspaceOpening: Sendable {
    func open(_ url: URL) -> Bool
    func reveal(_ url: URL)
}

@MainActor
struct FoundationWorkspaceOpener: WorkspaceOpening {
    func open(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

@MainActor
public final class NSWorkspaceFileActionAdapter: WorkspaceFileActing {
    private let opener: any WorkspaceOpening

    public init() {
        self.opener = FoundationWorkspaceOpener()
    }

    init(opener: any WorkspaceOpening) {
        self.opener = opener
    }

    public func open(url: URL) -> Bool {
        opener.open(url.standardizedFileURL)
    }

    public func reveal(url: URL) {
        opener.reveal(url.standardizedFileURL)
    }
}

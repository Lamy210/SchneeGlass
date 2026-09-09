import AppKit
import SwiftUI

@MainActor
public struct FileURLDropTarget: NSViewRepresentable {
    public typealias NSViewType = FileURLDropDestinationView

    private let onPlan: @MainActor ([URL]) async -> Bool
    private let onExit: @MainActor () -> Void
    private let onPerform: @MainActor ([URL]) async -> Void

    public init(
        onPlan: @escaping @MainActor ([URL]) async -> Bool,
        onExit: @escaping @MainActor () -> Void,
        onPerform: @escaping @MainActor ([URL]) async -> Void
    ) {
        self.onPlan = onPlan
        self.onExit = onExit
        self.onPerform = onPerform
    }

    public func makeNSView(context: Context) -> FileURLDropDestinationView {
        FileURLDropDestinationView(
            onPlan: onPlan,
            onExit: onExit,
            onPerform: onPerform
        )
    }

    public func updateNSView(
        _ nsView: FileURLDropDestinationView,
        context: Context
    ) {
        nsView.updateCallbacks(
            onPlan: onPlan,
            onExit: onExit,
            onPerform: onPerform
        )
    }
}

@MainActor
public final class FileURLDropDestinationView: NSView {
    private var onPlan: @MainActor ([URL]) async -> Bool
    private var onExit: @MainActor () -> Void
    private var onPerform: @MainActor ([URL]) async -> Void

    private var validationTask: Task<Void, Never>?
    private var validationToken = UUID()
    private var currentSignature: String?
    private var currentOperation: NSDragOperation = []
    private var didDispatchPerform = false

    init(
        onPlan: @escaping @MainActor ([URL]) async -> Bool,
        onExit: @escaping @MainActor () -> Void,
        onPerform: @escaping @MainActor ([URL]) async -> Void
    ) {
        self.onPlan = onPlan
        self.onExit = onExit
        self.onPerform = onPerform
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    deinit {
        validationTask?.cancel()
    }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        // This view is only a dragging destination. Normal clicks, double-clicks,
        // context menus, and accessibility interaction stay owned by SwiftUI.
        nil
    }

    public override func wantsPeriodicDraggingUpdates() -> Bool {
        // Planning uses an async filesystem inspection. Periodic updates let
        // AppKit pick up a newly validated .copy operation even if the pointer
        // remains stationary while that inspection completes.
        true
    }

    public override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        didDispatchPerform = false
        updateValidation(for: sender)
        return currentOperation
    }

    public override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        updateValidation(for: sender)
        return currentOperation
    }

    public override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        resetValidation(notifyExit: true)
    }

    public override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        currentOperation.contains(.copy) && !fileURLs(from: sender).isEmpty
    }

    public override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let urls = fileURLs(from: sender)
        guard currentOperation.contains(.copy), !urls.isEmpty else {
            resetValidation(notifyExit: true)
            return false
        }

        // performDragOperation must return synchronously. The Application layer
        // re-plans immediately before mutation, so this cached hover validation
        // is never treated as authorization.
        validationTask?.cancel()
        validationTask = nil
        currentOperation = []
        currentSignature = nil
        didDispatchPerform = true

        let perform = onPerform
        Task { @MainActor in
            await perform(urls)
        }
        return true
    }

    public override func draggingEnded(_ sender: any NSDraggingInfo) {
        let performWasDispatched = didDispatchPerform
        didDispatchPerform = false
        finishDraggingSession(performWasDispatched: performWasDispatched)
    }

    /// A cancelled drag can end without first exiting this view. Notify the workspace only when no
    /// perform callback was dispatched; successful Drop execution owns its own interaction state.
    func finishDraggingSession(performWasDispatched: Bool) {
        resetValidation(notifyExit: !performWasDispatched)
    }

    func updateCallbacks(
        onPlan: @escaping @MainActor ([URL]) async -> Bool,
        onExit: @escaping @MainActor () -> Void,
        onPerform: @escaping @MainActor ([URL]) async -> Void
    ) {
        self.onPlan = onPlan
        self.onExit = onExit
        self.onPerform = onPerform
    }

    private func updateValidation(for sender: any NSDraggingInfo) {
        let urls = fileURLs(from: sender)
        guard !urls.isEmpty else {
            resetValidation(notifyExit: false)
            return
        }

        let signature = dragSignature(for: urls)
        guard signature != currentSignature else {
            return
        }

        currentSignature = signature
        currentOperation = []
        validationTask?.cancel()

        let token = UUID()
        validationToken = token
        let plan = onPlan

        validationTask = Task { @MainActor [weak self] in
            let accepted = await plan(urls)
            guard !Task.isCancelled,
                  let self,
                  self.validationToken == token,
                  self.currentSignature == signature
            else {
                return
            }
            self.currentOperation = accepted ? .copy : []
        }
    }

    private func resetValidation(notifyExit: Bool) {
        validationTask?.cancel()
        validationTask = nil
        validationToken = UUID()
        currentSignature = nil
        currentOperation = []
        if notifyExit {
            onExit()
        }
    }

    private func fileURLs(from sender: any NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        let objects = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) ?? []

        return objects.compactMap { object in
            (object as? NSURL)?.absoluteURL?.standardizedFileURL
        }
    }

    private func dragSignature(for urls: [URL]) -> String {
        urls
            .map { $0.standardizedFileURL.path }
            .sorted()
            .joined(separator: "\u{0}")
    }
}

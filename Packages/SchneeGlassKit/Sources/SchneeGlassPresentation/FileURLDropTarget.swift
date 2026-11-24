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
  private var validationRefreshPolicy = DropValidationRefreshPolicy()
  // Approval is derived from the refresh policy. Starting a fresh hover
  // validation immediately disables the old copy operation.
  private var currentOperation: NSDragOperation {
    validationRefreshPolicy.approvedSignature == nil ? [] : .copy
  }
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
    // remains stationary while that inspection completes or external state changes.
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
    DropPayloadApprovalPolicy.allowsCopy(
      operation: currentOperation,
      approvedSignature: validationRefreshPolicy.approvedSignature,
      incomingURLs: fileURLs(from: sender)
    )
  }

  public override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    let urls = fileURLs(from: sender)
    // The drag payload may have changed since hover validation. Never
    // advertise/dispatch approval for different URLs, even though the
    // Application layer will independently re-plan before any copy.
    guard
      DropPayloadApprovalPolicy.allowsCopy(
        operation: currentOperation,
        approvedSignature: validationRefreshPolicy.approvedSignature,
        incomingURLs: urls
      )
    else {
      resetValidation(notifyExit: true)
      return false
    }

    // performDragOperation must return synchronously. The Application layer
    // re-plans immediately before mutation, so this cached hover validation
    // is never treated as authorization.
    validationTask?.cancel()
    validationTask = nil
    validationRefreshPolicy.reset()
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

    let signature = DropPayloadApprovalPolicy.signature(for: urls)
    let decision = validationRefreshPolicy.decision(
      for: signature,
      now: ProcessInfo.processInfo.systemUptime,
      validationInFlight: validationTask != nil
    )
    guard decision != .skip else {
      return
    }
    validationTask?.cancel()

    let token = UUID()
    validationToken = token
    let plan = onPlan

    validationTask = Task { @MainActor [weak self] in
      let accepted = await plan(urls)
      guard let self else {
        return
      }

      let isCurrent =
        self.validationToken == token
        && self.validationRefreshPolicy.currentSignature == signature
      if isCurrent {
        self.validationTask = nil
      }

      guard !Task.isCancelled, isCurrent else {
        return
      }
      self.validationRefreshPolicy.resolve(signature: signature, accepted: accepted)
    }
  }

  private func resetValidation(notifyExit: Bool) {
    validationTask?.cancel()
    validationTask = nil
    validationToken = UUID()
    validationRefreshPolicy.reset()
    if notifyExit {
      onExit()
    }
  }

  private func fileURLs(from sender: any NSDraggingInfo) -> [URL] {
    let options: [NSPasteboard.ReadingOptionKey: Any] = [
      .urlReadingFileURLsOnly: true
    ]
    let objects =
      sender.draggingPasteboard.readObjects(
        forClasses: [NSURL.self],
        options: options
      ) ?? []

    return objects.compactMap { object in
      (object as? NSURL)?.absoluteURL?.standardizedFileURL
    }
  }
}

enum DropPayloadApprovalPolicy {
  /// URL order may change across AppKit drag callbacks, but their normalized
  /// destination-independent paths must describe the same set of inputs.
  static func signature(for urls: [URL]) -> String {
    urls
      .map { $0.standardizedFileURL.path }
      .sorted()
      .joined(separator: "\u{0}")
  }

  static func allowsCopy(
    operation: NSDragOperation,
    approvedSignature: String?,
    incomingURLs: [URL]
  ) -> Bool {
    guard operation.contains(.copy),
      let approvedSignature,
      !incomingURLs.isEmpty
    else {
      return false
    }

    return approvedSignature == signature(for: incomingURLs)
  }
}

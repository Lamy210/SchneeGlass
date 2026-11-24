import AppKit
import Foundation
import Testing

@testable import SchneeGlassPresentation

@Test
@MainActor
func cancelledDragSessionNotifiesWorkspaceExitCleanup() {
  var exitCount = 0
  let view = FileURLDropDestinationView(
    onPlan: { _ in false },
    onExit: { exitCount += 1 },
    onPerform: { _ in }
  )

  view.finishDraggingSession(performWasDispatched: false)

  #expect(exitCount == 1)
}

@Test
@MainActor
func completedDropDoesNotSendCancellationCleanup() {
  var exitCount = 0
  let view = FileURLDropDestinationView(
    onPlan: { _ in false },
    onExit: { exitCount += 1 },
    onPerform: { _ in }
  )

  view.finishDraggingSession(performWasDispatched: true)

  #expect(exitCount == 0)
}

@Test
func dropValidationRefreshPolicyRechecksStableSignatureWithoutOverlappingWork() {
  var policy = DropValidationRefreshPolicy(minimumInterval: 0.5)

  #expect(
    policy.decision(
      for: "same-files",
      now: 10,
      validationInFlight: false
    ) == .start(isNewSignature: true)
  )
  #expect(
    policy.decision(
      for: "same-files",
      now: 10.2,
      validationInFlight: false
    ) == .skip
  )
  #expect(
    policy.decision(
      for: "same-files",
      now: 10.6,
      validationInFlight: true
    ) == .skip
  )
  #expect(
    policy.decision(
      for: "same-files",
      now: 10.6,
      validationInFlight: false
    ) == .start(isNewSignature: false)
  )

  #expect(
    policy.decision(
      for: "different-files",
      now: 10.61,
      validationInFlight: true
    ) == .start(isNewSignature: true)
  )

  policy.reset()
  #expect(
    policy.decision(
      for: "different-files",
      now: 10.62,
      validationInFlight: false
    ) == .start(isNewSignature: true)
  )
}

@Test
func approvedDragRejectsChangedPasteboardPayloadBeforeCopy() {
  let original = URL(fileURLWithPath: "/tmp/SchneeGlass-drop-original.txt")
  let replacement = URL(fileURLWithPath: "/tmp/SchneeGlass-drop-replacement.txt")
  let approval = DropPayloadApprovalPolicy.signature(for: [original])

  #expect(
    DropPayloadApprovalPolicy.allowsCopy(
      operation: .copy,
      approvedSignature: approval,
      incomingURLs: [original]
    )
  )
  #expect(
    !DropPayloadApprovalPolicy.allowsCopy(
      operation: .copy,
      approvedSignature: approval,
      incomingURLs: [replacement]
    )
  )
  #expect(
    !DropPayloadApprovalPolicy.allowsCopy(
      operation: .copy,
      approvedSignature: nil,
      incomingURLs: [original]
    )
  )
  #expect(
    !DropPayloadApprovalPolicy.allowsCopy(
      operation: [],
      approvedSignature: approval,
      incomingURLs: [original]
    )
  )
  #expect(
    !DropPayloadApprovalPolicy.allowsCopy(
      operation: .copy,
      approvedSignature: approval,
      incomingURLs: []
    )
  )
}

@Test
func approvedMultiFileDragIgnoresOrderButNotAddedOrRemovedURLs() {
  let first = URL(fileURLWithPath: "/tmp/SchneeGlass-drop-a.txt")
  let second = URL(fileURLWithPath: "/tmp/SchneeGlass-drop-b.txt")
  let third = URL(fileURLWithPath: "/tmp/SchneeGlass-drop-c.txt")
  let approval = DropPayloadApprovalPolicy.signature(for: [first, second])

  #expect(
    DropPayloadApprovalPolicy.allowsCopy(
      operation: .copy,
      approvedSignature: approval,
      incomingURLs: [second, first]
    )
  )
  for changed in [[first], [first, second, third], [first, third], [first, first]] {
    #expect(
      !DropPayloadApprovalPolicy.allowsCopy(
        operation: .copy,
        approvedSignature: approval,
        incomingURLs: changed
      )
    )
  }
}

@Test
func approvedDragComparesStandardizedFileURLs() {
  let original = URL(fileURLWithPath: "/tmp/SchneeGlass-drop-folder/../report.txt")
  let standardized = URL(fileURLWithPath: "/tmp/report.txt")
  let approval = DropPayloadApprovalPolicy.signature(for: [original])

  #expect(
    DropPayloadApprovalPolicy.allowsCopy(
      operation: .copy,
      approvedSignature: approval,
      incomingURLs: [standardized]
    )
  )
}

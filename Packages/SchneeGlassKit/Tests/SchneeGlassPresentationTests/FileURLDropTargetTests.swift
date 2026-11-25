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

@Test
func hoverRefreshRevokesOldCopyApprovalUntilFreshPlanSucceeds() {
  var policy = DropValidationRefreshPolicy(minimumInterval: 0.5)

  #expect(
    policy.decision(
      for: "same-files",
      now: 10,
      validationInFlight: false
    ) == .start(isNewSignature: true)
  )
  #expect(policy.approvedSignature == nil)

  policy.resolve(signature: "same-files", accepted: true)
  #expect(policy.approvedSignature == "same-files")

  #expect(
    policy.decision(
      for: "same-files",
      now: 10.25,
      validationInFlight: false
    ) == .skip
  )
  #expect(policy.approvedSignature == "same-files")

  #expect(
    policy.decision(
      for: "same-files",
      now: 10.5,
      validationInFlight: false
    ) == .start(isNewSignature: false)
  )
  #expect(policy.approvedSignature == nil)

  policy.resolve(signature: "same-files", accepted: false)
  #expect(policy.approvedSignature == nil)

  #expect(
    policy.decision(
      for: "same-files",
      now: 11,
      validationInFlight: false
    ) == .start(isNewSignature: false)
  )
  policy.resolve(signature: "same-files", accepted: true)
  #expect(policy.approvedSignature == "same-files")
}

@Test
func staleOrCancelledHoverCannotAuthorizeNewDragPayload() {
  var policy = DropValidationRefreshPolicy(minimumInterval: 0.5)

  #expect(
    policy.decision(
      for: "first",
      now: 20,
      validationInFlight: false
    ) == .start(isNewSignature: true)
  )
  policy.resolve(signature: "first", accepted: true)
  #expect(policy.approvedSignature == "first")

  #expect(
    policy.decision(
      for: "second",
      now: 20.1,
      validationInFlight: true
    ) == .start(isNewSignature: true)
  )
  #expect(policy.approvedSignature == nil)

  policy.resolve(signature: "first", accepted: true)
  #expect(policy.approvedSignature == nil)
  policy.resolve(signature: "second", accepted: true)
  #expect(policy.approvedSignature == "second")

  policy.reset()
  #expect(policy.currentSignature == nil)
  #expect(policy.approvedSignature == nil)
  policy.resolve(signature: "second", accepted: true)
  #expect(policy.approvedSignature == nil)
}

@Test
func inFlightRefreshCannotReuseAnEarlierPayloadSignatureApproval() {
  let url = URL(fileURLWithPath: "/tmp/SchneeGlass-drop-revalidate.txt")
  let signature = DropPayloadApprovalPolicy.signature(for: [url])
  var policy = DropValidationRefreshPolicy(minimumInterval: 0.5)

  #expect(
    policy.decision(
      for: signature,
      now: 30,
      validationInFlight: false
    ) == .start(isNewSignature: true)
  )
  policy.resolve(signature: signature, accepted: true)
  #expect(
    DropPayloadApprovalPolicy.allowsCopy(
      operation: .copy,
      approvedSignature: policy.approvedSignature,
      incomingURLs: [url]
    )
  )

  #expect(
    policy.decision(
      for: signature,
      now: 30.5,
      validationInFlight: false
    ) == .start(isNewSignature: false)
  )
  // Even a stale .copy icon cannot authorize a drop while a new preview
  // is in progress: only the current successful preview may approve it.
  #expect(
    !DropPayloadApprovalPolicy.allowsCopy(
      operation: .copy,
      approvedSignature: policy.approvedSignature,
      incomingURLs: [url]
    )
  )
}

@Test
func dropOnlyOffersCopyWhenDragSourcePermitsCopy() {
  let copyAndMove: NSDragOperation = [.copy, .move]

  #expect(
    DropPayloadApprovalPolicy.copyOperation(
      requested: .copy,
      source: .copy
    ) == .copy
  )
  #expect(
    DropPayloadApprovalPolicy.copyOperation(
      requested: .copy,
      source: copyAndMove
    ) == .copy
  )
  #expect(
    DropPayloadApprovalPolicy.copyOperation(
      requested: .copy,
      source: .move
    ) == []
  )
  #expect(
    DropPayloadApprovalPolicy.copyOperation(
      requested: .copy,
      source: .link
    ) == []
  )
  #expect(
    DropPayloadApprovalPolicy.copyOperation(
      requested: .copy,
      source: []
    ) == []
  )
  #expect(
    DropPayloadApprovalPolicy.copyOperation(
      requested: [],
      source: copyAndMove
    ) == []
  )
  #expect(
    DropPayloadApprovalPolicy.copyOperation(
      requested: .move,
      source: copyAndMove
    ) == []
  )
}

@Test
func dragSourceMaskChangeRejectsPreviouslyApprovedCopyPayload() {
  let url = URL(fileURLWithPath: "/tmp/SchneeGlass-source-mask.txt")
  let approved = DropPayloadApprovalPolicy.signature(for: [url])

  #expect(
    DropPayloadApprovalPolicy.allowsCopy(
      operation: DropPayloadApprovalPolicy.copyOperation(
        requested: .copy,
        source: .copy
      ),
      approvedSignature: approved,
      incomingURLs: [url]
    )
  )
  #expect(
    !DropPayloadApprovalPolicy.allowsCopy(
      operation: DropPayloadApprovalPolicy.copyOperation(
        requested: .copy,
        source: .move
      ),
      approvedSignature: approved,
      incomingURLs: [url]
    )
  )
}

import Testing

@testable import SchneeGlassMacOSAdapter

@MainActor
private final class ShortcutToggleCounter {
  var calls = 0

  func record() {
    calls += 1
  }
}

@Test
@MainActor
func queuedShortcutDeliveryDoesNotToggleAfterControllerStops() async {
  let counter = ShortcutToggleCounter()
  let controller = SchneeGlassGlobalVisibilityShortcutController {
    counter.record()
  }

  // The normal main-actor delivery still calls the visibility action.
  controller.deliverToggleIfActive()
  #expect(counter.calls == 1)

  // Model a key-up task queued on the main actor just before shutdown.
  // Stop synchronously before giving the scheduled task its first turn.
  let queuedKeyUp = Task { @MainActor in
    controller.deliverToggleIfActive()
  }
  controller.stop()
  await queuedKeyUp.value

  #expect(counter.calls == 1)
  // Stop is idempotent, and a later callback must remain inert.
  controller.stop()
  controller.deliverToggleIfActive()
  #expect(counter.calls == 1)

  // Replacing the registered controller also invalidates a queued event from
  // the previous owner, even if its explicit stop() was never called.
  let oldCounter = ShortcutToggleCounter()
  let previous = SchneeGlassGlobalVisibilityShortcutController {
    oldCounter.record()
  }
  let pendingOldKeyUp = Task { @MainActor in
    previous.deliverToggleIfActive()
  }
  let currentCounter = ShortcutToggleCounter()
  let current = SchneeGlassGlobalVisibilityShortcutController {
    currentCounter.record()
  }
  await pendingOldKeyUp.value
  #expect(oldCounter.calls == 0)

  // A stopped predecessor cannot suppress the active replacement.
  previous.stop()
  current.deliverToggleIfActive()
  #expect(currentCounter.calls == 1)
  current.stop()
}

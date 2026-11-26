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
}

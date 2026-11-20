import Foundation

/// Retires an actor-owned session only after its asynchronous cleanup has finished.
/// Keeping it discoverable across suspension lets concurrent shutdown join cleanup.
/// A replacement installed during the await must never be removed by the old caller.
@MainActor
enum WorkspaceSessionRetirement {
  static func stopAndRemove(
    stop: () async -> Void,
    isCurrent: () -> Bool,
    remove: () -> Void
  ) async {
    await stop()
    if isCurrent() {
      remove()
    }
  }
}

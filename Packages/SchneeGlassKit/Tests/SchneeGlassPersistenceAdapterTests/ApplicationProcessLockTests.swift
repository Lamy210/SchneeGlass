import Foundation
import Testing
@testable import SchneeGlassPersistenceAdapter

@Test
func applicationProcessLockRejectsSecondOwnerUntilFirstReleases() throws {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("schneeglass-process-lock-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let lockURL = root.appendingPathComponent("instance.lock", isDirectory: false)
  var firstLock: ApplicationProcessLock? = try ApplicationProcessLock(lockFileURL: lockURL)

  do {
    _ = try ApplicationProcessLock(lockFileURL: lockURL)
    Issue.record("Expected a second process lock owner to be rejected")
  } catch let error as ApplicationProcessLockError {
    #expect(error == .alreadyLocked)
  } catch {
    Issue.record("Expected ApplicationProcessLockError.alreadyLocked, got \(error)")
  }

  firstLock = nil
  _ = try ApplicationProcessLock(lockFileURL: lockURL)
}

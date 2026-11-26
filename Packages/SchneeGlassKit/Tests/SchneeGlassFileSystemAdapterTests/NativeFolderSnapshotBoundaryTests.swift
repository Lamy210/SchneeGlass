import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing

@testable import SchneeGlassFileSystemAdapter

@Test("hidden children do not falsely mark a 500-item snapshot as truncated")
func snapshotLimitCountsOnlyVisibleChildrenAtTheBoundary() async throws {
  let manager = FileManager.default
  let root = manager.temporaryDirectory
    .appendingPathComponent("SchneeGlass-snapshot-boundary-\(UUID().uuidString)", isDirectory: true)
  try manager.createDirectory(at: root, withIntermediateDirectories: false)
  defer {
    do {
      try manager.removeItem(at: root)
    } catch {
      Issue.record("Could not remove disposable snapshot boundary test folder")
    }
  }

  let limit = NativeFolderSnapshotReader.maximumDisplayedItems
  for index in 0..<limit {
    let file = root.appendingPathComponent(String(format: "visible-%04d.txt", index))
    try Data().write(to: file)
  }
  try Data().write(to: root.appendingPathComponent(".hidden-extra.txt"))

  let reader = NativeFolderSnapshotReader()
  let access = FolderAccessHandle(glassID: GlassID(), url: root)
  let atLimit = try await reader.snapshot(for: access, generation: 1)

  #expect(atLimit.items.count == limit)
  #expect(!atLimit.isTruncated)
  #expect(!atLimit.items.contains { $0.displayName == ".hidden-extra.txt" })

  // The same folder must transition to truncation only when a new visible
  // direct child crosses the limit, not when a hidden child exists.
  try Data().write(to: root.appendingPathComponent("visible-overflow.txt"))
  let overLimit = try await reader.snapshot(for: access, generation: 2)

  #expect(overLimit.items.count == limit)
  #expect(overLimit.isTruncated)
  #expect(overLimit.generation == 2)
  #expect(!overLimit.items.contains { $0.displayName == ".hidden-extra.txt" })
}

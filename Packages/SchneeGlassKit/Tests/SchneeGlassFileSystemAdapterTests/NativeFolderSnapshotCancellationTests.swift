import FileDomain
import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import SchneeGlassPOSIXSupport
import Testing

@testable import SchneeGlassFileSystemAdapter

private actor SnapshotCancellationRuntimeIdentityReader: RuntimeDirectoryIdentityReading {
  private let identity: POSIXDirectoryIdentity?
  private let cancelOnCall: Int?
  private var callCountValue = 0

  init(
    identity: POSIXDirectoryIdentity?,
    cancelOnCall: Int? = nil
  ) {
    self.identity = identity
    self.cancelOnCall = cancelOnCall
  }

  func identity(for url: URL) async -> POSIXDirectoryIdentity? {
    _ = url
    callCountValue += 1

    if callCountValue == cancelOnCall {
      withUnsafeCurrentTask { task in
        task?.cancel()
      }
    }

    return identity
  }

  func callCount() -> Int {
    callCountValue
  }
}

private func makeSnapshotCancellationRoot(_ name: String) throws -> URL {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent(
      "SchneeGlassSnapshotCancellation-\(name)-\(UUID().uuidString)",
      isDirectory: true
    )
  try FileManager.default.createDirectory(
    at: root,
    withIntermediateDirectories: true
  )
  return root
}

private func expectSnapshotCancellation(
  reader: NativeFolderSnapshotReader,
  access: FolderAccessHandle
) async {
  do {
    _ = try await reader.snapshot(for: access, generation: 1)
    Issue.record("Expected snapshot cancellation")
  } catch is CancellationError {
  } catch {
    Issue.record("Expected CancellationError, got \(error)")
  }
}

@Test
func preCancelledSnapshotStopsBeforeRuntimeIdentityRead() async throws {
  let root = try makeSnapshotCancellationRoot("pre-cancelled")
  defer { try? FileManager.default.removeItem(at: root) }

  let identityReader = SnapshotCancellationRuntimeIdentityReader(identity: nil)
  let reader = NativeFolderSnapshotReader(
    fileManager: .default,
    runtimeIdentityReader: identityReader
  )
  let access = FolderAccessHandle(
    glassID: GlassID(),
    url: root,
    fingerprint: nil
  )

  let task = Task {
    withUnsafeCurrentTask { current in
      current?.cancel()
    }

    return try await reader.snapshot(for: access, generation: 1)
  }

  do {
    _ = try await task.value
    Issue.record("Expected snapshot cancellation")
  } catch is CancellationError {
  } catch {
    Issue.record("Expected CancellationError, got \(error)")
  }

  #expect(await identityReader.callCount() == 0)
}

@Test
func cancellationAfterInitialRuntimeIdentityStopsBeforeEnumeration() async throws {
  let root = try makeSnapshotCancellationRoot("initial-identity")
  defer { try? FileManager.default.removeItem(at: root) }

  let identity = POSIXDirectoryIdentity(device: 7, inode: 41)
  let identityReader = SnapshotCancellationRuntimeIdentityReader(
    identity: identity,
    cancelOnCall: 1
  )
  let reader = NativeFolderSnapshotReader(
    fileManager: .default,
    runtimeIdentityReader: identityReader
  )
  let access = FolderAccessHandle(
    glassID: GlassID(),
    url: root,
    fingerprint: nil,
    runtimeDirectoryIdentity: RuntimeDirectoryIdentity(
      deviceIdentifier: identity.device,
      objectIdentifier: identity.inode
    )
  )

  await expectSnapshotCancellation(reader: reader, access: access)

  #expect(await identityReader.callCount() == 1)
}

@Test
func cancellationAfterFinalRuntimeIdentityDoesNotPublishSnapshot() async throws {
  let root = try makeSnapshotCancellationRoot("final-identity")
  defer { try? FileManager.default.removeItem(at: root) }

  let child = root.appendingPathComponent("visible.txt", isDirectory: false)
  try Data("visible".utf8).write(to: child)

  let identity = POSIXDirectoryIdentity(device: 7, inode: 41)
  let identityReader = SnapshotCancellationRuntimeIdentityReader(
    identity: identity,
    cancelOnCall: 2
  )
  let reader = NativeFolderSnapshotReader(
    fileManager: .default,
    runtimeIdentityReader: identityReader
  )
  let access = FolderAccessHandle(
    glassID: GlassID(),
    url: root,
    fingerprint: nil,
    runtimeDirectoryIdentity: RuntimeDirectoryIdentity(
      deviceIdentifier: identity.device,
      objectIdentifier: identity.inode
    )
  )

  await expectSnapshotCancellation(reader: reader, access: access)

  #expect(await identityReader.callCount() == 2)
}

import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import SchneeGlassPOSIXSupport
import Testing

@testable import SchneeGlassFileSystemAdapter

private enum FolderSourceCancellationTestError: Error, Sendable {
  case injected
}

private actor FolderSourceCancellationResourceAccessor: SecurityScopedResourceAccessing {
  private let fingerprintThrowCancellationOnCall: Int?
  private let fingerprintCancelAndReturnOnCall: Int?
  private let persistentThrowCancellationOnCall: Int?
  private let persistentCancelAndReturnOnCall: Int?
  private let persistentThrowsOrdinaryError: Bool
  private let bookmarkThrowsCancellation: Bool
  private let bookmarkCancelsAndReturns: Bool

  private var fingerprintCount = 0
  private var persistentIdentityCount = 0
  private var bookmarkCount = 0

  init(
    fingerprintThrowCancellationOnCall: Int? = nil,
    fingerprintCancelAndReturnOnCall: Int? = nil,
    persistentThrowCancellationOnCall: Int? = nil,
    persistentCancelAndReturnOnCall: Int? = nil,
    persistentThrowsOrdinaryError: Bool = false,
    bookmarkThrowsCancellation: Bool = false,
    bookmarkCancelsAndReturns: Bool = false
  ) {
    self.fingerprintThrowCancellationOnCall = fingerprintThrowCancellationOnCall
    self.fingerprintCancelAndReturnOnCall = fingerprintCancelAndReturnOnCall
    self.persistentThrowCancellationOnCall = persistentThrowCancellationOnCall
    self.persistentCancelAndReturnOnCall = persistentCancelAndReturnOnCall
    self.persistentThrowsOrdinaryError = persistentThrowsOrdinaryError
    self.bookmarkThrowsCancellation = bookmarkThrowsCancellation
    self.bookmarkCancelsAndReturns = bookmarkCancelsAndReturns
  }

  func resolveBookmark(_ data: Data) async throws -> ResolvedSecurityScopedResource {
    _ = data
    throw FolderSourceCancellationTestError.injected
  }

  func createBookmark(for url: URL) async throws -> Data {
    _ = url
    bookmarkCount += 1

    if bookmarkThrowsCancellation {
      throw CancellationError()
    }
    if bookmarkCancelsAndReturns {
      withUnsafeCurrentTask { task in
        task?.cancel()
      }
    }
    return Data([7, 8, 9])
  }

  func startAccessing(_ url: URL) async -> Bool {
    _ = url
    return false
  }

  func stopAccessing(_ url: URL) async {
    _ = url
  }

  func fingerprint(for url: URL) async throws -> ResourceFingerprint? {
    _ = url
    fingerprintCount += 1

    if fingerprintCount == fingerprintThrowCancellationOnCall {
      throw CancellationError()
    }
    if fingerprintCount == fingerprintCancelAndReturnOnCall {
      withUnsafeCurrentTask { task in
        task?.cancel()
      }
    }

    return ResourceFingerprint(
      volumeIdentifier: "volume-a",
      resourceIdentifier: "folder-a"
    )
  }

  func persistentIdentity(for url: URL) async throws -> PersistentFolderIdentity? {
    _ = url
    persistentIdentityCount += 1

    if persistentIdentityCount == persistentThrowCancellationOnCall {
      throw CancellationError()
    }
    if persistentIdentityCount == persistentCancelAndReturnOnCall {
      withUnsafeCurrentTask { task in
        task?.cancel()
      }
    }
    if persistentThrowsOrdinaryError {
      throw FolderSourceCancellationTestError.injected
    }

    return PersistentFolderIdentity(
      volumeUUIDString: "volume-uuid-a",
      documentIdentifier: 41
    )
  }

  func counts() -> (
    fingerprints: Int,
    persistentIdentities: Int,
    bookmarks: Int
  ) {
    (
      fingerprintCount,
      persistentIdentityCount,
      bookmarkCount
    )
  }
}

private actor FolderSourceCancellationRuntimeIdentityReader: RuntimeDirectoryIdentityReading {
  private let values: [POSIXDirectoryIdentity?]
  private let cancelAndReturnOnCall: Int?
  private var callCount = 0

  init(
    values: [POSIXDirectoryIdentity?],
    cancelAndReturnOnCall: Int? = nil
  ) {
    self.values = values
    self.cancelAndReturnOnCall = cancelAndReturnOnCall
  }

  func identity(for url: URL) async -> POSIXDirectoryIdentity? {
    _ = url
    callCount += 1

    if callCount == cancelAndReturnOnCall {
      withUnsafeCurrentTask { task in
        task?.cancel()
      }
    }

    guard !values.isEmpty else {
      return nil
    }
    let index = min(callCount - 1, values.count - 1)
    return values[index]
  }

  func calls() -> Int {
    callCount
  }
}

private func folderSourceCancellationRuntimeIdentity(
  inode: UInt64 = 41
) -> POSIXDirectoryIdentity {
  POSIXDirectoryIdentity(device: 7, inode: inode)
}

private func folderSourceCancellationFactory(
  accessor: FolderSourceCancellationResourceAccessor,
  runtimeIdentityReader: FolderSourceCancellationRuntimeIdentityReader
) -> SecurityScopedFolderSourceFactory {
  SecurityScopedFolderSourceFactory(
    resourceAccessor: accessor,
    runtimeIdentityReader: runtimeIdentityReader
  )
}

private func expectFolderSourceCancellation(
  factory: SecurityScopedFolderSourceFactory,
  url: URL
) async {
  let task = Task {
    try await factory.createSource(for: url)
  }

  do {
    _ = try await task.value
    Issue.record("Expected folder source creation cancellation")
  } catch is CancellationError {
  } catch {
    Issue.record("Expected CancellationError, got \(error)")
  }
}

@Test
func preCancelledFolderSourceCreationStopsBeforeRuntimeIdentityRead() async {
  let url = URL(fileURLWithPath: "/tmp/FolderSourcePreCancelled", isDirectory: true)
  let accessor = FolderSourceCancellationResourceAccessor()
  let runtimeIdentityReader = FolderSourceCancellationRuntimeIdentityReader(values: [nil])
  let factory = folderSourceCancellationFactory(
    accessor: accessor,
    runtimeIdentityReader: runtimeIdentityReader
  )

  let task = Task {
    withUnsafeCurrentTask { current in
      current?.cancel()
    }
    return try await factory.createSource(for: url)
  }

  do {
    _ = try await task.value
    Issue.record("Expected folder source creation cancellation")
  } catch is CancellationError {
  } catch {
    Issue.record("Expected CancellationError, got \(error)")
  }

  #expect(await runtimeIdentityReader.calls() == 0)
  let counts = await accessor.counts()
  #expect(counts.fingerprints == 0)
  #expect(counts.persistentIdentities == 0)
  #expect(counts.bookmarks == 0)
}

@Test
func cancellationObservedAfterInitialRuntimeIdentityStopsBeforeFallbackReads() async {
  let url = URL(fileURLWithPath: "/tmp/FolderSourceRuntimeCancellation", isDirectory: true)
  let accessor = FolderSourceCancellationResourceAccessor()
  let runtimeIdentityReader = FolderSourceCancellationRuntimeIdentityReader(
    values: [nil],
    cancelAndReturnOnCall: 1
  )
  let factory = folderSourceCancellationFactory(
    accessor: accessor,
    runtimeIdentityReader: runtimeIdentityReader
  )

  await expectFolderSourceCancellation(factory: factory, url: url)

  #expect(await runtimeIdentityReader.calls() == 1)
  let counts = await accessor.counts()
  #expect(counts.fingerprints == 0)
  #expect(counts.persistentIdentities == 0)
  #expect(counts.bookmarks == 0)
}

@Test
func fingerprintCancellationIsNotMappedToIdentityFailure() async {
  let url = URL(fileURLWithPath: "/tmp/FolderSourceFingerprintCancellation", isDirectory: true)
  let accessor = FolderSourceCancellationResourceAccessor(
    fingerprintThrowCancellationOnCall: 1
  )
  let runtimeIdentityReader = FolderSourceCancellationRuntimeIdentityReader(values: [nil])
  let factory = folderSourceCancellationFactory(
    accessor: accessor,
    runtimeIdentityReader: runtimeIdentityReader
  )

  await expectFolderSourceCancellation(factory: factory, url: url)

  let counts = await accessor.counts()
  #expect(counts.fingerprints == 1)
  #expect(counts.persistentIdentities == 0)
  #expect(counts.bookmarks == 0)
}

@Test
func cancellationObservedAfterFingerprintStopsBeforePersistentIdentity() async {
  let url = URL(fileURLWithPath: "/tmp/FolderSourceFingerprintReturnCancellation", isDirectory: true)
  let accessor = FolderSourceCancellationResourceAccessor(
    fingerprintCancelAndReturnOnCall: 1
  )
  let runtimeIdentityReader = FolderSourceCancellationRuntimeIdentityReader(values: [nil])
  let factory = folderSourceCancellationFactory(
    accessor: accessor,
    runtimeIdentityReader: runtimeIdentityReader
  )

  await expectFolderSourceCancellation(factory: factory, url: url)

  let counts = await accessor.counts()
  #expect(counts.fingerprints == 1)
  #expect(counts.persistentIdentities == 0)
  #expect(counts.bookmarks == 0)
}

@Test
func persistentIdentityCancellationIsNotSuppressedAsOptionalMetadata() async {
  let url = URL(fileURLWithPath: "/tmp/FolderSourcePersistentCancellation", isDirectory: true)
  let accessor = FolderSourceCancellationResourceAccessor(
    persistentThrowCancellationOnCall: 1
  )
  let runtimeIdentityReader = FolderSourceCancellationRuntimeIdentityReader(
    values: [folderSourceCancellationRuntimeIdentity()]
  )
  let factory = folderSourceCancellationFactory(
    accessor: accessor,
    runtimeIdentityReader: runtimeIdentityReader
  )

  await expectFolderSourceCancellation(factory: factory, url: url)

  let counts = await accessor.counts()
  #expect(counts.persistentIdentities == 1)
  #expect(counts.bookmarks == 0)
}

@Test
func cancellationObservedAfterPersistentIdentityStopsBeforeBookmarkCreation() async {
  let url = URL(fileURLWithPath: "/tmp/FolderSourcePersistentReturnCancellation", isDirectory: true)
  let accessor = FolderSourceCancellationResourceAccessor(
    persistentCancelAndReturnOnCall: 1
  )
  let runtimeIdentityReader = FolderSourceCancellationRuntimeIdentityReader(
    values: [folderSourceCancellationRuntimeIdentity()]
  )
  let factory = folderSourceCancellationFactory(
    accessor: accessor,
    runtimeIdentityReader: runtimeIdentityReader
  )

  await expectFolderSourceCancellation(factory: factory, url: url)

  let counts = await accessor.counts()
  #expect(counts.persistentIdentities == 1)
  #expect(counts.bookmarks == 0)
}

@Test
func bookmarkCancellationIsNotMappedToBookmarkCreationFailure() async {
  let url = URL(fileURLWithPath: "/tmp/FolderSourceBookmarkCancellation", isDirectory: true)
  let accessor = FolderSourceCancellationResourceAccessor(
    bookmarkThrowsCancellation: true
  )
  let identity = folderSourceCancellationRuntimeIdentity()
  let runtimeIdentityReader = FolderSourceCancellationRuntimeIdentityReader(values: [identity])
  let factory = folderSourceCancellationFactory(
    accessor: accessor,
    runtimeIdentityReader: runtimeIdentityReader
  )

  await expectFolderSourceCancellation(factory: factory, url: url)

  let counts = await accessor.counts()
  #expect(counts.bookmarks == 1)
  #expect(await runtimeIdentityReader.calls() == 1)
}

@Test
func cancellationObservedAfterBookmarkCreationStopsBeforeFinalIdentityValidation() async {
  let url = URL(fileURLWithPath: "/tmp/FolderSourceBookmarkReturnCancellation", isDirectory: true)
  let accessor = FolderSourceCancellationResourceAccessor(
    bookmarkCancelsAndReturns: true
  )
  let identity = folderSourceCancellationRuntimeIdentity()
  let runtimeIdentityReader = FolderSourceCancellationRuntimeIdentityReader(
    values: [identity, identity]
  )
  let factory = folderSourceCancellationFactory(
    accessor: accessor,
    runtimeIdentityReader: runtimeIdentityReader
  )

  await expectFolderSourceCancellation(factory: factory, url: url)

  let counts = await accessor.counts()
  #expect(counts.bookmarks == 1)
  #expect(await runtimeIdentityReader.calls() == 1)
}

@Test
func cancellationObservedAfterFinalRuntimeIdentityPreventsSourceReturn() async {
  let url = URL(fileURLWithPath: "/tmp/FolderSourceFinalRuntimeCancellation", isDirectory: true)
  let accessor = FolderSourceCancellationResourceAccessor()
  let identity = folderSourceCancellationRuntimeIdentity()
  let runtimeIdentityReader = FolderSourceCancellationRuntimeIdentityReader(
    values: [identity, identity],
    cancelAndReturnOnCall: 2
  )
  let factory = folderSourceCancellationFactory(
    accessor: accessor,
    runtimeIdentityReader: runtimeIdentityReader
  )

  await expectFolderSourceCancellation(factory: factory, url: url)

  #expect(await runtimeIdentityReader.calls() == 2)
  let counts = await accessor.counts()
  #expect(counts.bookmarks == 1)
  #expect(counts.persistentIdentities == 1)
}

@Test
func finalFingerprintCancellationPreventsSourceReturn() async {
  let url = URL(fileURLWithPath: "/tmp/FolderSourceFinalFingerprintCancellation", isDirectory: true)
  let accessor = FolderSourceCancellationResourceAccessor(
    fingerprintThrowCancellationOnCall: 2
  )
  let runtimeIdentityReader = FolderSourceCancellationRuntimeIdentityReader(values: [nil])
  let factory = folderSourceCancellationFactory(
    accessor: accessor,
    runtimeIdentityReader: runtimeIdentityReader
  )

  await expectFolderSourceCancellation(factory: factory, url: url)

  let counts = await accessor.counts()
  #expect(counts.fingerprints == 2)
  #expect(counts.bookmarks == 1)
  #expect(counts.persistentIdentities == 1)
}

@Test
func finalPersistentIdentityCancellationPreventsSourceReturn() async {
  let url = URL(fileURLWithPath: "/tmp/FolderSourceFinalPersistentCancellation", isDirectory: true)
  let accessor = FolderSourceCancellationResourceAccessor(
    persistentThrowCancellationOnCall: 2
  )
  let identity = folderSourceCancellationRuntimeIdentity()
  let runtimeIdentityReader = FolderSourceCancellationRuntimeIdentityReader(
    values: [identity, identity]
  )
  let factory = folderSourceCancellationFactory(
    accessor: accessor,
    runtimeIdentityReader: runtimeIdentityReader
  )

  await expectFolderSourceCancellation(factory: factory, url: url)

  let counts = await accessor.counts()
  #expect(counts.persistentIdentities == 2)
  #expect(counts.bookmarks == 1)
  #expect(await runtimeIdentityReader.calls() == 2)
}

@Test
func ordinaryPersistentIdentityFailureRemainsOptional() async throws {
  let url = URL(fileURLWithPath: "/tmp/FolderSourceOptionalPersistentFailure", isDirectory: true)
  let accessor = FolderSourceCancellationResourceAccessor(
    persistentThrowsOrdinaryError: true
  )
  let identity = folderSourceCancellationRuntimeIdentity()
  let runtimeIdentityReader = FolderSourceCancellationRuntimeIdentityReader(
    values: [identity, identity]
  )
  let factory = folderSourceCancellationFactory(
    accessor: accessor,
    runtimeIdentityReader: runtimeIdentityReader
  )

  let source = try await factory.createSource(for: url)

  #expect(source.bookmarkData == Data([7, 8, 9]))
  #expect(source.lastKnownPath == url.standardizedFileURL.path)
  #expect(source.persistentIdentity == nil)
  let counts = await accessor.counts()
  #expect(counts.persistentIdentities == 2)
  #expect(counts.bookmarks == 1)
}

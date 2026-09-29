import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import SchneeGlassPOSIXSupport
import Testing

@testable import SchneeGlassFileSystemAdapter

private enum SecurityScopedAccessCancellationStage: Sendable {
  case none
  case resolve
  case startAndReturn
  case fingerprint
  case persistentIdentity
  case createBookmark
  case refreshedFingerprint
  case refreshedPersistentIdentity
}

private actor CancellationSecurityScopedResourceAccessor: SecurityScopedResourceAccessing {
  private let url: URL
  private let isStale: Bool
  private let stage: SecurityScopedAccessCancellationStage
  private var resolveCount = 0
  private var startCount = 0
  private var stopCount = 0
  private var fingerprintCount = 0
  private var persistentIdentityCount = 0
  private var createBookmarkCount = 0

  init(
    url: URL,
    isStale: Bool = false,
    stage: SecurityScopedAccessCancellationStage = .none
  ) {
    self.url = url
    self.isStale = isStale
    self.stage = stage
  }

  func resolveBookmark(_ data: Data) async throws -> ResolvedSecurityScopedResource {
    _ = data
    resolveCount += 1
    if stage == .resolve {
      throw CancellationError()
    }
    return ResolvedSecurityScopedResource(url: url, isStale: isStale)
  }

  func createBookmark(for url: URL) async throws -> Data {
    _ = url
    createBookmarkCount += 1
    if stage == .createBookmark {
      throw CancellationError()
    }
    return Data([9])
  }

  func startAccessing(_ url: URL) async -> Bool {
    _ = url
    startCount += 1
    if stage == .startAndReturn {
      withUnsafeCurrentTask { task in
        task?.cancel()
      }
    }
    return true
  }

  func stopAccessing(_ url: URL) async {
    _ = url
    stopCount += 1
  }

  func fingerprint(for url: URL) async throws -> ResourceFingerprint? {
    _ = url
    fingerprintCount += 1
    if stage == .fingerprint && fingerprintCount == 1 {
      throw CancellationError()
    }
    if stage == .refreshedFingerprint && fingerprintCount == 2 {
      throw CancellationError()
    }
    return ResourceFingerprint(
      volumeIdentifier: "volume-a",
      resourceIdentifier: "folder-a"
    )
  }

  func persistentIdentity(for url: URL) async throws -> PersistentFolderIdentity? {
    _ = url
    persistentIdentityCount += 1
    if stage == .persistentIdentity && persistentIdentityCount == 1 {
      throw CancellationError()
    }
    if stage == .refreshedPersistentIdentity && persistentIdentityCount == 2 {
      throw CancellationError()
    }
    return PersistentFolderIdentity(
      volumeUUIDString: "volume-uuid-a",
      documentIdentifier: 41
    )
  }

  func counts() -> (
    resolves: Int,
    starts: Int,
    stops: Int,
    fingerprints: Int,
    persistentIdentities: Int,
    bookmarkCreates: Int
  ) {
    (
      resolveCount,
      startCount,
      stopCount,
      fingerprintCount,
      persistentIdentityCount,
      createBookmarkCount
    )
  }
}

private actor CancellationRuntimeDirectoryIdentityReader: RuntimeDirectoryIdentityReading {
  func identity(for url: URL) async -> POSIXDirectoryIdentity? {
    _ = url
    return nil
  }
}

private func securityScopedCancellationSource(
  path: String = "/tmp/SchneeGlassCancellation"
) -> FolderSource {
  FolderSource(
    bookmarkData: Data([1]),
    lastKnownPath: path
  )
}

private func securityScopedCancellationCoordinator(
  accessor: CancellationSecurityScopedResourceAccessor
) -> SecurityScopedAccessCoordinator {
  SecurityScopedAccessCoordinator(
    resourceAccessor: accessor,
    runtimeIdentityReader: CancellationRuntimeDirectoryIdentityReader()
  )
}

private func expectSecurityScopedAcquireCancellation(
  coordinator: SecurityScopedAccessCoordinator,
  source: FolderSource
) async {
  let task = Task {
    try await coordinator.acquire(
      source: source,
      glassID: GlassID()
    )
  }

  do {
    _ = try await task.value
    Issue.record("Expected security-scoped access cancellation")
  } catch is CancellationError {
  } catch {
    Issue.record("Expected CancellationError, got \(error)")
  }
}

@Test
func preCancelledSecurityScopedAcquireStopsBeforeBookmarkResolution() async {
  let url = URL(fileURLWithPath: "/tmp/SchneeGlassPreCancelled", isDirectory: true)
  let accessor = CancellationSecurityScopedResourceAccessor(url: url)
  let coordinator = securityScopedCancellationCoordinator(accessor: accessor)
  let source = securityScopedCancellationSource(path: url.path)

  let task = Task {
    withUnsafeCurrentTask { current in
      current?.cancel()
    }
    return try await coordinator.acquire(
      source: source,
      glassID: GlassID()
    )
  }

  do {
    _ = try await task.value
    Issue.record("Expected security-scoped access cancellation")
  } catch is CancellationError {
  } catch {
    Issue.record("Expected CancellationError, got \(error)")
  }

  let counts = await accessor.counts()
  #expect(counts.resolves == 0)
  #expect(counts.starts == 0)
  #expect(counts.stops == 0)
}

@Test
func bookmarkResolutionCancellationIsNotMappedToAccessFailure() async {
  let url = URL(fileURLWithPath: "/tmp/SchneeGlassResolveCancellation", isDirectory: true)
  let accessor = CancellationSecurityScopedResourceAccessor(
    url: url,
    stage: .resolve
  )
  let coordinator = securityScopedCancellationCoordinator(accessor: accessor)

  await expectSecurityScopedAcquireCancellation(
    coordinator: coordinator,
    source: securityScopedCancellationSource(path: url.path)
  )

  let counts = await accessor.counts()
  #expect(counts.resolves == 1)
  #expect(counts.starts == 0)
  #expect(counts.stops == 0)
}

@Test
func cancellationObservedAfterStartingSecurityScopeStopsAccessExactlyOnce() async {
  let url = URL(fileURLWithPath: "/tmp/SchneeGlassStartCancellation", isDirectory: true)
  let accessor = CancellationSecurityScopedResourceAccessor(
    url: url,
    stage: .startAndReturn
  )
  let coordinator = securityScopedCancellationCoordinator(accessor: accessor)

  await expectSecurityScopedAcquireCancellation(
    coordinator: coordinator,
    source: securityScopedCancellationSource(path: url.path)
  )

  let counts = await accessor.counts()
  #expect(counts.starts == 1)
  #expect(counts.stops == 1)
  #expect(counts.fingerprints == 0)
}

@Test
func fingerprintCancellationStopsSecurityScopeExactlyOnce() async {
  let url = URL(fileURLWithPath: "/tmp/SchneeGlassFingerprintCancellation", isDirectory: true)
  let accessor = CancellationSecurityScopedResourceAccessor(
    url: url,
    stage: .fingerprint
  )
  let coordinator = securityScopedCancellationCoordinator(accessor: accessor)

  await expectSecurityScopedAcquireCancellation(
    coordinator: coordinator,
    source: securityScopedCancellationSource(path: url.path)
  )

  let counts = await accessor.counts()
  #expect(counts.fingerprints == 1)
  #expect(counts.stops == 1)
}

@Test
func persistentIdentityCancellationStopsSecurityScopeExactlyOnce() async {
  let url = URL(fileURLWithPath: "/tmp/SchneeGlassIdentityCancellation", isDirectory: true)
  let accessor = CancellationSecurityScopedResourceAccessor(
    url: url,
    stage: .persistentIdentity
  )
  let coordinator = securityScopedCancellationCoordinator(accessor: accessor)

  await expectSecurityScopedAcquireCancellation(
    coordinator: coordinator,
    source: securityScopedCancellationSource(path: url.path)
  )

  let counts = await accessor.counts()
  #expect(counts.persistentIdentities == 1)
  #expect(counts.stops == 1)
}

@Test
func staleBookmarkRefreshCancellationStopsSecurityScopeExactlyOnce() async {
  let url = URL(fileURLWithPath: "/tmp/SchneeGlassBookmarkRefreshCancellation", isDirectory: true)
  let accessor = CancellationSecurityScopedResourceAccessor(
    url: url,
    isStale: true,
    stage: .createBookmark
  )
  let coordinator = securityScopedCancellationCoordinator(accessor: accessor)

  await expectSecurityScopedAcquireCancellation(
    coordinator: coordinator,
    source: securityScopedCancellationSource(path: url.path)
  )

  let counts = await accessor.counts()
  #expect(counts.bookmarkCreates == 1)
  #expect(counts.stops == 1)
}

@Test
func refreshedFingerprintCancellationStopsSecurityScopeExactlyOnce() async {
  let url = URL(fileURLWithPath: "/tmp/SchneeGlassRefingerprintCancellation", isDirectory: true)
  let accessor = CancellationSecurityScopedResourceAccessor(
    url: url,
    isStale: true,
    stage: .refreshedFingerprint
  )
  let coordinator = securityScopedCancellationCoordinator(accessor: accessor)

  await expectSecurityScopedAcquireCancellation(
    coordinator: coordinator,
    source: securityScopedCancellationSource(path: url.path)
  )

  let counts = await accessor.counts()
  #expect(counts.fingerprints == 2)
  #expect(counts.stops == 1)
}

@Test
func refreshedPersistentIdentityCancellationStopsSecurityScopeExactlyOnce() async {
  let url = URL(fileURLWithPath: "/tmp/SchneeGlassReidentityCancellation", isDirectory: true)
  let accessor = CancellationSecurityScopedResourceAccessor(
    url: url,
    isStale: true,
    stage: .refreshedPersistentIdentity
  )
  let coordinator = securityScopedCancellationCoordinator(accessor: accessor)

  await expectSecurityScopedAcquireCancellation(
    coordinator: coordinator,
    source: securityScopedCancellationSource(path: url.path)
  )

  let counts = await accessor.counts()
  #expect(counts.persistentIdentities == 2)
  #expect(counts.stops == 1)
}

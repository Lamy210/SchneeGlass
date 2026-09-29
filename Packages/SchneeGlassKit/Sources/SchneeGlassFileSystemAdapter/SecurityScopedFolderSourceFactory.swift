import Foundation
import SchneeGlassApplication
import SchneeGlassDomain

public actor SecurityScopedFolderSourceFactory: FolderSourceCreating {
  private let resourceAccessor: any SecurityScopedResourceAccessing
  private let runtimeIdentityReader: any RuntimeDirectoryIdentityReading

  public init() {
    self.resourceAccessor = FoundationSecurityScopedResourceAccessor()
    self.runtimeIdentityReader = POSIXRuntimeDirectoryIdentityReader()
  }

  init(
    resourceAccessor: any SecurityScopedResourceAccessing,
    runtimeIdentityReader: any RuntimeDirectoryIdentityReading =
      POSIXRuntimeDirectoryIdentityReader()
  ) {
    self.resourceAccessor = resourceAccessor
    self.runtimeIdentityReader = runtimeIdentityReader
  }

  public func createSource(for selectedURL: URL) async throws -> FolderSource {
    try Task.checkCancellation()

    let url = selectedURL.standardizedFileURL
    let initialRuntimeIdentity = await runtimeIdentityReader.identity(for: url)
    try Task.checkCancellation()

    let initialFallbackFingerprint: ResourceFingerprint?
    if initialRuntimeIdentity == nil {
      initialFallbackFingerprint = try await requiredFingerprint(for: url)
    } else {
      initialFallbackFingerprint = nil
    }

    let initialPersistentIdentity = try await optionalPersistentIdentity(for: url)

    let bookmarkData: Data
    do {
      bookmarkData = try await resourceAccessor.createBookmark(for: url)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      try Task.checkCancellation()
      throw FolderSourceCreationError.bookmarkCreationFailed
    }
    try Task.checkCancellation()

    // Bookmark creation is an async boundary. Prefer descriptor-derived POSIX identity so a
    // pathname replacement cannot bind the new bookmark to a different physical directory. If
    // descriptor identity is unavailable, retain the existing Foundation resource-ID fallback.
    if let initialRuntimeIdentity {
      let finalRuntimeIdentity = await runtimeIdentityReader.identity(for: url)
      try Task.checkCancellation()

      guard
        let finalRuntimeIdentity,
        finalRuntimeIdentity == initialRuntimeIdentity
      else {
        throw FolderSourceCreationError.resourceIdentityUnavailable
      }
    } else {
      let finalFingerprint = try await requiredFingerprint(for: url)
      guard finalFingerprint == initialFallbackFingerprint else {
        throw FolderSourceCreationError.resourceIdentityUnavailable
      }
    }

    let finalPersistentIdentity = try await optionalPersistentIdentity(for: url)
    if let initialPersistentIdentity,
      let finalPersistentIdentity,
      initialPersistentIdentity != finalPersistentIdentity
    {
      throw FolderSourceCreationError.resourceIdentityUnavailable
    }

    try Task.checkCancellation()

    // Runtime identity belongs to FolderAccessHandle, not persisted FolderSource. Keeping this
    // value nil also ensures the in-memory configuration is equal to what its Codable form
    // actually stores, which is required by optimistic configuration concurrency.
    return FolderSource(
      bookmarkData: bookmarkData,
      lastKnownPath: url.path,
      persistentIdentity: finalPersistentIdentity
    )
  }

  private func requiredFingerprint(for url: URL) async throws -> ResourceFingerprint {
    try Task.checkCancellation()

    let observedFingerprint: ResourceFingerprint?
    do {
      observedFingerprint = try await resourceAccessor.fingerprint(for: url)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      try Task.checkCancellation()
      throw FolderSourceCreationError.resourceIdentityUnavailable
    }

    try Task.checkCancellation()

    guard
      let observedFingerprint,
      observedFingerprint.resourceIdentifier != nil
    else {
      throw FolderSourceCreationError.resourceIdentityUnavailable
    }
    return observedFingerprint
  }

  private func optionalPersistentIdentity(
    for url: URL
  ) async throws -> PersistentFolderIdentity? {
    try Task.checkCancellation()

    do {
      let identity = try await resourceAccessor.persistentIdentity(for: url)
      try Task.checkCancellation()
      return identity
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      try Task.checkCancellation()

      // Persistent metadata is an optional supplement to the security-scoped bookmark. Some
      // filesystems do not expose it; source creation must remain available there.
      return nil
    }
  }
}

import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing
@testable import SchneeGlassFileSystemAdapter

private actor RefreshIdentityResourceAccessor: SecurityScopedResourceAccessing {
    private let resolvedURL: URL
    private let fingerprints: [ResourceFingerprint?]
    private var fingerprintIndex = 0
    private var stopCounter = 0
    private var bookmarkCounter = 0

    init(
        resolvedURL: URL,
        fingerprints: [ResourceFingerprint?]
    ) {
        self.resolvedURL = resolvedURL
        self.fingerprints = fingerprints
    }

    func resolveBookmark(_ data: Data) async throws -> ResolvedSecurityScopedResource {
        _ = data
        return ResolvedSecurityScopedResource(url: resolvedURL, isStale: true)
    }

    func createBookmark(for url: URL) async throws -> Data {
        _ = url
        bookmarkCounter += 1
        return Data([0x02])
    }

    func startAccessing(_ url: URL) async -> Bool {
        _ = url
        return true
    }

    func stopAccessing(_ url: URL) async {
        _ = url
        stopCounter += 1
    }

    func fingerprint(for url: URL) async throws -> ResourceFingerprint? {
        _ = url
        guard !fingerprints.isEmpty else {
            return nil
        }
        let index = min(fingerprintIndex, fingerprints.count - 1)
        fingerprintIndex += 1
        return fingerprints[index]
    }

    func counters() -> (fingerprints: Int, bookmarks: Int, stops: Int) {
        (fingerprintIndex, bookmarkCounter, stopCounter)
    }
}

private func refreshIdentitySource(
    at url: URL,
    fingerprint: ResourceFingerprint?
) -> FolderSource {
    FolderSource(
        bookmarkData: Data([0x01]),
        lastKnownPath: url.path,
        fingerprint: fingerprint
    )
}

@Test
func staleBookmarkRefreshRejectsResourceReplacementAndStopsScope() async {
    let url = URL(fileURLWithPath: "/tmp/schneeglass-refresh-replacement", isDirectory: true)
    let before = ResourceFingerprint(
        volumeIdentifier: "volume-a",
        resourceIdentifier: "folder-a"
    )
    let after = ResourceFingerprint(
        volumeIdentifier: "volume-a",
        resourceIdentifier: "folder-b"
    )
    let accessor = RefreshIdentityResourceAccessor(
        resolvedURL: url,
        fingerprints: [before, after]
    )
    let coordinator = SecurityScopedAccessCoordinator(resourceAccessor: accessor)

    do {
        _ = try await coordinator.acquire(
            source: refreshIdentitySource(at: url, fingerprint: before),
            glassID: GlassID()
        )
        Issue.record("Expected stale bookmark refresh replacement detection")
    } catch let error as FolderAccessError {
        #expect(error == .resourceReplacementDetected)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    let counters = await accessor.counters()
    #expect(counters.fingerprints == 2)
    #expect(counters.bookmarks == 1)
    #expect(counters.stops == 1)
}

@Test
func staleBookmarkRefreshFailsWhenObservedIdentityDisappears() async {
    let url = URL(fileURLWithPath: "/tmp/schneeglass-refresh-identity-missing", isDirectory: true)
    let fingerprint = ResourceFingerprint(
        volumeIdentifier: "volume-a",
        resourceIdentifier: "folder-a"
    )
    let accessor = RefreshIdentityResourceAccessor(
        resolvedURL: url,
        fingerprints: [fingerprint, nil]
    )
    let coordinator = SecurityScopedAccessCoordinator(resourceAccessor: accessor)

    do {
        _ = try await coordinator.acquire(
            source: refreshIdentitySource(at: url, fingerprint: fingerprint),
            glassID: GlassID()
        )
        Issue.record("Expected stale bookmark refresh identity failure")
    } catch let error as FolderAccessError {
        #expect(error == .bookmarkResolutionFailed)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    let counters = await accessor.counters()
    #expect(counters.fingerprints == 2)
    #expect(counters.bookmarks == 1)
    #expect(counters.stops == 1)
}

@Test
func staleLegacyBookmarkWithoutObservedIdentityKeepsCompatibility() async throws {
    let url = URL(fileURLWithPath: "/tmp/schneeglass-refresh-legacy", isDirectory: true)
    let accessor = RefreshIdentityResourceAccessor(
        resolvedURL: url,
        fingerprints: [nil]
    )
    let coordinator = SecurityScopedAccessCoordinator(resourceAccessor: accessor)

    let acquisition = try await coordinator.acquire(
        source: refreshIdentitySource(at: url, fingerprint: nil),
        glassID: GlassID()
    )

    #expect(acquisition.refreshedSource?.bookmarkData == Data([0x02]))
    #expect(acquisition.refreshedSource?.fingerprint == nil)
    #expect(acquisition.handle.fingerprint == nil)

    let beforeRelease = await accessor.counters()
    #expect(beforeRelease.fingerprints == 1)
    #expect(beforeRelease.bookmarks == 1)
    #expect(beforeRelease.stops == 0)

    await coordinator.release(handleID: acquisition.handle.id)
    #expect(await accessor.counters().stops == 1)
}

@Test
func staleLegacyVolumeOnlyBookmarkKeepsCompatibilityWithoutFalseFolderProof() async throws {
    let url = URL(fileURLWithPath: "/tmp/schneeglass-refresh-volume-only", isDirectory: true)
    let volumeOnly = ResourceFingerprint(
        volumeIdentifier: "volume-a",
        resourceIdentifier: nil
    )
    let accessor = RefreshIdentityResourceAccessor(
        resolvedURL: url,
        fingerprints: [volumeOnly]
    )
    let coordinator = SecurityScopedAccessCoordinator(resourceAccessor: accessor)

    let acquisition = try await coordinator.acquire(
        source: refreshIdentitySource(at: url, fingerprint: volumeOnly),
        glassID: GlassID()
    )

    #expect(acquisition.refreshedSource?.fingerprint == volumeOnly)
    #expect(acquisition.handle.fingerprint == volumeOnly)

    let beforeRelease = await accessor.counters()
    #expect(beforeRelease.fingerprints == 1)
    #expect(beforeRelease.bookmarks == 1)
    #expect(beforeRelease.stops == 0)

    await coordinator.release(handleID: acquisition.handle.id)
    #expect(await accessor.counters().stops == 1)
}

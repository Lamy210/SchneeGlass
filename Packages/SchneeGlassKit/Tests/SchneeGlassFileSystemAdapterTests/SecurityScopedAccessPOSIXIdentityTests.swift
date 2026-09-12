import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import SchneeGlassPOSIXSupport
import Testing
@testable import SchneeGlassFileSystemAdapter

private actor POSIXIdentityTestResourceAccessor: SecurityScopedResourceAccessing {
    private let resolvedURL: URL
    private var stopCounter = 0
    private var bookmarkCounter = 0
    private var fingerprintCounter = 0

    init(resolvedURL: URL) {
        self.resolvedURL = resolvedURL
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
        fingerprintCounter += 1
        return ResourceFingerprint(
            volumeIdentifier: "foundation-volume-should-not-be-read",
            resourceIdentifier: "foundation-resource-should-not-be-read"
        )
    }

    func persistentIdentity(for url: URL) async throws -> PersistentFolderIdentity? {
        _ = url
        return nil
    }

    func counters() -> (stops: Int, bookmarks: Int, fingerprints: Int) {
        (stopCounter, bookmarkCounter, fingerprintCounter)
    }
}

private actor SequenceRuntimeDirectoryIdentityReader: RuntimeDirectoryIdentityReading {
    private let values: [POSIXDirectoryIdentity?]
    private var index = 0

    init(_ values: [POSIXDirectoryIdentity?]) {
        self.values = values
    }

    func identity(for url: URL) async -> POSIXDirectoryIdentity? {
        _ = url
        guard !values.isEmpty else {
            return nil
        }
        let current = min(index, values.count - 1)
        index += 1
        return values[current]
    }
}

private func runtimeDirectoryIdentity(
    device: UInt64 = 7,
    inode: UInt64
) -> POSIXDirectoryIdentity {
    POSIXDirectoryIdentity(device: device, inode: inode)
}

@Test
func staleBookmarkRefreshRejectsPOSIXDirectoryReplacementWithoutFoundationFingerprint() async {
    let url = URL(fileURLWithPath: "/tmp/schneeglass-posix-refresh-replacement", isDirectory: true)
    let accessor = POSIXIdentityTestResourceAccessor(resolvedURL: url)
    let identityReader = SequenceRuntimeDirectoryIdentityReader([
        runtimeDirectoryIdentity(inode: 41),
        runtimeDirectoryIdentity(inode: 99),
    ])
    let coordinator = SecurityScopedAccessCoordinator(
        resourceAccessor: accessor,
        runtimeIdentityReader: identityReader
    )

    do {
        _ = try await coordinator.acquire(
            source: FolderSource(bookmarkData: Data([0x01]), lastKnownPath: url.path),
            glassID: GlassID()
        )
        Issue.record("Expected POSIX directory replacement detection")
    } catch let error as FolderAccessError {
        #expect(error == .resourceReplacementDetected)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    let counters = await accessor.counters()
    #expect(counters.bookmarks == 1)
    #expect(counters.stops == 1)
    #expect(counters.fingerprints == 0)
}

@Test
func staleBookmarkRefreshFailsClosedWhenPOSIXIdentityDisappears() async {
    let url = URL(fileURLWithPath: "/tmp/schneeglass-posix-refresh-missing", isDirectory: true)
    let accessor = POSIXIdentityTestResourceAccessor(resolvedURL: url)
    let identityReader = SequenceRuntimeDirectoryIdentityReader([
        runtimeDirectoryIdentity(inode: 41),
        nil,
    ])
    let coordinator = SecurityScopedAccessCoordinator(
        resourceAccessor: accessor,
        runtimeIdentityReader: identityReader
    )

    do {
        _ = try await coordinator.acquire(
            source: FolderSource(bookmarkData: Data([0x01]), lastKnownPath: url.path),
            glassID: GlassID()
        )
        Issue.record("Expected missing POSIX identity to fail closed")
    } catch let error as FolderAccessError {
        #expect(error == .bookmarkResolutionFailed)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    let counters = await accessor.counters()
    #expect(counters.bookmarks == 1)
    #expect(counters.stops == 1)
    #expect(counters.fingerprints == 0)
}

@Test
func staleBookmarkRefreshAcceptsStablePOSIXIdentityWithoutFoundationFingerprintRead() async throws {
    let url = URL(fileURLWithPath: "/tmp/schneeglass-posix-refresh-stable", isDirectory: true)
    let accessor = POSIXIdentityTestResourceAccessor(resolvedURL: url)
    let identity = runtimeDirectoryIdentity(inode: 41)
    let identityReader = SequenceRuntimeDirectoryIdentityReader([identity, identity])
    let coordinator = SecurityScopedAccessCoordinator(
        resourceAccessor: accessor,
        runtimeIdentityReader: identityReader
    )

    let acquisition = try await coordinator.acquire(
        source: FolderSource(bookmarkData: Data([0x01]), lastKnownPath: url.path),
        glassID: GlassID()
    )

    #expect(acquisition.refreshedSource?.bookmarkData == Data([0x02]))
    #expect(acquisition.handle.fingerprint == nil)
    #expect(acquisition.handle.runtimeDirectoryIdentity == RuntimeDirectoryIdentity(
        deviceIdentifier: identity.device,
        objectIdentifier: identity.inode
    ))

    let beforeRelease = await accessor.counters()
    #expect(beforeRelease.stops == 0)
    #expect(beforeRelease.fingerprints == 0)

    await coordinator.release(handleID: acquisition.handle.id)
    let afterRelease = await accessor.counters()
    #expect(afterRelease.stops == 1)
    #expect(afterRelease.fingerprints == 0)
}

import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing
@testable import SchneeGlassFileSystemAdapter

private actor FakeSecurityScopedResourceAccessor: SecurityScopedResourceAccessing {
    let resolvedResource: ResolvedSecurityScopedResource
    let startResult: Bool
    let fingerprintValue: ResourceFingerprint?
    let refreshedBookmarkData: Data

    private var stopCalls = 0
    private var createBookmarkCalls = 0

    init(
        resolvedURL: URL,
        isStale: Bool = false,
        startResult: Bool = true,
        fingerprintValue: ResourceFingerprint? = nil,
        refreshedBookmarkData: Data = Data([0x42])
    ) {
        self.resolvedResource = ResolvedSecurityScopedResource(
            url: resolvedURL,
            isStale: isStale
        )
        self.startResult = startResult
        self.fingerprintValue = fingerprintValue
        self.refreshedBookmarkData = refreshedBookmarkData
    }

    func resolveBookmark(_ data: Data) async throws -> ResolvedSecurityScopedResource {
        resolvedResource
    }

    func createBookmark(for url: URL) async throws -> Data {
        createBookmarkCalls += 1
        return refreshedBookmarkData
    }

    func startAccessing(_ url: URL) async -> Bool {
        startResult
    }

    func stopAccessing(_ url: URL) async {
        stopCalls += 1
    }

    func fingerprint(for url: URL) async throws -> ResourceFingerprint? {
        fingerprintValue
    }

    func counters() -> (stopCalls: Int, createBookmarkCalls: Int) {
        (stopCalls, createBookmarkCalls)
    }
}

@Test
func acquireAndReleaseBalancesSecurityScope() async throws {
    let url = URL(fileURLWithPath: "/tmp/schneeglass-security-scope", isDirectory: true)
    let fingerprint = ResourceFingerprint(
        volumeIdentifier: "volume-a",
        resourceIdentifier: "folder-a"
    )
    let accessor = FakeSecurityScopedResourceAccessor(
        resolvedURL: url,
        fingerprintValue: fingerprint
    )
    let coordinator = SecurityScopedAccessCoordinator(resourceAccessor: accessor)
    let source = FolderSource(
        bookmarkData: Data([0x01]),
        lastKnownPath: url.path,
        fingerprint: fingerprint
    )

    let acquisition = try await coordinator.acquire(
        source: source,
        glassID: GlassID()
    )

    #expect(acquisition.handle.url == url)
    #expect(acquisition.handle.fingerprint == fingerprint)
    #expect(acquisition.refreshedSource == nil)

    await coordinator.release(handleID: acquisition.handle.id)
    let counters = await accessor.counters()
    #expect(counters.stopCalls == 1)
}

@Test
func duplicateReleaseDoesNotStopSecurityScopeTwice() async throws {
    let url = URL(fileURLWithPath: "/tmp/schneeglass-duplicate-release", isDirectory: true)
    let accessor = FakeSecurityScopedResourceAccessor(resolvedURL: url)
    let coordinator = SecurityScopedAccessCoordinator(resourceAccessor: accessor)
    let acquisition = try await coordinator.acquire(
        source: FolderSource(bookmarkData: Data([0x01]), lastKnownPath: url.path),
        glassID: GlassID()
    )

    await coordinator.release(handleID: acquisition.handle.id)
    await coordinator.release(handleID: acquisition.handle.id)

    let counters = await accessor.counters()
    #expect(counters.stopCalls == 1)
}

@Test
func staleBookmarkReturnsRefreshedSource() async throws {
    let url = URL(fileURLWithPath: "/tmp/schneeglass-stale-bookmark", isDirectory: true)
    let refreshedBookmark = Data([0xAA, 0xBB])
    let fingerprint = ResourceFingerprint(
        volumeIdentifier: "volume-a",
        resourceIdentifier: "folder-a"
    )
    let accessor = FakeSecurityScopedResourceAccessor(
        resolvedURL: url,
        isStale: true,
        fingerprintValue: fingerprint,
        refreshedBookmarkData: refreshedBookmark
    )
    let coordinator = SecurityScopedAccessCoordinator(resourceAccessor: accessor)

    let acquisition = try await coordinator.acquire(
        source: FolderSource(bookmarkData: Data([0x01]), lastKnownPath: "/old/path"),
        glassID: GlassID()
    )

    #expect(acquisition.refreshedSource?.bookmarkData == refreshedBookmark)
    #expect(acquisition.refreshedSource?.lastKnownPath == url.path)
    #expect(acquisition.refreshedSource?.fingerprint == fingerprint)

    let counters = await accessor.counters()
    #expect(counters.createBookmarkCalls == 1)

    await coordinator.release(handleID: acquisition.handle.id)
}

@Test
func replacementDetectionStopsAccessBeforeThrowing() async {
    let url = URL(fileURLWithPath: "/tmp/schneeglass-replacement", isDirectory: true)
    let accessor = FakeSecurityScopedResourceAccessor(
        resolvedURL: url,
        fingerprintValue: ResourceFingerprint(
            volumeIdentifier: "volume-a",
            resourceIdentifier: "new-folder"
        )
    )
    let coordinator = SecurityScopedAccessCoordinator(resourceAccessor: accessor)
    let source = FolderSource(
        bookmarkData: Data([0x01]),
        lastKnownPath: url.path,
        fingerprint: ResourceFingerprint(
            volumeIdentifier: "volume-a",
            resourceIdentifier: "old-folder"
        )
    )

    do {
        _ = try await coordinator.acquire(source: source, glassID: GlassID())
        Issue.record("Expected resource replacement detection")
    } catch let error as FolderAccessError {
        #expect(error == .resourceReplacementDetected)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    let counters = await accessor.counters()
    #expect(counters.stopCalls == 1)
}

@Test
func deniedAccessDoesNotCallStopAccessing() async {
    let url = URL(fileURLWithPath: "/tmp/schneeglass-denied-access", isDirectory: true)
    let accessor = FakeSecurityScopedResourceAccessor(
        resolvedURL: url,
        startResult: false
    )
    let coordinator = SecurityScopedAccessCoordinator(resourceAccessor: accessor)

    do {
        _ = try await coordinator.acquire(
            source: FolderSource(bookmarkData: Data([0x01]), lastKnownPath: url.path),
            glassID: GlassID()
        )
        Issue.record("Expected access denial")
    } catch let error as FolderAccessError {
        #expect(error == .accessDenied)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    let counters = await accessor.counters()
    #expect(counters.stopCalls == 0)
}

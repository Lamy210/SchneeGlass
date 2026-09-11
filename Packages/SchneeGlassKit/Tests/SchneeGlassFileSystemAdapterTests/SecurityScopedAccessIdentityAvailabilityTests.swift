import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing
@testable import SchneeGlassFileSystemAdapter

private actor IdentityAvailabilityResourceAccessor: SecurityScopedResourceAccessing {
    private let resolvedURL: URL
    private let fingerprintValue: ResourceFingerprint?
    private var stopCounter = 0

    init(
        resolvedURL: URL,
        fingerprintValue: ResourceFingerprint?
    ) {
        self.resolvedURL = resolvedURL
        self.fingerprintValue = fingerprintValue
    }

    func resolveBookmark(_ data: Data) async throws -> ResolvedSecurityScopedResource {
        _ = data
        return ResolvedSecurityScopedResource(url: resolvedURL, isStale: false)
    }

    func createBookmark(for url: URL) async throws -> Data {
        _ = url
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
        return fingerprintValue
    }

    func stopCount() -> Int {
        stopCounter
    }
}

@Test
func savedFolderIdentityMissingAtAccessTimeFailsClosedAndStopsScope() async {
    let url = URL(fileURLWithPath: "/tmp/schneeglass-identity-unavailable", isDirectory: true)
    let accessor = IdentityAvailabilityResourceAccessor(
        resolvedURL: url,
        fingerprintValue: nil
    )
    let coordinator = SecurityScopedAccessCoordinator(resourceAccessor: accessor)
    let source = FolderSource(
        bookmarkData: Data([0x01]),
        lastKnownPath: url.path,
        fingerprint: ResourceFingerprint(
            volumeIdentifier: "volume-a",
            resourceIdentifier: "folder-a"
        )
    )

    do {
        _ = try await coordinator.acquire(source: source, glassID: GlassID())
        Issue.record("Expected unverifiable saved identity to fail closed")
    } catch let error as FolderAccessError {
        #expect(error == .bookmarkResolutionFailed)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(await accessor.stopCount() == 1)
}

@Test
func missingExpectedIdentityDimensionFailsClosedBeforeAccessIsReturned() async {
    let url = URL(fileURLWithPath: "/tmp/schneeglass-partial-identity", isDirectory: true)
    let accessor = IdentityAvailabilityResourceAccessor(
        resolvedURL: url,
        fingerprintValue: ResourceFingerprint(
            volumeIdentifier: "volume-a",
            resourceIdentifier: nil
        )
    )
    let coordinator = SecurityScopedAccessCoordinator(resourceAccessor: accessor)
    let source = FolderSource(
        bookmarkData: Data([0x01]),
        lastKnownPath: url.path,
        fingerprint: ResourceFingerprint(
            volumeIdentifier: "volume-a",
            resourceIdentifier: "folder-a"
        )
    )

    do {
        _ = try await coordinator.acquire(source: source, glassID: GlassID())
        Issue.record("Expected incomplete identity comparison to fail closed")
    } catch let error as FolderAccessError {
        #expect(error == .bookmarkResolutionFailed)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(await accessor.stopCount() == 1)
}

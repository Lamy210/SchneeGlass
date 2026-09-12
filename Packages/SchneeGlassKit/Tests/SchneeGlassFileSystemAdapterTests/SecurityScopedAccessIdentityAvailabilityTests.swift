import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing
@testable import SchneeGlassFileSystemAdapter

private enum IdentityAvailabilityTestError: Error, Sendable {
    case injected
}

private actor IdentityAvailabilityResourceAccessor: SecurityScopedResourceAccessing {
    private let resolvedURL: URL
    private let fingerprintValue: ResourceFingerprint?
    private let persistentIdentityValue: PersistentFolderIdentity?
    private let persistentIdentityThrows: Bool
    private var stopCounter = 0

    init(
        resolvedURL: URL,
        fingerprintValue: ResourceFingerprint? = nil,
        persistentIdentityValue: PersistentFolderIdentity? = nil,
        persistentIdentityThrows: Bool = false
    ) {
        self.resolvedURL = resolvedURL
        self.fingerprintValue = fingerprintValue
        self.persistentIdentityValue = persistentIdentityValue
        self.persistentIdentityThrows = persistentIdentityThrows
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

    func persistentIdentity(for url: URL) async throws -> PersistentFolderIdentity? {
        _ = url
        if persistentIdentityThrows {
            throw IdentityAvailabilityTestError.injected
        }
        return persistentIdentityValue
    }

    func stopCount() -> Int {
        stopCounter
    }
}

private func identityProtectedSource(at url: URL) -> FolderSource {
    FolderSource(
        bookmarkData: Data([0x01]),
        lastKnownPath: url.path,
        persistentIdentity: PersistentFolderIdentity(
            volumeUUIDString: "volume-uuid-a",
            documentIdentifier: 41
        )
    )
}

@Test
func savedPersistentFolderIdentityMissingAtAccessTimeFailsClosedAndStopsScope() async {
    let url = URL(fileURLWithPath: "/tmp/schneeglass-identity-unavailable", isDirectory: true)
    let accessor = IdentityAvailabilityResourceAccessor(resolvedURL: url)
    let coordinator = SecurityScopedAccessCoordinator(resourceAccessor: accessor)

    do {
        _ = try await coordinator.acquire(
            source: identityProtectedSource(at: url),
            glassID: GlassID()
        )
        Issue.record("Expected unverifiable saved persistent identity to fail closed")
    } catch let error as FolderAccessError {
        #expect(error == .bookmarkResolutionFailed)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(await accessor.stopCount() == 1)
}

@Test
func missingExpectedPersistentIdentityDimensionFailsClosedBeforeAccessIsReturned() async {
    let url = URL(fileURLWithPath: "/tmp/schneeglass-partial-identity", isDirectory: true)
    let accessor = IdentityAvailabilityResourceAccessor(
        resolvedURL: url,
        persistentIdentityValue: PersistentFolderIdentity(
            volumeUUIDString: "volume-uuid-a",
            documentIdentifier: nil
        )
    )
    let coordinator = SecurityScopedAccessCoordinator(resourceAccessor: accessor)

    do {
        _ = try await coordinator.acquire(
            source: identityProtectedSource(at: url),
            glassID: GlassID()
        )
        Issue.record("Expected incomplete persistent identity comparison to fail closed")
    } catch let error as FolderAccessError {
        #expect(error == .bookmarkResolutionFailed)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(await accessor.stopCount() == 1)
}

@Test
func persistentIdentityReadFailureForSavedProofFailsClosedAndStopsScope() async {
    let url = URL(fileURLWithPath: "/tmp/schneeglass-identity-read-failure", isDirectory: true)
    let accessor = IdentityAvailabilityResourceAccessor(
        resolvedURL: url,
        persistentIdentityThrows: true
    )
    let coordinator = SecurityScopedAccessCoordinator(resourceAccessor: accessor)

    do {
        _ = try await coordinator.acquire(
            source: identityProtectedSource(at: url),
            glassID: GlassID()
        )
        Issue.record("Expected persistent identity read failure to fail closed")
    } catch let error as FolderAccessError {
        #expect(error == .bookmarkResolutionFailed)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(await accessor.stopCount() == 1)
}

@Test
func persistentIdentityReadFailureWithoutSavedProofKeepsBookmarkCompatibility() async throws {
    let url = URL(fileURLWithPath: "/tmp/schneeglass-no-persistent-proof", isDirectory: true)
    let runtime = ResourceFingerprint(
        volumeIdentifier: "boot-volume",
        resourceIdentifier: "boot-folder"
    )
    let accessor = IdentityAvailabilityResourceAccessor(
        resolvedURL: url,
        fingerprintValue: runtime,
        persistentIdentityThrows: true
    )
    let coordinator = SecurityScopedAccessCoordinator(resourceAccessor: accessor)

    let acquisition = try await coordinator.acquire(
        source: FolderSource(bookmarkData: Data([0x01]), lastKnownPath: url.path),
        glassID: GlassID()
    )

    #expect(acquisition.handle.fingerprint == runtime)
    #expect(acquisition.refreshedSource == nil)
    #expect(await accessor.stopCount() == 0)

    await coordinator.release(handleID: acquisition.handle.id)
    #expect(await accessor.stopCount() == 1)
}

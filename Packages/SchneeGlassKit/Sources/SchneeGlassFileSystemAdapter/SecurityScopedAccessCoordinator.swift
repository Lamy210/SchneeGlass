import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import SchneeGlassPOSIXSupport

struct ResolvedSecurityScopedResource: Sendable {
    let url: URL
    let isStale: Bool
}

protocol SecurityScopedResourceAccessing: Sendable {
    func resolveBookmark(_ data: Data) async throws -> ResolvedSecurityScopedResource
    func createBookmark(for url: URL) async throws -> Data
    func startAccessing(_ url: URL) async -> Bool
    func stopAccessing(_ url: URL) async
    func fingerprint(for url: URL) async throws -> ResourceFingerprint?
    func persistentIdentity(for url: URL) async throws -> PersistentFolderIdentity?
}

extension SecurityScopedResourceAccessing {
    /// Test doubles and specialized accessors may not expose restart-safe metadata. Production's
    /// Foundation accessor overrides this method.
    func persistentIdentity(for url: URL) async throws -> PersistentFolderIdentity? {
        nil
    }
}

struct FoundationSecurityScopedResourceAccessor: SecurityScopedResourceAccessing {
    func resolveBookmark(_ data: Data) async throws -> ResolvedSecurityScopedResource {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return ResolvedSecurityScopedResource(url: url, isStale: isStale)
    }

    func createBookmark(for url: URL) async throws -> Data {
        try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    func startAccessing(_ url: URL) async -> Bool {
        url.startAccessingSecurityScopedResource()
    }

    func stopAccessing(_ url: URL) async {
        url.stopAccessingSecurityScopedResource()
    }

    func fingerprint(for url: URL) async throws -> ResourceFingerprint? {
        let values = try url.resourceValues(forKeys: [
            .volumeIdentifierKey,
            .fileResourceIdentifierKey,
        ])

        let volumeIdentifier = values.volumeIdentifier.map { String(describing: $0) }
        let resourceIdentifier = values.fileResourceIdentifier.map { String(describing: $0) }

        guard volumeIdentifier != nil || resourceIdentifier != nil else {
            return nil
        }

        return ResourceFingerprint(
            volumeIdentifier: volumeIdentifier,
            resourceIdentifier: resourceIdentifier
        )
    }

    func persistentIdentity(for url: URL) async throws -> PersistentFolderIdentity? {
        let values = try url.resourceValues(forKeys: [
            .volumeUUIDStringKey,
            .documentIdentifierKey,
        ])

        // A document identifier is unique only within its volume. Without the persistent volume UUID
        // it is not useful as a persisted comparison token, so omit the supplemental identity.
        guard let volumeUUIDString = values.volumeUUIDString else {
            return nil
        }

        return PersistentFolderIdentity(
            volumeUUIDString: volumeUUIDString,
            documentIdentifier: values.documentIdentifier
        )
    }
}

public actor SecurityScopedAccessCoordinator: FolderAccessControlling {
    private struct ActiveAccess: Sendable {
        let url: URL
    }

    private let resourceAccessor: any SecurityScopedResourceAccessing
    private let runtimeIdentityReader: any RuntimeDirectoryIdentityReading
    private var activeAccesses: [UUID: ActiveAccess] = [:]

    public init() {
        self.resourceAccessor = FoundationSecurityScopedResourceAccessor()
        self.runtimeIdentityReader = POSIXRuntimeDirectoryIdentityReader()
    }

    init(
        resourceAccessor: any SecurityScopedResourceAccessing,
        runtimeIdentityReader: any RuntimeDirectoryIdentityReading = POSIXRuntimeDirectoryIdentityReader()
    ) {
        self.resourceAccessor = resourceAccessor
        self.runtimeIdentityReader = runtimeIdentityReader
    }

    public func acquire(
        source: FolderSource,
        glassID: GlassID
    ) async throws -> FolderAccessAcquisition {
        let resolved: ResolvedSecurityScopedResource
        do {
            resolved = try await resourceAccessor.resolveBookmark(source.bookmarkData)
        } catch {
            throw FolderAccessError.bookmarkResolutionFailed
        }

        guard await resourceAccessor.startAccessing(resolved.url) else {
            throw FolderAccessError.accessDenied
        }

        let actualRuntimeDirectoryIdentity = await runtimeIdentityReader.identity(for: resolved.url)

        let actualFingerprint: ResourceFingerprint?
        do {
            actualFingerprint = try await resourceAccessor.fingerprint(for: resolved.url)
        } catch {
            actualFingerprint = nil
        }

        let actualPersistentIdentity: PersistentFolderIdentity?
        do {
            actualPersistentIdentity = try await resourceAccessor.persistentIdentity(for: resolved.url)
        } catch {
            // Restart-safe metadata is supplemental when no persisted proof exists. If a previous
            // configuration did persist such proof, inability to re-observe it must fail closed.
            if source.persistentIdentity != nil {
                await resourceAccessor.stopAccessing(resolved.url)
                throw FolderAccessError.bookmarkResolutionFailed
            }
            actualPersistentIdentity = nil
        }

        // A security-scoped bookmark is the primary persistent resource reference. When a source
        // also carries restart-safe metadata, every recorded dimension must still be observable and
        // equal. Boot-local fileResourceIdentifier/volumeIdentifier values are deliberately ignored.
        if Self.persistentIdentityVerificationIsUnavailable(
            expected: source.persistentIdentity,
            actual: actualPersistentIdentity
        ) {
            await resourceAccessor.stopAccessing(resolved.url)
            throw FolderAccessError.bookmarkResolutionFailed
        }

        if Self.representsPersistentReplacement(
            expected: source.persistentIdentity,
            actual: actualPersistentIdentity
        ) {
            await resourceAccessor.stopAccessing(resolved.url)
            throw FolderAccessError.resourceReplacementDetected
        }

        let refreshedSource: FolderSource?
        if resolved.isStale {
            let refreshedBookmark: Data
            do {
                refreshedBookmark = try await resourceAccessor.createBookmark(for: resolved.url)
            } catch {
                await resourceAccessor.stopAccessing(resolved.url)
                throw FolderAccessError.bookmarkResolutionFailed
            }

            // Prefer descriptor-derived POSIX identity around the bookmark refresh boundary. It
            // observes the opened directory object directly instead of depending on Foundation's
            // opaque identifiers. The Foundation fingerprint remains a compatibility fallback when
            // descriptor identity is unavailable on the current filesystem/location.
            if let actualRuntimeDirectoryIdentity {
                guard let refreshedRuntimeDirectoryIdentity = await runtimeIdentityReader.identity(for: resolved.url) else {
                    await resourceAccessor.stopAccessing(resolved.url)
                    throw FolderAccessError.bookmarkResolutionFailed
                }
                guard refreshedRuntimeDirectoryIdentity == actualRuntimeDirectoryIdentity else {
                    await resourceAccessor.stopAccessing(resolved.url)
                    throw FolderAccessError.resourceReplacementDetected
                }
            } else if actualFingerprint?.resourceIdentifier != nil {
                let refreshedFingerprint: ResourceFingerprint?
                do {
                    refreshedFingerprint = try await resourceAccessor.fingerprint(for: resolved.url)
                } catch {
                    await resourceAccessor.stopAccessing(resolved.url)
                    throw FolderAccessError.bookmarkResolutionFailed
                }

                if Self.runtimeIdentityVerificationIsUnavailable(
                    expected: actualFingerprint,
                    actual: refreshedFingerprint
                ) {
                    await resourceAccessor.stopAccessing(resolved.url)
                    throw FolderAccessError.bookmarkResolutionFailed
                }

                if Self.representsRuntimeReplacement(
                    expected: actualFingerprint,
                    actual: refreshedFingerprint
                ) {
                    await resourceAccessor.stopAccessing(resolved.url)
                    throw FolderAccessError.resourceReplacementDetected
                }
            }

            let refreshedPersistentIdentity: PersistentFolderIdentity?
            do {
                refreshedPersistentIdentity = try await resourceAccessor.persistentIdentity(for: resolved.url)
            } catch {
                if actualPersistentIdentity != nil {
                    await resourceAccessor.stopAccessing(resolved.url)
                    throw FolderAccessError.bookmarkResolutionFailed
                }
                refreshedPersistentIdentity = nil
            }

            if Self.persistentIdentityVerificationIsUnavailable(
                expected: actualPersistentIdentity,
                actual: refreshedPersistentIdentity
            ) {
                await resourceAccessor.stopAccessing(resolved.url)
                throw FolderAccessError.bookmarkResolutionFailed
            }

            if Self.representsPersistentReplacement(
                expected: actualPersistentIdentity,
                actual: refreshedPersistentIdentity
            ) {
                await resourceAccessor.stopAccessing(resolved.url)
                throw FolderAccessError.resourceReplacementDetected
            }

            refreshedSource = FolderSource(
                bookmarkData: refreshedBookmark,
                lastKnownPath: resolved.url.path,
                persistentIdentity: refreshedPersistentIdentity
            )
        } else if source.persistentIdentity != actualPersistentIdentity
                    || source.fingerprint != nil
                    || source.lastKnownPath != resolved.url.path
        {
            // This is also the in-place migration path for schema-v1 files. Preserve the existing
            // bookmark, discard the decoded legacy boot-local fingerprint in memory, and add whatever
            // restart-safe metadata the resolved resource currently exposes.
            refreshedSource = FolderSource(
                bookmarkData: source.bookmarkData,
                lastKnownPath: resolved.url.path,
                persistentIdentity: actualPersistentIdentity
            )
        } else {
            refreshedSource = nil
        }

        let handle = FolderAccessHandle(
            glassID: glassID,
            url: resolved.url,
            fingerprint: actualFingerprint
        )
        activeAccesses[handle.id] = ActiveAccess(url: resolved.url)

        return FolderAccessAcquisition(
            handle: handle,
            refreshedSource: refreshedSource
        )
    }

    public func release(handleID: UUID) async {
        guard let activeAccess = activeAccesses.removeValue(forKey: handleID) else {
            return
        }
        await resourceAccessor.stopAccessing(activeAccess.url)
    }

    public func releaseAll() async {
        let active = Array(activeAccesses.values)
        activeAccesses.removeAll(keepingCapacity: false)
        for access in active {
            await resourceAccessor.stopAccessing(access.url)
        }
    }

    private static func persistentIdentityVerificationIsUnavailable(
        expected: PersistentFolderIdentity?,
        actual: PersistentFolderIdentity?
    ) -> Bool {
        guard let expected else {
            return false
        }
        guard let actual else {
            return expected.volumeUUIDString != nil || expected.documentIdentifier != nil
        }

        if expected.volumeUUIDString != nil, actual.volumeUUIDString == nil {
            return true
        }
        if expected.documentIdentifier != nil, actual.documentIdentifier == nil {
            return true
        }
        return false
    }

    private static func representsPersistentReplacement(
        expected: PersistentFolderIdentity?,
        actual: PersistentFolderIdentity?
    ) -> Bool {
        guard let expected, let actual else {
            return false
        }

        if let expectedVolume = expected.volumeUUIDString,
           let actualVolume = actual.volumeUUIDString,
           expectedVolume != actualVolume
        {
            return true
        }

        if let expectedDocument = expected.documentIdentifier,
           let actualDocument = actual.documentIdentifier,
           expectedDocument != actualDocument
        {
            return true
        }

        return false
    }

    private static func runtimeIdentityVerificationIsUnavailable(
        expected: ResourceFingerprint?,
        actual: ResourceFingerprint?
    ) -> Bool {
        guard let expected else {
            return false
        }

        let expectsVolume = expected.volumeIdentifier != nil
        let expectsResource = expected.resourceIdentifier != nil
        guard expectsVolume || expectsResource else {
            return false
        }
        guard let actual else {
            return true
        }

        if expectsVolume, actual.volumeIdentifier == nil {
            return true
        }
        if expectsResource, actual.resourceIdentifier == nil {
            return true
        }
        return false
    }

    private static func representsRuntimeReplacement(
        expected: ResourceFingerprint?,
        actual: ResourceFingerprint?
    ) -> Bool {
        guard let expected, let actual else {
            return false
        }

        if let expectedVolume = expected.volumeIdentifier,
           let actualVolume = actual.volumeIdentifier,
           expectedVolume != actualVolume
        {
            return true
        }

        if let expectedResource = expected.resourceIdentifier,
           let actualResource = actual.resourceIdentifier,
           expectedResource != actualResource
        {
            return true
        }

        return false
    }
}

import Foundation
import SchneeGlassApplication
import SchneeGlassDomain

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
}

public actor SecurityScopedAccessCoordinator: FolderAccessControlling {
    private struct ActiveAccess: Sendable {
        let url: URL
    }

    private let resourceAccessor: any SecurityScopedResourceAccessing
    private var activeAccesses: [UUID: ActiveAccess] = [:]

    public init() {
        self.resourceAccessor = FoundationSecurityScopedResourceAccessor()
    }

    init(resourceAccessor: any SecurityScopedResourceAccessing) {
        self.resourceAccessor = resourceAccessor
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

        let actualFingerprint: ResourceFingerprint?
        do {
            actualFingerprint = try await resourceAccessor.fingerprint(for: resolved.url)
        } catch {
            actualFingerprint = nil
        }

        if Self.representsReplacement(expected: source.fingerprint, actual: actualFingerprint) {
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

            refreshedSource = FolderSource(
                bookmarkData: refreshedBookmark,
                lastKnownPath: resolved.url.path,
                fingerprint: actualFingerprint
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

    private static func representsReplacement(
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

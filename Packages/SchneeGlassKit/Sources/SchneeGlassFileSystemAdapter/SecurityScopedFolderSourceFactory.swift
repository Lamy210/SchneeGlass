import Foundation
import SchneeGlassApplication
import SchneeGlassDomain

public actor SecurityScopedFolderSourceFactory: FolderSourceCreating {
    private let resourceAccessor: any SecurityScopedResourceAccessing

    public init() {
        self.resourceAccessor = FoundationSecurityScopedResourceAccessor()
    }

    init(resourceAccessor: any SecurityScopedResourceAccessing) {
        self.resourceAccessor = resourceAccessor
    }

    public func createSource(for selectedURL: URL) async throws -> FolderSource {
        let url = selectedURL.standardizedFileURL
        let initialFingerprint = try await requiredFingerprint(for: url)
        let initialPersistentIdentity = try await persistentIdentity(for: url)

        let bookmarkData: Data
        do {
            bookmarkData = try await resourceAccessor.createBookmark(for: url)
        } catch {
            throw FolderSourceCreationError.bookmarkCreationFailed
        }

        // Bookmark creation is an async boundary. The selected pathname can be replaced while this
        // actor is suspended, so bind the bookmark only to a resource whose current-boot identity
        // stayed stable across the operation. Persistent metadata is supplemental and is captured
        // only from that same stable resource.
        let finalFingerprint = try await requiredFingerprint(for: url)
        let finalPersistentIdentity = try await persistentIdentity(for: url)
        guard finalFingerprint == initialFingerprint else {
            throw FolderSourceCreationError.resourceIdentityUnavailable
        }

        if let initialPersistentIdentity,
           let finalPersistentIdentity,
           initialPersistentIdentity != finalPersistentIdentity
        {
            throw FolderSourceCreationError.resourceIdentityUnavailable
        }

        return FolderSource(
            bookmarkData: bookmarkData,
            lastKnownPath: url.path,
            fingerprint: finalFingerprint,
            persistentIdentity: finalPersistentIdentity
        )
    }

    private func requiredFingerprint(for url: URL) async throws -> ResourceFingerprint {
        do {
            guard let observedFingerprint = try await resourceAccessor.fingerprint(for: url),
                  observedFingerprint.resourceIdentifier != nil
            else {
                throw FolderSourceCreationError.resourceIdentityUnavailable
            }
            return observedFingerprint
        } catch let error as FolderSourceCreationError {
            throw error
        } catch {
            throw FolderSourceCreationError.resourceIdentityUnavailable
        }
    }

    private func persistentIdentity(for url: URL) async throws -> PersistentFolderIdentity? {
        do {
            return try await resourceAccessor.persistentIdentity(for: url)
        } catch {
            throw FolderSourceCreationError.resourceIdentityUnavailable
        }
    }
}

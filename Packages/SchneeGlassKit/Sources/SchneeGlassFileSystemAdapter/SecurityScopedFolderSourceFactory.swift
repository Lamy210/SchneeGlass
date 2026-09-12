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

        let bookmarkData: Data
        do {
            bookmarkData = try await resourceAccessor.createBookmark(for: url)
        } catch {
            throw FolderSourceCreationError.bookmarkCreationFailed
        }

        // Bookmark creation is an async boundary. The selected pathname can be replaced while this
        // actor is suspended, so bind the bookmark only to a resource whose physical identity stayed
        // stable across the operation. Otherwise a bookmark and fingerprint from different folders
        // could be persisted together and force later recovery to guess which authority was intended.
        let finalFingerprint = try await requiredFingerprint(for: url)
        guard finalFingerprint == initialFingerprint else {
            throw FolderSourceCreationError.resourceIdentityUnavailable
        }

        return FolderSource(
            bookmarkData: bookmarkData,
            lastKnownPath: url.path,
            fingerprint: finalFingerprint
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
}

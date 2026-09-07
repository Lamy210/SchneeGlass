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
        let bookmarkData: Data

        do {
            bookmarkData = try await resourceAccessor.createBookmark(for: url)
        } catch {
            throw FolderSourceCreationError.bookmarkCreationFailed
        }

        let fingerprint: ResourceFingerprint?
        do {
            fingerprint = try await resourceAccessor.fingerprint(for: url)
        } catch {
            fingerprint = nil
        }

        return FolderSource(
            bookmarkData: bookmarkData,
            lastKnownPath: url.path,
            fingerprint: fingerprint
        )
    }
}

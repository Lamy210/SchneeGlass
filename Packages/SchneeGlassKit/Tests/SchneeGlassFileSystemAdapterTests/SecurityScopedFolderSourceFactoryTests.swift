import Foundation
import SchneeGlassApplication
@testable import SchneeGlassFileSystemAdapter
import SchneeGlassDomain
import Testing

private enum FolderSourceFactoryTestError: Error, Sendable {
    case injected
}

private actor FakeFolderSourceResourceAccessor: SecurityScopedResourceAccessing {
    let bookmarkData: Data
    let fingerprintValue: ResourceFingerprint?
    let failBookmark: Bool
    let failFingerprint: Bool
    private(set) var bookmarkURLs: [URL] = []
    private(set) var fingerprintURLs: [URL] = []

    init(
        bookmarkData: Data = Data([1, 2, 3]),
        fingerprintValue: ResourceFingerprint? = ResourceFingerprint(
            volumeIdentifier: "volume",
            resourceIdentifier: "resource"
        ),
        failBookmark: Bool = false,
        failFingerprint: Bool = false
    ) {
        self.bookmarkData = bookmarkData
        self.fingerprintValue = fingerprintValue
        self.failBookmark = failBookmark
        self.failFingerprint = failFingerprint
    }

    func resolveBookmark(_ data: Data) async throws -> ResolvedSecurityScopedResource {
        throw FolderSourceFactoryTestError.injected
    }

    func createBookmark(for url: URL) async throws -> Data {
        bookmarkURLs.append(url)
        if failBookmark { throw FolderSourceFactoryTestError.injected }
        return bookmarkData
    }

    func startAccessing(_ url: URL) async -> Bool { false }

    func stopAccessing(_ url: URL) async {}

    func fingerprint(for url: URL) async throws -> ResourceFingerprint? {
        fingerprintURLs.append(url)
        if failFingerprint { throw FolderSourceFactoryTestError.injected }
        return fingerprintValue
    }

    func observedURLs() -> (bookmark: [URL], fingerprint: [URL]) {
        (bookmarkURLs, fingerprintURLs)
    }
}

@Test
func folderSourceFactoryCreatesBookmarkAndFingerprintFromStandardizedURL() async throws {
    let accessor = FakeFolderSourceResourceAccessor()
    let factory = SecurityScopedFolderSourceFactory(resourceAccessor: accessor)
    let selected = URL(fileURLWithPath: "/tmp/Folder/../Folder", isDirectory: true)

    let source = try await factory.createSource(for: selected)
    let expected = selected.standardizedFileURL
    let observed = await accessor.observedURLs()

    #expect(source.bookmarkData == Data([1, 2, 3]))
    #expect(source.lastKnownPath == expected.path)
    #expect(source.fingerprint == ResourceFingerprint(
        volumeIdentifier: "volume",
        resourceIdentifier: "resource"
    ))
    #expect(observed.bookmark == [expected])
    #expect(observed.fingerprint == [expected])
}

@Test
func folderSourceFactoryTreatsFingerprintFailureAsOptionalMetadata() async throws {
    let accessor = FakeFolderSourceResourceAccessor(failFingerprint: true)
    let factory = SecurityScopedFolderSourceFactory(resourceAccessor: accessor)
    let selected = URL(fileURLWithPath: "/tmp/FingerprintOptional", isDirectory: true)

    let source = try await factory.createSource(for: selected)

    #expect(source.bookmarkData == Data([1, 2, 3]))
    #expect(source.fingerprint == nil)
}

@Test
func folderSourceFactoryMapsBookmarkFailureToStableApplicationError() async {
    let accessor = FakeFolderSourceResourceAccessor(failBookmark: true)
    let factory = SecurityScopedFolderSourceFactory(resourceAccessor: accessor)
    let selected = URL(fileURLWithPath: "/tmp/BookmarkFailure", isDirectory: true)

    do {
        _ = try await factory.createSource(for: selected)
        Issue.record("Expected bookmark creation failure")
    } catch let error as FolderSourceCreationError {
        #expect(error == .bookmarkCreationFailed)
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

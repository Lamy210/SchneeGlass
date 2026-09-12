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
    let fingerprintValues: [ResourceFingerprint?]
    let persistentIdentityValue: PersistentFolderIdentity?
    let failBookmark: Bool
    let failFingerprint: Bool
    private(set) var bookmarkURLs: [URL] = []
    private(set) var fingerprintURLs: [URL] = []
    private(set) var persistentIdentityURLs: [URL] = []
    private var fingerprintCallCount = 0

    init(
        bookmarkData: Data = Data([1, 2, 3]),
        fingerprintValue: ResourceFingerprint? = ResourceFingerprint(
            volumeIdentifier: "volume",
            resourceIdentifier: "resource"
        ),
        fingerprintValues: [ResourceFingerprint?]? = nil,
        persistentIdentityValue: PersistentFolderIdentity? = nil,
        failBookmark: Bool = false,
        failFingerprint: Bool = false
    ) {
        self.bookmarkData = bookmarkData
        self.fingerprintValues = fingerprintValues ?? [fingerprintValue]
        self.persistentIdentityValue = persistentIdentityValue
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

        guard !fingerprintValues.isEmpty else {
            return nil
        }
        let index = min(fingerprintCallCount, fingerprintValues.count - 1)
        fingerprintCallCount += 1
        return fingerprintValues[index]
    }

    func persistentIdentity(for url: URL) async throws -> PersistentFolderIdentity? {
        persistentIdentityURLs.append(url)
        return persistentIdentityValue
    }

    func observedURLs() -> (bookmark: [URL], fingerprint: [URL], persistentIdentity: [URL]) {
        (bookmarkURLs, fingerprintURLs, persistentIdentityURLs)
    }
}

@Test
func folderSourceFactoryValidatesRuntimeFingerprintWithoutPersistingIt() async throws {
    let accessor = FakeFolderSourceResourceAccessor()
    let factory = SecurityScopedFolderSourceFactory(resourceAccessor: accessor)
    let selected = URL(fileURLWithPath: "/tmp/Folder/../Folder", isDirectory: true)

    let source = try await factory.createSource(for: selected)
    let expected = selected.standardizedFileURL
    let observed = await accessor.observedURLs()

    #expect(source.bookmarkData == Data([1, 2, 3]))
    #expect(source.lastKnownPath == expected.path)
    #expect(source.fingerprint == nil)
    #expect(source.persistentIdentity == nil)
    #expect(observed.bookmark == [expected])
    #expect(observed.fingerprint == [expected, expected])
    #expect(observed.persistentIdentity == [expected, expected])
}

@Test
func folderSourceFactoryPersistsRestartSafeIdentityWithoutRuntimeFingerprint() async throws {
    let identity = PersistentFolderIdentity(
        volumeUUIDString: "58F0D944-7AE3-4B65-B918-29C31B7A06CB",
        documentIdentifier: 8123
    )
    let accessor = FakeFolderSourceResourceAccessor(persistentIdentityValue: identity)
    let factory = SecurityScopedFolderSourceFactory(resourceAccessor: accessor)
    let selected = URL(fileURLWithPath: "/tmp/PersistentIdentity", isDirectory: true)

    let source = try await factory.createSource(for: selected)

    #expect(source.fingerprint == nil)
    #expect(source.persistentIdentity == identity)
}

@Test
func folderSourceFactoryRejectsIdentityChangeDuringBookmarkCreation() async {
    let before = ResourceFingerprint(
        volumeIdentifier: "volume",
        resourceIdentifier: "resource-before"
    )
    let after = ResourceFingerprint(
        volumeIdentifier: "volume",
        resourceIdentifier: "resource-after"
    )
    let accessor = FakeFolderSourceResourceAccessor(
        fingerprintValues: [before, after]
    )
    let factory = SecurityScopedFolderSourceFactory(resourceAccessor: accessor)
    let selected = URL(fileURLWithPath: "/tmp/ReplacedDuringBookmark", isDirectory: true)

    do {
        _ = try await factory.createSource(for: selected)
        Issue.record("Expected unstable resource identity failure")
    } catch let error as FolderSourceCreationError {
        #expect(error == .resourceIdentityUnavailable)
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }

    let expected = selected.standardizedFileURL
    let observed = await accessor.observedURLs()
    #expect(observed.bookmark == [expected])
    #expect(observed.fingerprint == [expected, expected])
}

@Test
func folderSourceFactoryFailsClosedWhenFingerprintReadFails() async {
    let accessor = FakeFolderSourceResourceAccessor(failFingerprint: true)
    let factory = SecurityScopedFolderSourceFactory(resourceAccessor: accessor)
    let selected = URL(fileURLWithPath: "/tmp/FingerprintFailure", isDirectory: true)

    do {
        _ = try await factory.createSource(for: selected)
        Issue.record("Expected resource identity failure")
    } catch let error as FolderSourceCreationError {
        #expect(error == .resourceIdentityUnavailable)
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

@Test
func folderSourceFactoryRejectsMissingDirectoryResourceIdentity() async {
    let accessor = FakeFolderSourceResourceAccessor(
        fingerprintValue: ResourceFingerprint(
            volumeIdentifier: "volume-only",
            resourceIdentifier: nil
        )
    )
    let factory = SecurityScopedFolderSourceFactory(resourceAccessor: accessor)
    let selected = URL(fileURLWithPath: "/tmp/VolumeOnlyIdentity", isDirectory: true)

    do {
        _ = try await factory.createSource(for: selected)
        Issue.record("Expected resource identity failure")
    } catch let error as FolderSourceCreationError {
        #expect(error == .resourceIdentityUnavailable)
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

@Test
func folderSourceFactoryRejectsCompletelyUnavailableIdentity() async {
    let accessor = FakeFolderSourceResourceAccessor(fingerprintValue: nil)
    let factory = SecurityScopedFolderSourceFactory(resourceAccessor: accessor)
    let selected = URL(fileURLWithPath: "/tmp/MissingIdentity", isDirectory: true)

    do {
        _ = try await factory.createSource(for: selected)
        Issue.record("Expected resource identity failure")
    } catch let error as FolderSourceCreationError {
        #expect(error == .resourceIdentityUnavailable)
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
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

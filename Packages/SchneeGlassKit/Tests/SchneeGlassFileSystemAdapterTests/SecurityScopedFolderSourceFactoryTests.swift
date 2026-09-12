import Foundation
import SchneeGlassApplication
@testable import SchneeGlassFileSystemAdapter
import SchneeGlassDomain
import SchneeGlassPOSIXSupport
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

private actor FolderSourceRuntimeIdentityReader: RuntimeDirectoryIdentityReading {
    private let values: [POSIXDirectoryIdentity?]
    private var index = 0
    private(set) var observedURLs: [URL] = []

    init(_ values: [POSIXDirectoryIdentity?]) {
        self.values = values
    }

    func identity(for url: URL) async -> POSIXDirectoryIdentity? {
        observedURLs.append(url)
        guard !values.isEmpty else {
            return nil
        }
        let current = min(index, values.count - 1)
        index += 1
        return values[current]
    }

    func urls() -> [URL] {
        observedURLs
    }
}

private func folderSourceRuntimeIdentity(
    device: UInt64 = 7,
    inode: UInt64
) -> POSIXDirectoryIdentity {
    POSIXDirectoryIdentity(device: device, inode: inode)
}

private func fallbackIdentityReader() -> FolderSourceRuntimeIdentityReader {
    FolderSourceRuntimeIdentityReader([nil])
}

@Test
func folderSourceFactoryValidatesFallbackFingerprintWithoutPersistingIt() async throws {
    let accessor = FakeFolderSourceResourceAccessor()
    let runtimeIdentityReader = fallbackIdentityReader()
    let factory = SecurityScopedFolderSourceFactory(
        resourceAccessor: accessor,
        runtimeIdentityReader: runtimeIdentityReader
    )
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
    #expect(await runtimeIdentityReader.urls() == [expected])
}

@Test
func folderSourceFactoryPrefersStablePOSIXIdentityOverFoundationFingerprint() async throws {
    let accessor = FakeFolderSourceResourceAccessor(failFingerprint: true)
    let identity = folderSourceRuntimeIdentity(inode: 41)
    let runtimeIdentityReader = FolderSourceRuntimeIdentityReader([identity, identity])
    let factory = SecurityScopedFolderSourceFactory(
        resourceAccessor: accessor,
        runtimeIdentityReader: runtimeIdentityReader
    )
    let selected = URL(fileURLWithPath: "/tmp/POSIXIdentity", isDirectory: true)

    let source = try await factory.createSource(for: selected)
    let expected = selected.standardizedFileURL
    let observed = await accessor.observedURLs()

    #expect(source.bookmarkData == Data([1, 2, 3]))
    #expect(source.lastKnownPath == expected.path)
    #expect(source.fingerprint == nil)
    #expect(observed.fingerprint.isEmpty)
    #expect(observed.bookmark == [expected])
    #expect(await runtimeIdentityReader.urls() == [expected, expected])
}

@Test
func folderSourceFactoryPersistsRestartSafeIdentityWithStablePOSIXRuntimeIdentity() async throws {
    let persistentIdentity = PersistentFolderIdentity(
        volumeUUIDString: "58F0D944-7AE3-4B65-B918-29C31B7A06CB",
        documentIdentifier: 8123
    )
    let accessor = FakeFolderSourceResourceAccessor(
        persistentIdentityValue: persistentIdentity,
        failFingerprint: true
    )
    let runtimeIdentity = folderSourceRuntimeIdentity(inode: 41)
    let runtimeIdentityReader = FolderSourceRuntimeIdentityReader([
        runtimeIdentity,
        runtimeIdentity,
    ])
    let factory = SecurityScopedFolderSourceFactory(
        resourceAccessor: accessor,
        runtimeIdentityReader: runtimeIdentityReader
    )
    let selected = URL(fileURLWithPath: "/tmp/PersistentIdentity", isDirectory: true)

    let source = try await factory.createSource(for: selected)

    #expect(source.fingerprint == nil)
    #expect(source.persistentIdentity == persistentIdentity)
    #expect(await accessor.observedURLs().fingerprint.isEmpty)
}

@Test
func folderSourceFactoryRejectsPOSIXIdentityChangeDuringBookmarkCreation() async {
    let accessor = FakeFolderSourceResourceAccessor(failFingerprint: true)
    let runtimeIdentityReader = FolderSourceRuntimeIdentityReader([
        folderSourceRuntimeIdentity(inode: 41),
        folderSourceRuntimeIdentity(inode: 99),
    ])
    let factory = SecurityScopedFolderSourceFactory(
        resourceAccessor: accessor,
        runtimeIdentityReader: runtimeIdentityReader
    )
    let selected = URL(fileURLWithPath: "/tmp/ReplacedDuringBookmark", isDirectory: true)

    do {
        _ = try await factory.createSource(for: selected)
        Issue.record("Expected unstable POSIX resource identity failure")
    } catch let error as FolderSourceCreationError {
        #expect(error == .resourceIdentityUnavailable)
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }

    let expected = selected.standardizedFileURL
    let observed = await accessor.observedURLs()
    #expect(observed.bookmark == [expected])
    #expect(observed.fingerprint.isEmpty)
    #expect(await runtimeIdentityReader.urls() == [expected, expected])
}

@Test
func folderSourceFactoryFailsClosedWhenPOSIXIdentityDisappearsDuringBookmarkCreation() async {
    let accessor = FakeFolderSourceResourceAccessor(failFingerprint: true)
    let runtimeIdentityReader = FolderSourceRuntimeIdentityReader([
        folderSourceRuntimeIdentity(inode: 41),
        nil,
    ])
    let factory = SecurityScopedFolderSourceFactory(
        resourceAccessor: accessor,
        runtimeIdentityReader: runtimeIdentityReader
    )
    let selected = URL(fileURLWithPath: "/tmp/MissingAfterBookmark", isDirectory: true)

    do {
        _ = try await factory.createSource(for: selected)
        Issue.record("Expected missing POSIX identity to fail closed")
    } catch let error as FolderSourceCreationError {
        #expect(error == .resourceIdentityUnavailable)
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }

    #expect(await accessor.observedURLs().fingerprint.isEmpty)
}

@Test
func folderSourceFactoryFallsBackToFoundationIdentityWhenPOSIXIdentityIsUnavailable() async {
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
    let runtimeIdentityReader = fallbackIdentityReader()
    let factory = SecurityScopedFolderSourceFactory(
        resourceAccessor: accessor,
        runtimeIdentityReader: runtimeIdentityReader
    )
    let selected = URL(fileURLWithPath: "/tmp/FallbackReplacement", isDirectory: true)

    do {
        _ = try await factory.createSource(for: selected)
        Issue.record("Expected fallback Foundation identity mismatch")
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
func folderSourceFactoryFailsClosedWhenFallbackFingerprintReadFails() async {
    let accessor = FakeFolderSourceResourceAccessor(failFingerprint: true)
    let factory = SecurityScopedFolderSourceFactory(
        resourceAccessor: accessor,
        runtimeIdentityReader: fallbackIdentityReader()
    )
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
func folderSourceFactoryRejectsMissingFallbackDirectoryResourceIdentity() async {
    let accessor = FakeFolderSourceResourceAccessor(
        fingerprintValue: ResourceFingerprint(
            volumeIdentifier: "volume-only",
            resourceIdentifier: nil
        )
    )
    let factory = SecurityScopedFolderSourceFactory(
        resourceAccessor: accessor,
        runtimeIdentityReader: fallbackIdentityReader()
    )
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
    let factory = SecurityScopedFolderSourceFactory(
        resourceAccessor: accessor,
        runtimeIdentityReader: fallbackIdentityReader()
    )
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
    let identity = folderSourceRuntimeIdentity(inode: 41)
    let factory = SecurityScopedFolderSourceFactory(
        resourceAccessor: accessor,
        runtimeIdentityReader: FolderSourceRuntimeIdentityReader([identity])
    )
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

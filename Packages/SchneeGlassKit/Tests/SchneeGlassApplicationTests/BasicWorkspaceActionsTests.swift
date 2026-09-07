import FileDomain
import Foundation
@testable import SchneeGlassApplication
import SchneeGlassDomain
import Testing

private enum BasicWorkspaceActionsTestError: Error, Sendable {
    case injected
}

private actor BasicActionsConfigurationStore: ConfigurationPersisting {
    private let loaded: [GlassConfiguration]
    private let failLoad: Bool
    private let failSave: Bool
    private var savedValues: [[GlassConfiguration]] = []

    init(
        loaded: [GlassConfiguration],
        failLoad: Bool = false,
        failSave: Bool = false
    ) {
        self.loaded = loaded
        self.failLoad = failLoad
        self.failSave = failSave
    }

    func load() async throws -> [GlassConfiguration] {
        if failLoad {
            throw BasicWorkspaceActionsTestError.injected
        }
        return loaded
    }

    func save(_ configurations: [GlassConfiguration]) async throws {
        if failSave {
            throw BasicWorkspaceActionsTestError.injected
        }
        savedValues.append(configurations)
    }

    func saves() -> [[GlassConfiguration]] {
        savedValues
    }
}

@MainActor
private final class FakeWorkspaceFileActor: WorkspaceFileActing {
    var openResult = true
    private(set) var openedURLs: [URL] = []
    private(set) var revealedURLs: [URL] = []

    func open(url: URL) -> Bool {
        openedURLs.append(url)
        return openResult
    }

    func reveal(url: URL) {
        revealedURLs.append(url)
    }
}

private func basicActionsConfiguration(
    id: GlassID = GlassID(),
    title: String
) throws -> GlassConfiguration {
    try GlassConfiguration(
        id: id,
        title: title,
        source: FolderSource(
            bookmarkData: Data([1, 2, 3]),
            lastKnownPath: "/tmp/\(title)"
        ),
        placement: GlassPlacement(x: 100, y: 120),
        createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
}

private func basicActionsItem(path: String = "/tmp/report.txt") -> GlassItem {
    let url = URL(fileURLWithPath: path)
    return GlassItem(
        id: FileIdentity(resourceIdentifier: "file-id", standardizedURL: url),
        url: url,
        displayName: url.lastPathComponent,
        kind: .regular,
        isHidden: false
    )
}

@Test
func removeGlassPersistsOnlyRemainingConfigurations() async throws {
    let removedID = GlassID()
    let removed = try basicActionsConfiguration(id: removedID, title: "Removed")
    let kept = try basicActionsConfiguration(title: "Kept")
    let store = BasicActionsConfigurationStore(loaded: [removed, kept])
    let useCase = RemoveGlassUseCase(configurationStore: store)

    let didRemove = try await useCase.execute(glassID: removedID)

    #expect(didRemove)
    #expect(await store.saves() == [[kept]])
}

@Test
func removeGlassMissingIDDoesNotWriteConfiguration() async throws {
    let existing = try basicActionsConfiguration(title: "Existing")
    let store = BasicActionsConfigurationStore(loaded: [existing])
    let useCase = RemoveGlassUseCase(configurationStore: store)

    let didRemove = try await useCase.execute(glassID: GlassID())

    #expect(!didRemove)
    #expect(await store.saves().isEmpty)
}

@Test
func removeGlassMapsLoadFailureWithoutWriting() async throws {
    let store = BasicActionsConfigurationStore(loaded: [], failLoad: true)
    let useCase = RemoveGlassUseCase(configurationStore: store)

    do {
        _ = try await useCase.execute(glassID: GlassID())
        Issue.record("Expected configuration load failure")
    } catch let error as RemoveGlassError {
        #expect(error == .configurationLoadFailed)
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }

    #expect(await store.saves().isEmpty)
}

@Test
func removeGlassSaveFailureNeverReportsSuccess() async throws {
    let removedID = GlassID()
    let removed = try basicActionsConfiguration(id: removedID, title: "Removed")
    let kept = try basicActionsConfiguration(title: "Kept")
    let store = BasicActionsConfigurationStore(
        loaded: [removed, kept],
        failSave: true
    )
    let useCase = RemoveGlassUseCase(configurationStore: store)

    do {
        _ = try await useCase.execute(glassID: removedID)
        Issue.record("Expected configuration save failure")
    } catch let error as RemoveGlassError {
        #expect(error == .configurationSaveFailed)
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }

    #expect(await store.saves().isEmpty)
}

@Test
@MainActor
func workspaceFileActionOpenForwardsItemURL() throws {
    let actor = FakeWorkspaceFileActor()
    let useCase = WorkspaceFileActionUseCase(actor: actor)
    let item = basicActionsItem()

    try useCase.open(item)

    #expect(actor.openedURLs == [item.url])
}

@Test
@MainActor
func workspaceFileActionOpenFailureIsExplicit() {
    let actor = FakeWorkspaceFileActor()
    actor.openResult = false
    let useCase = WorkspaceFileActionUseCase(actor: actor)
    let item = basicActionsItem()

    do {
        try useCase.open(item)
        Issue.record("Expected open failure")
    } catch let error as WorkspaceFileActionError {
        #expect(error == .openFailed)
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

@Test
@MainActor
func workspaceFileActionRevealForwardsItemURL() {
    let actor = FakeWorkspaceFileActor()
    let useCase = WorkspaceFileActionUseCase(actor: actor)
    let item = basicActionsItem()

    useCase.reveal(item)

    #expect(actor.revealedURLs == [item.url])
}

import FileDomain
import Foundation
@testable import SchneeGlassApplication
import SchneeGlassDomain
import Testing

private enum BasicWorkspaceActionsTestError: Error, Sendable {
    case injected
}

private actor BasicActionsConfigurationStore: ConditionalConfigurationPersisting {
    private let loaded: [GlassConfiguration]
    private let failLoad: Bool
    private let failSave: Bool
    private let rejectConditionalSave: Bool
    private var savedValues: [[GlassConfiguration]] = []

    init(
        loaded: [GlassConfiguration],
        failLoad: Bool = false,
        failSave: Bool = false,
        rejectConditionalSave: Bool = false
    ) {
        self.loaded = loaded
        self.failLoad = failLoad
        self.failSave = failSave
        self.rejectConditionalSave = rejectConditionalSave
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

    func save(
        _ configurations: [GlassConfiguration],
        ifCurrentMatches expectedCurrent: [GlassConfiguration]
    ) async throws -> Bool {
        if failSave {
            throw BasicWorkspaceActionsTestError.injected
        }
        guard !rejectConditionalSave, expectedCurrent == loaded else {
            return false
        }
        savedValues.append(configurations)
        return true
    }

    func saves() -> [[GlassConfiguration]] {
        savedValues
    }
}

private actor BasicActionsPendingCopyStore: PendingCopyRecording {
    private let loaded: [PendingCopyRecord]
    private let failLoad: Bool
    private var readCount = 0

    init(
        loaded: [PendingCopyRecord] = [],
        failLoad: Bool = false
    ) {
        self.loaded = loaded
        self.failLoad = failLoad
    }

    func records() async throws -> [PendingCopyRecord] {
        readCount += 1
        if failLoad {
            throw BasicWorkspaceActionsTestError.injected
        }
        return loaded
    }

    func upsert(_ record: PendingCopyRecord) async throws {
        _ = record
    }

    func remove(operationID: UUID) async throws {
        _ = operationID
    }

    func reads() -> Int {
        readCount
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

private func basicActionsPendingCopy(glassID: GlassID) -> PendingCopyRecord {
    let operationID = UUID()
    return PendingCopyRecord(
        operationID: operationID,
        batchID: UUID(),
        destinationGlassID: glassID,
        stagingFilename: ".schneeglass-copy-\(operationID.uuidString.lowercased()).partial",
        finalFilename: "payload.txt",
        expectedSize: 7,
        stagingResourceIdentifier: "xattr-v1:\(UUID().uuidString.lowercased())",
        state: .verifying
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
    let pendingCopyStore = BasicActionsPendingCopyStore()
    let useCase = RemoveGlassUseCase(
        configurationStore: store,
        pendingCopyStore: pendingCopyStore
    )

    let didRemove = try await useCase.execute(glassID: removedID)

    #expect(didRemove)
    #expect(await store.saves() == [[kept]])
    #expect(await pendingCopyStore.reads() == 1)
}

@Test
func removeGlassMissingIDDoesNotReadRecoveryOrWriteConfiguration() async throws {
    let existing = try basicActionsConfiguration(title: "Existing")
    let store = BasicActionsConfigurationStore(loaded: [existing])
    let pendingCopyStore = BasicActionsPendingCopyStore(failLoad: true)
    let useCase = RemoveGlassUseCase(
        configurationStore: store,
        pendingCopyStore: pendingCopyStore
    )

    let didRemove = try await useCase.execute(glassID: GlassID())

    #expect(!didRemove)
    #expect(await pendingCopyStore.reads() == 0)
    #expect(await store.saves().isEmpty)
}

@Test
func removeGlassMapsConfigurationLoadFailureWithoutReadingRecovery() async throws {
    let store = BasicActionsConfigurationStore(loaded: [], failLoad: true)
    let pendingCopyStore = BasicActionsPendingCopyStore()
    let useCase = RemoveGlassUseCase(
        configurationStore: store,
        pendingCopyStore: pendingCopyStore
    )

    do {
        _ = try await useCase.execute(glassID: GlassID())
        Issue.record("Expected configuration load failure")
    } catch let error as RemoveGlassError {
        #expect(error == .configurationLoadFailed)
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }

    #expect(await pendingCopyStore.reads() == 0)
    #expect(await store.saves().isEmpty)
}

@Test
func removeGlassFailsClosedWhenRecoveryMetadataCannotBeLoaded() async throws {
    let removedID = GlassID()
    let removed = try basicActionsConfiguration(id: removedID, title: "Removed")
    let store = BasicActionsConfigurationStore(loaded: [removed])
    let pendingCopyStore = BasicActionsPendingCopyStore(failLoad: true)
    let useCase = RemoveGlassUseCase(
        configurationStore: store,
        pendingCopyStore: pendingCopyStore
    )

    do {
        _ = try await useCase.execute(glassID: removedID)
        Issue.record("Expected pending-copy load failure")
    } catch let error as RemoveGlassError {
        #expect(error == .pendingCopyLoadFailed)
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }

    #expect(await pendingCopyStore.reads() == 1)
    #expect(await store.saves().isEmpty)
}

@Test
func removeGlassPreservesConfigurationWhileTargetHasPendingRecovery() async throws {
    let removedID = GlassID()
    let removed = try basicActionsConfiguration(id: removedID, title: "Removed")
    let kept = try basicActionsConfiguration(title: "Kept")
    let store = BasicActionsConfigurationStore(loaded: [removed, kept])
    let pendingCopyStore = BasicActionsPendingCopyStore(
        loaded: [basicActionsPendingCopy(glassID: removedID)]
    )
    let useCase = RemoveGlassUseCase(
        configurationStore: store,
        pendingCopyStore: pendingCopyStore
    )

    do {
        _ = try await useCase.execute(glassID: removedID)
        Issue.record("Expected pending-copy recovery requirement")
    } catch let error as RemoveGlassError {
        #expect(error == .pendingCopyRecoveryRequired)
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }

    #expect(await store.saves().isEmpty)
}

@Test
func removeGlassIgnoresPendingRecoveryForDifferentGlass() async throws {
    let removedID = GlassID()
    let removed = try basicActionsConfiguration(id: removedID, title: "Removed")
    let kept = try basicActionsConfiguration(title: "Kept")
    let store = BasicActionsConfigurationStore(loaded: [removed, kept])
    let pendingCopyStore = BasicActionsPendingCopyStore(
        loaded: [basicActionsPendingCopy(glassID: kept.id)]
    )
    let useCase = RemoveGlassUseCase(
        configurationStore: store,
        pendingCopyStore: pendingCopyStore
    )

    let didRemove = try await useCase.execute(glassID: removedID)

    #expect(didRemove)
    #expect(await store.saves() == [[kept]])
}

@Test
func removeGlassRejectsStaleConfigurationWithoutWriting() async throws {
    let removedID = GlassID()
    let removed = try basicActionsConfiguration(id: removedID, title: "Removed")
    let kept = try basicActionsConfiguration(title: "Kept")
    let store = BasicActionsConfigurationStore(
        loaded: [removed, kept],
        rejectConditionalSave: true
    )
    let pendingCopyStore = BasicActionsPendingCopyStore()
    let useCase = RemoveGlassUseCase(
        configurationStore: store,
        pendingCopyStore: pendingCopyStore
    )

    do {
        _ = try await useCase.execute(glassID: removedID)
        Issue.record("Expected configurationChanged")
    } catch let error as RemoveGlassError {
        #expect(error == .configurationChanged)
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
    let pendingCopyStore = BasicActionsPendingCopyStore()
    let useCase = RemoveGlassUseCase(
        configurationStore: store,
        pendingCopyStore: pendingCopyStore
    )

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

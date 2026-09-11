import FileDomain
import Foundation
@testable import SchneeGlassApplication
import SchneeGlassDomain
import Testing

private enum CreateGlassSourceErrorFailure: Sendable {
    case bookmarkCreation
    case resourceIdentityUnavailable
    case unexpected
}

private enum CreateGlassSourceErrorInjectedError: Error, Sendable {
    case unexpectedCall
    case injected
}

@MainActor
private final class CreateGlassSourceErrorTrace {
    private var events: [String] = []

    func append(_ event: String) {
        events.append(event)
    }

    func snapshot() -> [String] {
        events
    }
}

@MainActor
private final class CreateGlassSourceErrorFolderSelector: FolderSelecting {
    private let trace: CreateGlassSourceErrorTrace
    private let selectedURL: URL

    init(trace: CreateGlassSourceErrorTrace, selectedURL: URL) {
        self.trace = trace
        self.selectedURL = selectedURL
    }

    func selectFolder() async -> URL? {
        trace.append("select")
        return selectedURL
    }
}

private struct CreateGlassSourceErrorCreator: FolderSourceCreating {
    let failure: CreateGlassSourceErrorFailure
    let trace: CreateGlassSourceErrorTrace

    func createSource(for selectedURL: URL) async throws -> FolderSource {
        _ = selectedURL
        await trace.append("source")

        switch failure {
        case .bookmarkCreation:
            throw FolderSourceCreationError.bookmarkCreationFailed
        case .resourceIdentityUnavailable:
            throw FolderSourceCreationError.resourceIdentityUnavailable
        case .unexpected:
            throw CreateGlassSourceErrorInjectedError.injected
        }
    }
}

@MainActor
private final class CreateGlassSourceErrorPlacementProvider: InitialGlassPlacementProviding {
    private let trace: CreateGlassSourceErrorTrace

    init(trace: CreateGlassSourceErrorTrace) {
        self.trace = trace
    }

    func initialPlacement() throws -> GlassPlacement {
        trace.append("placement")
        throw CreateGlassSourceErrorInjectedError.unexpectedCall
    }
}

private actor CreateGlassSourceErrorConfigurationStore: ConditionalConfigurationPersisting {
    private let trace: CreateGlassSourceErrorTrace

    init(trace: CreateGlassSourceErrorTrace) {
        self.trace = trace
    }

    func load() async throws -> [GlassConfiguration] {
        await trace.append("load")
        throw CreateGlassSourceErrorInjectedError.unexpectedCall
    }

    func save(_ configurations: [GlassConfiguration]) async throws {
        _ = configurations
        await trace.append("save")
        throw CreateGlassSourceErrorInjectedError.unexpectedCall
    }

    func save(
        _ configurations: [GlassConfiguration],
        ifCurrentMatches expectedCurrent: [GlassConfiguration]
    ) async throws -> Bool {
        _ = configurations
        _ = expectedCurrent
        await trace.append("conditionalSave")
        throw CreateGlassSourceErrorInjectedError.unexpectedCall
    }
}

private actor CreateGlassSourceErrorAccessController: FolderAccessControlling {
    private let trace: CreateGlassSourceErrorTrace

    init(trace: CreateGlassSourceErrorTrace) {
        self.trace = trace
    }

    func acquire(
        source: FolderSource,
        glassID: GlassID
    ) async throws -> FolderAccessAcquisition {
        _ = source
        _ = glassID
        await trace.append("acquire")
        throw CreateGlassSourceErrorInjectedError.unexpectedCall
    }

    func release(handleID: UUID) async {
        _ = handleID
        await trace.append("release")
    }
}

private actor CreateGlassSourceErrorEventStreaming: FileEventStreaming {
    private let trace: CreateGlassSourceErrorTrace

    init(trace: CreateGlassSourceErrorTrace) {
        self.trace = trace
    }

    func subscribe(for access: FolderAccessHandle) async throws -> FileEventSubscription {
        _ = access
        await trace.append("subscribe")
        throw CreateGlassSourceErrorInjectedError.unexpectedCall
    }

    func stop(subscriptionID: UUID) async {
        _ = subscriptionID
        await trace.append("stop")
    }
}

private actor CreateGlassSourceErrorSnapshotReader: FolderSnapshotReading {
    private let trace: CreateGlassSourceErrorTrace

    init(trace: CreateGlassSourceErrorTrace) {
        self.trace = trace
    }

    func snapshot(
        for access: FolderAccessHandle,
        generation: UInt64
    ) async throws -> FolderSnapshot {
        _ = access
        _ = generation
        await trace.append("snapshot")
        throw CreateGlassSourceErrorInjectedError.unexpectedCall
    }
}

@MainActor
private func makeCreateGlassSourceErrorUseCase(
    failure: CreateGlassSourceErrorFailure,
    trace: CreateGlassSourceErrorTrace
) -> CreateGlassUseCase {
    CreateGlassUseCase(
        folderSelector: CreateGlassSourceErrorFolderSelector(
            trace: trace,
            selectedURL: URL(fileURLWithPath: "/tmp/SchneeGlassSourceError", isDirectory: true)
        ),
        sourceCreator: CreateGlassSourceErrorCreator(failure: failure, trace: trace),
        placementProvider: CreateGlassSourceErrorPlacementProvider(trace: trace),
        configurationStore: CreateGlassSourceErrorConfigurationStore(trace: trace),
        accessController: CreateGlassSourceErrorAccessController(trace: trace),
        eventStreaming: CreateGlassSourceErrorEventStreaming(trace: trace),
        snapshotReader: CreateGlassSourceErrorSnapshotReader(trace: trace)
    )
}

@Test
@MainActor
func createGlassPreservesFolderIdentityObservationFailure() async {
    let trace = CreateGlassSourceErrorTrace()
    let useCase = makeCreateGlassSourceErrorUseCase(
        failure: .resourceIdentityUnavailable,
        trace: trace
    )

    do {
        _ = try await useCase.execute()
        Issue.record("Expected sourceIdentityUnavailable")
    } catch let error as CreateGlassError {
        #expect(error == .sourceIdentityUnavailable)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(trace.snapshot() == ["select", "source"])
}

@Test
@MainActor
func createGlassKeepsBookmarkCreationFailureGeneric() async {
    let trace = CreateGlassSourceErrorTrace()
    let useCase = makeCreateGlassSourceErrorUseCase(
        failure: .bookmarkCreation,
        trace: trace
    )

    do {
        _ = try await useCase.execute()
        Issue.record("Expected sourceCreationFailed")
    } catch let error as CreateGlassError {
        #expect(error == .sourceCreationFailed)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(trace.snapshot() == ["select", "source"])
}

@Test
@MainActor
func createGlassKeepsUnknownSourceCreatorFailureGeneric() async {
    let trace = CreateGlassSourceErrorTrace()
    let useCase = makeCreateGlassSourceErrorUseCase(
        failure: .unexpected,
        trace: trace
    )

    do {
        _ = try await useCase.execute()
        Issue.record("Expected sourceCreationFailed")
    } catch let error as CreateGlassError {
        #expect(error == .sourceCreationFailed)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(trace.snapshot() == ["select", "source"])
}

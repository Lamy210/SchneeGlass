import Observation
import SchneeGlassApplication
import SchneeGlassDomain

public struct GlassWorkspaceEntry: Identifiable, Hashable, Sendable {
    public let id: GlassID
    public let title: String
    public var contentState: GlassContentState

    public init(
        id: GlassID,
        title: String,
        contentState: GlassContentState
    ) {
        self.id = id
        self.title = title
        self.contentState = contentState
    }
}

@MainActor
@Observable
public final class SchneeGlassWorkspaceModel {
    public private(set) var glasses: [GlassWorkspaceEntry] = []
    public private(set) var isCreatingGlass = false
    public private(set) var isRestoring = false
    public private(set) var userMessage: String?

    private let createGlassUseCase: CreateGlassUseCase
    private let restoreApplicationUseCase: RestoreApplicationUseCase
    private let runtimeSessionFactory: GlassRuntimeSessionFactory
    private var sessions: [GlassID: GlassRuntimeSession] = [:]
    private var stateTasks: [GlassID: Task<Void, Never>] = [:]
    private var didAttemptInitialRestore = false

    public init(
        createGlassUseCase: CreateGlassUseCase,
        restoreApplicationUseCase: RestoreApplicationUseCase,
        runtimeSessionFactory: GlassRuntimeSessionFactory
    ) {
        self.createGlassUseCase = createGlassUseCase
        self.restoreApplicationUseCase = restoreApplicationUseCase
        self.runtimeSessionFactory = runtimeSessionFactory
    }

    public func restoreIfNeeded() async {
        guard !didAttemptInitialRestore else {
            return
        }

        didAttemptInitialRestore = true
        isRestoring = true
        userMessage = nil
        defer { isRestoring = false }

        do {
            let result = try await restoreApplicationUseCase.execute()

            for failure in result.failures {
                upsert(
                    GlassWorkspaceEntry(
                        id: failure.glassID,
                        title: failure.title,
                        contentState: Self.contentState(for: failure.reason)
                    )
                )
            }

            for seed in result.seeds {
                do {
                    try await activate(seed)
                } catch {
                    upsert(
                        GlassWorkspaceEntry(
                            id: seed.configuration.id,
                            title: seed.configuration.title,
                            contentState: .failed(.unexpected)
                        )
                    )
                }
            }

            if result.refreshedConfigurationSavePending {
                userMessage = "Some refreshed folder permissions could not be saved. Your current Glasses remain available for this session."
            } else if !result.failures.isEmpty {
                userMessage = "Some Glasses couldn't reconnect. Other Glasses were restored normally."
            }
        } catch {
            userMessage = "SchneeGlass couldn't read its saved configuration. Use Recovery before making changes."
        }
    }

    public func addGlass() async {
        guard !isCreatingGlass, !isRestoring else {
            return
        }

        isCreatingGlass = true
        userMessage = nil
        defer { isCreatingGlass = false }

        do {
            guard let seed = try await createGlassUseCase.execute() else {
                return
            }
            try await activate(seed)
        } catch {
            userMessage = Self.userFacingMessage(for: error)
        }
    }

    public func dismissMessage() {
        userMessage = nil
    }

    public func shutdown() async {
        let activeSessions = Array(sessions.values)
        stateTasks.values.forEach { $0.cancel() }
        stateTasks.removeAll(keepingCapacity: false)
        sessions.removeAll(keepingCapacity: false)

        for session in activeSessions {
            await session.stop()
        }
    }

    private func activate(_ seed: CreatedGlassRuntimeSeed) async throws {
        let session = runtimeSessionFactory.makeSession(from: seed)

        do {
            let states = try await session.start()
            let glassID = seed.configuration.id

            sessions[glassID] = session
            upsert(
                GlassWorkspaceEntry(
                    id: glassID,
                    title: seed.configuration.title,
                    contentState: .loading
                )
            )

            stateTasks[glassID]?.cancel()
            stateTasks[glassID] = Task { [weak self] in
                for await state in states {
                    guard !Task.isCancelled else {
                        return
                    }
                    self?.updateState(state, for: glassID)
                }
                self?.stateTasks[glassID] = nil
                self?.sessions[glassID] = nil
            }
        } catch {
            await session.stop()
            throw error
        }
    }

    private func updateState(_ state: GlassContentState, for glassID: GlassID) {
        guard let index = glasses.firstIndex(where: { $0.id == glassID }) else {
            return
        }
        glasses[index].contentState = state
    }

    private func upsert(_ entry: GlassWorkspaceEntry) {
        if let index = glasses.firstIndex(where: { $0.id == entry.id }) {
            glasses[index] = entry
        } else {
            glasses.append(entry)
        }
    }

    private static func contentState(
        for failure: GlassRestoreFailure.Reason
    ) -> GlassContentState {
        switch failure {
        case let .folderAccess(accessError):
            switch accessError {
            case .bookmarkResolutionFailed:
                return .unavailable(.bookmarkResolutionFailed)
            case .accessDenied:
                return .unavailable(.permissionLost)
            case .resourceReplacementDetected:
                return .unavailable(.replacementDetected)
            }

        case .eventStreamFailed:
            return .failed(.unexpected)

        case .snapshotFailed:
            return .failed(.enumerationFailed)

        case .invalidRefreshedConfiguration:
            return .failed(.unexpected)
        }
    }

    private static func userFacingMessage(for error: Error) -> String {
        guard let createError = error as? CreateGlassError else {
            return "SchneeGlass couldn't add this folder. Nothing was changed."
        }

        switch createError {
        case .sourceCreationFailed:
            return "SchneeGlass couldn't remember access to this folder."
        case .placementUnavailable:
            return "SchneeGlass couldn't find a usable screen position."
        case .invalidConfiguration:
            return "SchneeGlass couldn't create a valid Glass for this folder."
        case .configurationLoadFailed:
            return "SchneeGlass couldn't read its configuration. Open Recovery before trying again."
        case .folderAccess:
            return "SchneeGlass couldn't access this folder. Choose it again to reconnect."
        case .eventStreamFailed:
            return "SchneeGlass couldn't watch this folder for changes."
        case .snapshotFailed:
            return "SchneeGlass couldn't read this folder."
        case .configurationSaveFailed:
            return "SchneeGlass couldn't save this Glass. Nothing was added."
        }
    }
}

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
    public private(set) var userMessage: String?

    private let createGlassUseCase: CreateGlassUseCase
    private let runtimeSessionFactory: GlassRuntimeSessionFactory
    private var sessions: [GlassID: GlassRuntimeSession] = [:]
    private var stateTasks: [GlassID: Task<Void, Never>] = [:]

    public init(
        createGlassUseCase: CreateGlassUseCase,
        runtimeSessionFactory: GlassRuntimeSessionFactory
    ) {
        self.createGlassUseCase = createGlassUseCase
        self.runtimeSessionFactory = runtimeSessionFactory
    }

    public func addGlass() async {
        guard !isCreatingGlass else {
            return
        }

        isCreatingGlass = true
        userMessage = nil
        defer { isCreatingGlass = false }

        do {
            guard let seed = try await createGlassUseCase.execute() else {
                return
            }

            let session = runtimeSessionFactory.makeSession(from: seed)
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

import FileDomain
import Foundation
import Observation
import SchneeGlassApplication
import SchneeGlassDomain

public struct GlassWorkspaceEntry: Identifiable, Hashable, Sendable {
    public let id: GlassID
    public let title: String
    public var contentState: GlassContentState
    public var interactionState: InteractionState
    public var placement: GlassPlacement?
    public let showOnAllSpaces: Bool

    public init(
        id: GlassID,
        title: String,
        contentState: GlassContentState,
        interactionState: InteractionState = .idle,
        placement: GlassPlacement? = nil,
        showOnAllSpaces: Bool = false
    ) {
        self.id = id
        self.title = title
        self.contentState = contentState
        self.interactionState = interactionState
        self.placement = placement
        self.showOnAllSpaces = showOnAllSpaces
    }
}

public enum GlassPlacementPersistenceResult: Hashable, Sendable {
    case updated
    case busy
    case missing
    case failed
}

public enum GlassPositionResetResult: Hashable, Sendable {
    case updated
    case noGlasses
    case busy
    case failed
}

@MainActor
@Observable
public final class SchneeGlassWorkspaceModel {
    public private(set) var glasses: [GlassWorkspaceEntry] = []
    public private(set) var isCreatingGlass = false
    public private(set) var isRestoring = false
    public private(set) var isMutatingConfiguration = false
    public private(set) var userMessage: String?

    private let createGlassUseCase: CreateGlassUseCase
    private let restoreApplicationUseCase: RestoreApplicationUseCase
    private let removeGlassUseCase: RemoveGlassUseCase
    private let updateGlassPlacementUseCase: UpdateGlassPlacementUseCase
    private let resetGlassPositionsUseCase: ResetGlassPositionsUseCase
    private let fileActionUseCase: WorkspaceFileActionUseCase
    private let runtimeSessionFactory: GlassRuntimeSessionFactory
    private var sessions: [GlassID: GlassRuntimeSession] = [:]
    private var stateTasks: [GlassID: Task<Void, Never>] = [:]
    private var didAttemptInitialRestore = false

    public init(
        createGlassUseCase: CreateGlassUseCase,
        restoreApplicationUseCase: RestoreApplicationUseCase,
        removeGlassUseCase: RemoveGlassUseCase,
        updateGlassPlacementUseCase: UpdateGlassPlacementUseCase,
        resetGlassPositionsUseCase: ResetGlassPositionsUseCase,
        fileActionUseCase: WorkspaceFileActionUseCase,
        runtimeSessionFactory: GlassRuntimeSessionFactory
    ) {
        self.createGlassUseCase = createGlassUseCase
        self.restoreApplicationUseCase = restoreApplicationUseCase
        self.removeGlassUseCase = removeGlassUseCase
        self.updateGlassPlacementUseCase = updateGlassPlacementUseCase
        self.resetGlassPositionsUseCase = resetGlassPositionsUseCase
        self.fileActionUseCase = fileActionUseCase
        self.runtimeSessionFactory = runtimeSessionFactory
    }

    public func restoreIfNeeded() async {
        guard !didAttemptInitialRestore, !isMutatingConfiguration else {
            return
        }

        didAttemptInitialRestore = true
        isMutatingConfiguration = true
        isRestoring = true
        userMessage = nil
        defer {
            isRestoring = false
            isMutatingConfiguration = false
        }

        do {
            let result = try await restoreApplicationUseCase.execute()

            for failure in result.failures {
                upsert(
                    GlassWorkspaceEntry(
                        id: failure.glassID,
                        title: failure.title,
                        contentState: Self.contentState(for: failure.reason),
                        placement: failure.placement,
                        showOnAllSpaces: failure.showOnAllSpaces
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
                            contentState: .failed(.unexpected),
                            placement: seed.configuration.placement,
                            showOnAllSpaces: seed.configuration.showOnAllSpaces
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
        guard !isMutatingConfiguration else {
            return
        }

        isMutatingConfiguration = true
        isCreatingGlass = true
        userMessage = nil
        defer {
            isCreatingGlass = false
            isMutatingConfiguration = false
        }

        do {
            guard let seed = try await createGlassUseCase.execute() else {
                return
            }
            try await activate(seed)
        } catch {
            userMessage = Self.userFacingMessage(for: error)
        }
    }

    public func removeGlass(id: GlassID) async {
        guard !isMutatingConfiguration,
              !isCopying(glassID: id)
        else {
            return
        }

        isMutatingConfiguration = true
        defer { isMutatingConfiguration = false }

        do {
            let removed = try await removeGlassUseCase.execute(glassID: id)
            guard removed else {
                return
            }

            stateTasks[id]?.cancel()
            stateTasks[id] = nil

            if let session = sessions.removeValue(forKey: id) {
                await session.stop()
            }

            glasses.removeAll { $0.id == id }
            userMessage = nil
        } catch {
            userMessage = "SchneeGlass couldn't remove this Glass from its configuration. The folder and its files were not changed."
        }
    }

    public func persistPlacement(
        glassID: GlassID,
        placement: GlassPlacement
    ) async -> GlassPlacementPersistenceResult {
        guard !isMutatingConfiguration else {
            return .busy
        }

        isMutatingConfiguration = true
        defer { isMutatingConfiguration = false }

        do {
            let updated = try await updateGlassPlacementUseCase.execute(
                glassID: glassID,
                placement: placement
            )
            guard updated else {
                return .missing
            }

            if let index = glasses.firstIndex(where: { $0.id == glassID }) {
                glasses[index].placement = placement
            }
            return .updated
        } catch {
            userMessage = "SchneeGlass couldn't save the new Glass position. Files and folders were not changed."
            return .failed
        }
    }

    public func resetGlassPositions(
        placements: [GlassID: GlassPlacement]
    ) async -> GlassPositionResetResult {
        guard !glasses.isEmpty else {
            return .noGlasses
        }
        guard !isMutatingConfiguration else {
            return .busy
        }
        guard Set(placements.keys) == Set(glasses.map(\.id)) else {
            userMessage = "SchneeGlass couldn't reset positions because the workspace changed. No files or folders were changed."
            return .failed
        }

        isMutatingConfiguration = true
        defer { isMutatingConfiguration = false }

        do {
            _ = try await resetGlassPositionsUseCase.execute(placements: placements)
            for index in glasses.indices {
                if let placement = placements[glasses[index].id] {
                    glasses[index].placement = placement
                }
            }
            userMessage = nil
            return .updated
        } catch {
            userMessage = "SchneeGlass couldn't reset Glass positions. Files and folders were not changed."
            return .failed
        }
    }

    public func planDrop(
        glassID: GlassID,
        sourceURLs: [URL]
    ) async -> DropPlan {
        guard let session = sessions[glassID],
              !isCopying(glassID: glassID)
        else {
            let rejection = DropPlan.reject(.destinationUnavailable)
            updateInteraction(.dropInvalid(.destinationUnavailable), for: glassID)
            return rejection
        }

        updateInteraction(.hovered, for: glassID)
        let plan = await session.planDrop(sourceURLs: sourceURLs)

        switch plan {
        case let .copy(copyPlan):
            updateInteraction(.dropValid(.copy(copyPlan)), for: glassID)
        case .noOperation:
            updateInteraction(.dropInvalid(.containsSameDirectoryItem), for: glassID)
        case let .reject(reason):
            updateInteraction(.dropInvalid(reason), for: glassID)
        }

        return plan
    }

    public func performDrop(
        glassID: GlassID,
        sourceURLs: [URL]
    ) async -> Bool {
        guard let session = sessions[glassID],
              !isCopying(glassID: glassID)
        else {
            updateInteraction(.dropInvalid(.destinationUnavailable), for: glassID)
            return false
        }

        let freshPlan = await session.planDrop(sourceURLs: sourceURLs)
        guard case let .copy(copyPlan) = freshPlan else {
            switch freshPlan {
            case .noOperation:
                updateInteraction(.dropInvalid(.containsSameDirectoryItem), for: glassID)
            case let .reject(reason):
                updateInteraction(.dropInvalid(reason), for: glassID)
            case .copy:
                break
            }
            return false
        }

        let firstFilename = copyPlan.items.first?.destinationFilename ?? "file"
        updateInteraction(
            .copying(
                CopyProgress(
                    currentIndex: 1,
                    totalCount: copyPlan.items.count,
                    currentFilename: firstFilename
                )
            ),
            for: glassID
        )

        do {
            let result = try await session.executeCopy(copyPlan)
            updateInteraction(.idle, for: glassID)

            if let failure = result.failed {
                userMessage = Self.copyFailureMessage(
                    failure,
                    succeededCount: result.succeeded.count
                )
                return !result.succeeded.isEmpty
            }

            if result.succeeded.contains(where: { $0.recoveryMetadataCleanupPending }) {
                userMessage = "The files were copied, but SchneeGlass still has recovery metadata to clean up. Your copied files were not changed."
            } else {
                userMessage = nil
            }
            return true
        } catch let error as GlassCopyExecutionError {
            updateInteraction(.idle, for: glassID)
            switch error {
            case .sessionNotRunning, .destinationMismatch:
                userMessage = "This Glass is no longer available as a copy destination. Nothing was copied."
            case .copyInProgress:
                userMessage = "A copy is already running for this Glass."
            }
            return false
        } catch {
            updateInteraction(.idle, for: glassID)
            userMessage = "SchneeGlass couldn't copy these files. Source files were not moved or deleted."
            return false
        }
    }

    public func cancelDrop(glassID: GlassID) {
        guard !isCopying(glassID: glassID) else {
            return
        }
        updateInteraction(.idle, for: glassID)
    }

    public func open(_ item: GlassItem) {
        do {
            try fileActionUseCase.open(item)
        } catch {
            userMessage = "macOS couldn't open \(item.displayName)."
        }
    }

    public func revealInFinder(_ item: GlassItem) {
        fileActionUseCase.reveal(item)
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
                    contentState: .loading,
                    placement: seed.configuration.placement,
                    showOnAllSpaces: seed.configuration.showOnAllSpaces
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

    private func updateInteraction(_ state: InteractionState, for glassID: GlassID) {
        guard let index = glasses.firstIndex(where: { $0.id == glassID }) else {
            return
        }
        glasses[index].interactionState = state
    }

    private func isCopying(glassID: GlassID) -> Bool {
        guard let entry = glasses.first(where: { $0.id == glassID }) else {
            return false
        }
        if case .copying = entry.interactionState {
            return true
        }
        return false
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

    private static func copyFailureMessage(
        _ failure: CopyItemFailure,
        succeededCount: Int
    ) -> String {
        let prefix = succeededCount > 0
            ? "\(succeededCount) file(s) were copied before the operation stopped. "
            : "Nothing was copied. "

        switch failure.reason {
        case .sourceUnavailable:
            return prefix + "A source file became unavailable."
        case .unsupportedItem:
            return prefix + "One of the dropped items is not supported."
        case .destinationUnavailable:
            return prefix + "The destination folder became unavailable."
        case .permissionDenied:
            return prefix + "macOS denied file access."
        case .insufficientSpace:
            return prefix + "There is not enough free space at the destination."
        case .collision:
            return prefix + "A file with the same name already exists. Nothing was overwritten."
        case .verificationFailed:
            return prefix + "SchneeGlass could not verify a copied file safely."
        case .cancelled:
            return prefix + "The copy was cancelled."
        case .unexpected:
            return prefix + "SchneeGlass encountered an unexpected copy error."
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

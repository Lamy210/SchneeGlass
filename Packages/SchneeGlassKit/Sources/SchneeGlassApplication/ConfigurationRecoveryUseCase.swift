import SchneeGlassDomain

public enum ConfigurationRecoveryUseCaseError: Error, Hashable, Sendable {
    case pendingCopyLoadFailed
    case pendingCopyRecoveryRequired
}

/// Provides the explicit configuration recovery operations used by Presentation.
///
/// Recovery is deliberately user-initiated. The persistence adapter is responsible for validating
/// backup identifiers, preserving the current configuration, and performing the atomic restore.
/// Pending Copy metadata is checked before restore because those records bind recovery authority to
/// the current Glass IDs and destination bookmarks.
public actor ConfigurationRecoveryUseCase {
    private let recoveryProvider: any ConfigurationRecoveryProviding
    private let pendingCopyStore: any PendingCopyRecording

    public init(
        recoveryProvider: any ConfigurationRecoveryProviding,
        pendingCopyStore: any PendingCopyRecording
    ) {
        self.recoveryProvider = recoveryProvider
        self.pendingCopyStore = pendingCopyStore
    }

    public func availableBackups() async throws -> [ConfigurationBackupDescriptor] {
        try await recoveryProvider.availableBackups()
    }

    @discardableResult
    public func restoreBackup(id: String) async throws -> [GlassConfiguration] {
        let pendingCopies: [PendingCopyRecord]
        do {
            pendingCopies = try await pendingCopyStore.records()
        } catch {
            throw ConfigurationRecoveryUseCaseError.pendingCopyLoadFailed
        }

        guard pendingCopies.isEmpty else {
            throw ConfigurationRecoveryUseCaseError.pendingCopyRecoveryRequired
        }

        return try await recoveryProvider.restoreBackup(id: id)
    }
}

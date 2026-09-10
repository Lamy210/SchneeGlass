import SchneeGlassDomain

public enum ConfigurationRecoveryUseCaseError: Error, Hashable, Sendable {
    case pendingCopyLoadFailed
    case pendingCopyRecoveryRequired
}

/// Provides the explicit configuration recovery operations used by Presentation.
///
/// Recovery is deliberately user-initiated. The persistence adapter is responsible for validating
/// backup identifiers, preserving the current configuration, and performing the atomic restore.
/// When Pending Copy metadata still has a live current Glass mapping, that mapping is preserved until
/// the user resolves the pending recovery item. If the current configuration is already unreadable or
/// the referenced Glass is already missing, explicit backup restore remains available as a recovery
/// path instead of creating a dead end.
public actor ConfigurationRecoveryUseCase {
    private let recoveryStore: any ConfigurationRecoveryProviding & ConfigurationPersisting
    private let pendingCopyStore: any PendingCopyRecording

    public init(
        recoveryStore: any ConfigurationRecoveryProviding & ConfigurationPersisting,
        pendingCopyStore: any PendingCopyRecording
    ) {
        self.recoveryStore = recoveryStore
        self.pendingCopyStore = pendingCopyStore
    }

    public func availableBackups() async throws -> [ConfigurationBackupDescriptor] {
        try await recoveryStore.availableBackups()
    }

    @discardableResult
    public func restoreBackup(id: String) async throws -> [GlassConfiguration] {
        let pendingCopies: [PendingCopyRecord]
        do {
            pendingCopies = try await pendingCopyStore.records()
        } catch {
            throw ConfigurationRecoveryUseCaseError.pendingCopyLoadFailed
        }

        guard !pendingCopies.isEmpty else {
            return try await recoveryStore.restoreBackup(id: id)
        }

        let currentConfigurations: [GlassConfiguration]
        do {
            currentConfigurations = try await recoveryStore.load()
        } catch {
            // Explicit configuration recovery exists specifically for unreadable/corrupt current
            // state. The persistence adapter still applies its own preservation/schema guards before
            // committing the selected backup, so do not make Pending Copy metadata a dead end here.
            return try await recoveryStore.restoreBackup(id: id)
        }

        let currentGlassIDs = Set(currentConfigurations.map(\.id))
        guard !pendingCopies.contains(where: { currentGlassIDs.contains($0.destinationGlassID) }) else {
            throw ConfigurationRecoveryUseCaseError.pendingCopyRecoveryRequired
        }

        // All pending records already lack a current Glass mapping. Allow explicit backup recovery;
        // it may restore those mappings and cannot destroy an authority that is still present now.
        return try await recoveryStore.restoreBackup(id: id)
    }
}

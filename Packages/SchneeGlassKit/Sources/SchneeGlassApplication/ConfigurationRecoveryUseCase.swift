import SchneeGlassDomain

/// Provides the explicit configuration recovery operations used by Presentation.
///
/// Recovery is deliberately user-initiated. The persistence adapter is responsible for validating
/// backup identifiers, preserving the current configuration, and performing the atomic restore.
public actor ConfigurationRecoveryUseCase {
    private let recoveryProvider: any ConfigurationRecoveryProviding

    public init(recoveryProvider: any ConfigurationRecoveryProviding) {
        self.recoveryProvider = recoveryProvider
    }

    public func availableBackups() async throws -> [ConfigurationBackupDescriptor] {
        try await recoveryProvider.availableBackups()
    }

    @discardableResult
    public func restoreBackup(id: String) async throws -> [GlassConfiguration] {
        try await recoveryProvider.restoreBackup(id: id)
    }
}

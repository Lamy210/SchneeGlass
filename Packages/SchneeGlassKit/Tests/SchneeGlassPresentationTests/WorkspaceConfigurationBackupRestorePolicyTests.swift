import Testing

@testable import SchneeGlassPresentation

@Suite
struct WorkspaceConfigurationBackupRestorePolicyTests {
  @Test
  func blocksBackupRestoreBeforeInitialConfigurationLoad() {
    #expect(
      !WorkspaceConfigurationBackupRestorePolicy.allowsRestore(
        hasLoadedConfigurationSnapshot: false,
        isMutatingConfiguration: false,
        requiresConfigurationRecovery: false
      )
    )
  }

  @Test
  func allowsBackupRestoreAfterSuccessfulConfigurationLoad() {
    #expect(
      WorkspaceConfigurationBackupRestorePolicy.allowsRestore(
        hasLoadedConfigurationSnapshot: true,
        isMutatingConfiguration: false,
        requiresConfigurationRecovery: false
      )
    )
  }

  @Test
  func allowsBackupRestoreWhenInitialLoadRequiresRecovery() {
    #expect(
      WorkspaceConfigurationBackupRestorePolicy.allowsRestore(
        hasLoadedConfigurationSnapshot: false,
        isMutatingConfiguration: false,
        requiresConfigurationRecovery: true
      )
    )
  }

  @Test
  func blocksBackupRestoreWhileConfigurationMutationIsActive() {
    #expect(
      !WorkspaceConfigurationBackupRestorePolicy.allowsRestore(
        hasLoadedConfigurationSnapshot: true,
        isMutatingConfiguration: true,
        requiresConfigurationRecovery: false
      )
    )
    #expect(
      !WorkspaceConfigurationBackupRestorePolicy.allowsRestore(
        hasLoadedConfigurationSnapshot: false,
        isMutatingConfiguration: true,
        requiresConfigurationRecovery: true
      )
    )
  }
}

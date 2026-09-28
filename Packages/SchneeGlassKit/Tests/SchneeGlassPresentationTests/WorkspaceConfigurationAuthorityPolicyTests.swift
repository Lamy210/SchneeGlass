import Testing

@testable import SchneeGlassPresentation

@Suite
struct WorkspaceConfigurationAuthorityPolicyTests {
  @Test
  func blocksAuthorityBeforeInitialRestoreAttempt() {
    #expect(
      !WorkspaceConfigurationAuthorityPolicy.hasAuthoritativeSnapshot(
        didAttemptInitialRestore: false,
        isMutatingConfiguration: false,
        requiresConfigurationRecovery: false
      )
    )
  }

  @Test
  func allowsAuthorityAfterSuccessfulStableRestore() {
    #expect(
      WorkspaceConfigurationAuthorityPolicy.hasAuthoritativeSnapshot(
        didAttemptInitialRestore: true,
        isMutatingConfiguration: false,
        requiresConfigurationRecovery: false
      )
    )
  }

  @Test
  func blocksAuthorityWhileConfigurationMutationIsActive() {
    #expect(
      !WorkspaceConfigurationAuthorityPolicy.hasAuthoritativeSnapshot(
        didAttemptInitialRestore: true,
        isMutatingConfiguration: true,
        requiresConfigurationRecovery: false
      )
    )
  }

  @Test
  func blocksAuthorityWhileConfigurationRecoveryIsRequired() {
    #expect(
      !WorkspaceConfigurationAuthorityPolicy.hasAuthoritativeSnapshot(
        didAttemptInitialRestore: true,
        isMutatingConfiguration: false,
        requiresConfigurationRecovery: true
      )
    )
  }
}

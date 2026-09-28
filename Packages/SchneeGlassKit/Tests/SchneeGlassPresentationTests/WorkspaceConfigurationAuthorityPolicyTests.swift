import Testing

@testable import SchneeGlassPresentation

@Suite
struct WorkspaceConfigurationAuthorityPolicyTests {
  @Test
  func blocksAuthorityBeforeConfigurationLoadSucceeds() {
    #expect(
      !WorkspaceConfigurationAuthorityPolicy.hasAuthoritativeSnapshot(
        hasLoadedConfigurationSnapshot: false,
        isMutatingConfiguration: false,
        requiresConfigurationRecovery: false
      )
    )
  }

  @Test
  func allowsAuthorityAfterSuccessfulStableRestore() {
    #expect(
      WorkspaceConfigurationAuthorityPolicy.hasAuthoritativeSnapshot(
        hasLoadedConfigurationSnapshot: true,
        isMutatingConfiguration: false,
        requiresConfigurationRecovery: false
      )
    )
  }

  @Test
  func blocksAuthorityWhileConfigurationMutationIsActive() {
    #expect(
      !WorkspaceConfigurationAuthorityPolicy.hasAuthoritativeSnapshot(
        hasLoadedConfigurationSnapshot: true,
        isMutatingConfiguration: true,
        requiresConfigurationRecovery: false
      )
    )
  }

  @Test
  func blocksAuthorityWhileConfigurationRecoveryIsRequired() {
    #expect(
      !WorkspaceConfigurationAuthorityPolicy.hasAuthoritativeSnapshot(
        hasLoadedConfigurationSnapshot: true,
        isMutatingConfiguration: false,
        requiresConfigurationRecovery: true
      )
    )
  }
}

import Testing
@testable import SchneeGlassPresentation

@Suite
struct WorkspaceConfigurationMutationPolicyTests {
    @Test
    func allowsMutationWhenWorkspaceIsReady() {
        #expect(
            WorkspaceConfigurationMutationPolicy.allowsMutation(
                isMutatingConfiguration: false,
                requiresConfigurationRecovery: false
            )
        )
    }

    @Test
    func blocksMutationWhileAnotherConfigurationMutationIsActive() {
        #expect(
            !WorkspaceConfigurationMutationPolicy.allowsMutation(
                isMutatingConfiguration: true,
                requiresConfigurationRecovery: false
            )
        )
    }

    @Test
    func blocksMutationUntilConfigurationRecoveryCompletes() {
        #expect(
            !WorkspaceConfigurationMutationPolicy.allowsMutation(
                isMutatingConfiguration: false,
                requiresConfigurationRecovery: true
            )
        )
    }

    @Test
    func recoveryRequirementWinsEvenWhileMutationFlagIsSet() {
        #expect(
            !WorkspaceConfigurationMutationPolicy.allowsMutation(
                isMutatingConfiguration: true,
                requiresConfigurationRecovery: true
            )
        )
    }
}

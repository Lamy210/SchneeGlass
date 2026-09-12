import Testing
@testable import SchneeGlassPresentation

@Test
func transientContentFailuresKeepAutomaticRetryGuidance() {
    let enumeration = GlassContentFailurePresentation.make(for: .enumerationFailed)
    let metadata = GlassContentFailurePresentation.make(for: .metadataFailed)

    #expect(enumeration.status == "Refresh failed")
    #expect(enumeration.title == "Couldn't refresh this folder")
    #expect(enumeration.detail.contains("retry when the folder changes"))
    #expect(metadata == enumeration)
}

@Test
func unexpectedContentFailureUsesImplementedRecoveryPath() {
    let presentation = GlassContentFailurePresentation.make(for: .unexpected)

    #expect(presentation.status == "Needs attention")
    #expect(presentation.title == "This Glass couldn't continue")
    #expect(presentation.detail.contains("Restart SchneeGlass"))
    #expect(presentation.detail.contains("remove this Glass"))
    #expect(presentation.detail.contains("add the folder again"))
    #expect(!presentation.detail.contains("Recovery"))
    #expect(!presentation.detail.contains("reconnect"))
    #expect(!presentation.detail.contains("folder changes"))
}

@Test
func unavailableFolderGuidanceDoesNotPresentPendingCopyRecoveryAsSourceReconnect() {
    let presentation = GlassUnavailablePresentation.current

    #expect(presentation.title == "Folder unavailable")
    #expect(presentation.detail.contains("Restart SchneeGlass"))
    #expect(presentation.detail.contains("remove this Glass"))
    #expect(presentation.detail.contains("add the folder again"))
    #expect(presentation.detail.contains("Pending Copy Recovery"))
    #expect(!presentation.detail.contains("Reconnect support"))
}

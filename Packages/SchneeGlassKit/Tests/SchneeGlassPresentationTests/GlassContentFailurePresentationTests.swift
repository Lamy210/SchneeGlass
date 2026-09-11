import SchneeGlassApplication
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
func unexpectedContentFailureDoesNotPromiseAutomaticRetry() {
    let presentation = GlassContentFailurePresentation.make(for: .unexpected)

    #expect(presentation.status == "Needs reconnect")
    #expect(presentation.title == "This Glass needs to reconnect")
    #expect(presentation.detail.contains("Restart SchneeGlass"))
    #expect(!presentation.detail.contains("folder changes"))
}

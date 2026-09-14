import Darwin
import Testing
@testable import SchneeGlassFileSystemAdapter

@Test
func destinationEntryLookupClassifierTreatsSuccessfulStatAsExisting() {
    #expect(
        DestinationEntryLookupClassifier.classify(result: 0, error: 0)
            == .exists
    )
}

@Test
func destinationEntryLookupClassifierTreatsOnlyMissingEntryAsAbsent() {
    #expect(
        DestinationEntryLookupClassifier.classify(result: -1, error: ENOENT)
            == .absent
    )
}

@Test
func destinationEntryLookupClassifierTreatsLookupFailuresAsUnknown() {
    #expect(
        DestinationEntryLookupClassifier.classify(result: -1, error: EACCES)
            == .unknown
    )
    #expect(
        DestinationEntryLookupClassifier.classify(result: -1, error: EIO)
            == .unknown
    )
    #expect(
        DestinationEntryLookupClassifier.classify(result: -1, error: EBADF)
            == .unknown
    )
}

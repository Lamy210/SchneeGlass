import Darwin
import Testing
@testable import SchneeGlassFileSystemAdapter

@Test
func destinationCommitPreflightClassifierPreservesStagingOpenFailures() {
    #expect(
        DestinationCommitErrnoClassifier.classifyStagingOpen(ENOENT)
            == .stagingMissing
    )
    #expect(
        DestinationCommitErrnoClassifier.classifyStagingOpen(ELOOP)
            == .unexpectedFileType
    )
    #expect(
        DestinationCommitErrnoClassifier.classifyStagingOpen(EACCES)
            == .permissionDenied
    )
    #expect(
        DestinationCommitErrnoClassifier.classifyStagingOpen(EPERM)
            == .permissionDenied
    )
    #expect(
        DestinationCommitErrnoClassifier.classifyStagingOpen(EIO)
            == .commitFailed
    )
}

@Test
func destinationCommitPreflightClassifierDistinguishesAbsentFinalFromLookupFailure() {
    #expect(
        DestinationCommitErrnoClassifier.classifyDestinationLookup(ENOENT)
            == .destinationAbsent
    )
    #expect(
        DestinationCommitErrnoClassifier.classifyDestinationLookup(EACCES)
            == .permissionDenied
    )
    #expect(
        DestinationCommitErrnoClassifier.classifyDestinationLookup(EPERM)
            == .permissionDenied
    )
    #expect(
        DestinationCommitErrnoClassifier.classifyDestinationLookup(EIO)
            == .commitFailed
    )
}

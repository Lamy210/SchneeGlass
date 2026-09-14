import Darwin
import Testing
@testable import SchneeGlassFileSystemAdapter

@Test
func destinationCommitErrnoClassifierPreservesCollisionAndMissingStaging() {
    #expect(
        DestinationCommitErrnoClassifier.classify(EEXIST)
            == StagingCommitError.collision
    )
    #expect(
        DestinationCommitErrnoClassifier.classify(ENOENT)
            == StagingCommitError.stagingMissing
    )
}

@Test
func destinationCommitErrnoClassifierTreatsReadOnlyFilesystemAsDestinationUnavailable() {
    #expect(
        DestinationCommitErrnoClassifier.classify(EROFS)
            == StagingCommitError.destinationUnavailable
    )
}

@Test
func destinationCommitErrnoClassifierPreservesPermissionErrors() {
    #expect(
        DestinationCommitErrnoClassifier.classify(EACCES)
            == StagingCommitError.permissionDenied
    )
    #expect(
        DestinationCommitErrnoClassifier.classify(EPERM)
            == StagingCommitError.permissionDenied
    )
}

@Test
func destinationCommitErrnoClassifierPreservesCapacityErrors() {
    #expect(
        DestinationCommitErrnoClassifier.classify(ENOSPC)
            == StagingCommitError.insufficientSpace
    )
    #expect(
        DestinationCommitErrnoClassifier.classify(EDQUOT)
            == StagingCommitError.insufficientSpace
    )
}

@Test
func destinationCommitErrnoClassifierPreservesUnknownErrno() {
    #expect(
        DestinationCommitErrnoClassifier.classify(EIO)
            == StagingCommitError.commitFailed
    )
}

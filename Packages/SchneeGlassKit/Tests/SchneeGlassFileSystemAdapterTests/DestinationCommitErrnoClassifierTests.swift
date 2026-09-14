import Darwin
import Testing
@testable import SchneeGlassFileSystemAdapter

@Test
func destinationCommitErrnoClassifierPreservesCollisionAndMissingStaging() {
    #expect(DestinationCommitErrnoClassifier.classify(EEXIST) == .collision)
    #expect(DestinationCommitErrnoClassifier.classify(ENOENT) == .stagingMissing)
}

@Test
func destinationCommitErrnoClassifierTreatsReadOnlyFilesystemAsDestinationUnavailable() {
    #expect(DestinationCommitErrnoClassifier.classify(EROFS) == .destinationUnavailable)
}

@Test
func destinationCommitErrnoClassifierPreservesPermissionErrors() {
    #expect(DestinationCommitErrnoClassifier.classify(EACCES) == .permissionDenied)
    #expect(DestinationCommitErrnoClassifier.classify(EPERM) == .permissionDenied)
}

@Test
func destinationCommitErrnoClassifierPreservesCapacityErrors() {
    #expect(DestinationCommitErrnoClassifier.classify(ENOSPC) == .insufficientSpace)
    #expect(DestinationCommitErrnoClassifier.classify(EDQUOT) == .insufficientSpace)
}

@Test
func destinationCommitErrnoClassifierPreservesUnknownErrno() {
    #expect(DestinationCommitErrnoClassifier.classify(EIO) == .commitFailed)
}

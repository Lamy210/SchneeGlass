import Darwin
import Testing
@testable import SchneeGlassFileSystemAdapter

@Test
func destinationWriteErrnoClassifierTreatsReadOnlyFilesystemAsDestinationUnavailable() {
    #expect(
        DestinationWriteErrnoClassifier.classify(EROFS)
            == SourceFileLeaseError.destinationUnavailable
    )
}

@Test
func destinationWriteErrnoClassifierPreservesPermissionErrors() {
    #expect(
        DestinationWriteErrnoClassifier.classify(EACCES)
            == SourceFileLeaseError.permissionDenied
    )
    #expect(
        DestinationWriteErrnoClassifier.classify(EPERM)
            == SourceFileLeaseError.permissionDenied
    )
}

@Test
func destinationWriteErrnoClassifierPreservesCapacityErrors() {
    #expect(
        DestinationWriteErrnoClassifier.classify(ENOSPC)
            == SourceFileLeaseError.insufficientSpace
    )
    #expect(
        DestinationWriteErrnoClassifier.classify(EDQUOT)
            == SourceFileLeaseError.insufficientSpace
    )
}

@Test
func destinationWriteErrnoClassifierPreservesUnknownErrno() {
    #expect(
        DestinationWriteErrnoClassifier.classify(EIO)
            == SourceFileLeaseError.copyFailed(EIO)
    )
}

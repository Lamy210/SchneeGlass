import Testing
@testable import SchneeGlassFileSystemAdapter

@Test
func destinationStorageWritabilityClassifierRejectsUnknownVolumeReadOnlyState() {
    #expect(
        DestinationStorageWritabilityClassifier.isWritable(
            volumeIsReadOnly: nil,
            pathAppearsWritable: true
        ) == false
    )
}

@Test
func destinationStorageWritabilityClassifierRejectsReadOnlyVolume() {
    #expect(
        DestinationStorageWritabilityClassifier.isWritable(
            volumeIsReadOnly: true,
            pathAppearsWritable: true
        ) == false
    )
}

@Test
func destinationStorageWritabilityClassifierRejectsNonWritablePath() {
    #expect(
        DestinationStorageWritabilityClassifier.isWritable(
            volumeIsReadOnly: false,
            pathAppearsWritable: false
        ) == false
    )
}

@Test
func destinationStorageWritabilityClassifierAcceptsKnownWritableVolumeAndPath() {
    #expect(
        DestinationStorageWritabilityClassifier.isWritable(
            volumeIsReadOnly: false,
            pathAppearsWritable: true
        ) == true
    )
}

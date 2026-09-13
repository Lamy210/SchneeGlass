import FileDomain
import Testing
@testable import SchneeGlassFileSystemAdapter

@Test
func destinationStorageLocationClassifierRejectsUnknownLocality() {
    #expect(
        DestinationStorageLocationClassifier.locationKind(
            isLocal: nil,
            isRemovable: false
        ) == nil
    )
}

@Test
func destinationStorageLocationClassifierClassifiesNetworkVolume() {
    #expect(
        DestinationStorageLocationClassifier.locationKind(
            isLocal: false,
            isRemovable: false
        ) == .network
    )
}

@Test
func destinationStorageLocationClassifierClassifiesRemovableLocalVolume() {
    #expect(
        DestinationStorageLocationClassifier.locationKind(
            isLocal: true,
            isRemovable: true
        ) == .localRemovable
    )
}

@Test
func destinationStorageLocationClassifierClassifiesFixedLocalVolumeWhenRemovabilityIsUnknown() {
    #expect(
        DestinationStorageLocationClassifier.locationKind(
            isLocal: true,
            isRemovable: nil
        ) == .localFixed
    )
}

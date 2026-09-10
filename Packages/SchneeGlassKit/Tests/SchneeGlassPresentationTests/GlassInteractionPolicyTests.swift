import FileDomain
import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing
@testable import SchneeGlassPresentation

@Test
func removalAvailabilityMatchesDropInteractionLifecycle() throws {
    #expect(GlassInteractionPolicy.allowsRemoval(during: .idle))
    #expect(GlassInteractionPolicy.allowsRemoval(during: .dropInvalid(.collision)))
    #expect(!GlassInteractionPolicy.allowsRemoval(during: .hovered))

    let destinationURL = URL(fileURLWithPath: "/tmp/DropDestination", isDirectory: true)
    let destination = DestinationDescriptor(
        glassID: GlassID(),
        folderIdentity: FolderIdentity(resourceIdentifier: "destination", standardizedURL: destinationURL),
        url: destinationURL,
        capabilities: StorageCapabilities(
            locationKind: .localFixed,
            isWritable: true,
            supportsSafeDestinationCommit: true
        )
    )
    let plan = try CopyBatchPlan(
        destination: destination,
        items: [
            CopyItemPlan(
                sourceURL: URL(fileURLWithPath: "/tmp/source.txt"),
                originalFilename: "source.txt",
                destinationFilename: "source.txt",
                expectedSize: 1
            )
        ]
    )

    #expect(!GlassInteractionPolicy.allowsRemoval(during: .dropValid(.copy(plan))))
    #expect(
        !GlassInteractionPolicy.allowsRemoval(
            during: .copying(
                CopyProgress(
                    currentIndex: 1,
                    totalCount: 1,
                    currentFilename: "source.txt"
                )
            )
        )
    )
}

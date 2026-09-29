import Foundation
import SchneeGlassDomain
import Testing

@testable import FileDomain

@Test
func sameDirectoryDropIgnoresItsOwnExistingDestinationEntry() {
  let destinationURL = URL(
    fileURLWithPath: "/tmp/SchneeGlassSameDirectory",
    isDirectory: true
  )
  let sourceURL = destinationURL.appendingPathComponent("already-here.txt")
  let destination = DestinationDescriptor(
    glassID: GlassID(),
    folderIdentity: FolderIdentity(
      resourceIdentifier: "destination",
      standardizedURL: destinationURL
    ),
    url: destinationURL,
    capabilities: StorageCapabilities(
      locationKind: .localFixed,
      isWritable: true,
      supportsSafeDestinationCommit: true
    )
  )
  let candidate = DropCandidate(
    url: sourceURL,
    kind: .regular,
    size: 12
  )

  let result = DropPlanner.plan(
    DropPlanningContext(
      candidates: [candidate],
      destination: destination,
      collidingSourceURLs: [sourceURL.standardizedFileURL]
    )
  )

  #expect(result == .noOperation)
}

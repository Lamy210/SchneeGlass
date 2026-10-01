import Foundation
import SchneeGlassApplication
import SchneeGlassPOSIXSupport

enum RecoveryDestinationRuntimeIdentityValidator {
  static func matchesAcquiredIdentity(_ access: FolderAccessHandle) -> Bool {
    if let expected = access.runtimeDirectoryIdentity {
      guard
        let observed = POSIXDirectoryIdentityReader.identity(
          at: access.url.standardizedFileURL
        )
      else {
        return false
      }

      return observed.device == expected.deviceIdentifier
        && observed.inode == expected.objectIdentifier
    }

    guard let expectedFingerprint = access.fingerprint else {
      // Compatibility path for access providers that cannot expose either descriptor-derived
      // identity or Foundation's boot-local resource identifiers.
      return true
    }

    // A volume identifier alone cannot distinguish two directories on the same volume. Match
    // the production destination-binding contract by requiring an exact directory resource ID
    // whenever descriptor-derived runtime identity is unavailable.
    guard let expectedResourceIdentifier = expectedFingerprint.resourceIdentifier else {
      return false
    }

    var keys: Set<URLResourceKey> = [.fileResourceIdentifierKey]
    if expectedFingerprint.volumeIdentifier != nil {
      keys.insert(.volumeIdentifierKey)
    }

    let values: URLResourceValues
    do {
      values = try access.url.standardizedFileURL.resourceValues(forKeys: keys)
    } catch {
      return false
    }

    if let expectedVolumeIdentifier = expectedFingerprint.volumeIdentifier {
      let observedVolumeIdentifier = values.volumeIdentifier.map { String(describing: $0) }
      guard observedVolumeIdentifier == expectedVolumeIdentifier else {
        return false
      }
    }

    let observedResourceIdentifier = values.fileResourceIdentifier.map { String(describing: $0) }
    return observedResourceIdentifier == expectedResourceIdentifier
  }
}

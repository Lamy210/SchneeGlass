import Foundation
import SchneeGlassApplication
import SchneeGlassPOSIXSupport

enum RecoveryDestinationRuntimeIdentityValidator {
    static func matchesAcquiredIdentity(_ access: FolderAccessHandle) -> Bool {
        if let expected = access.runtimeDirectoryIdentity {
            guard let observed = POSIXDirectoryIdentityReader.identity(
                at: access.url.standardizedFileURL
            ) else {
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

        var keys: Set<URLResourceKey> = []
        if expectedFingerprint.volumeIdentifier != nil {
            keys.insert(.volumeIdentifierKey)
        }
        if expectedFingerprint.resourceIdentifier != nil {
            keys.insert(.fileResourceIdentifierKey)
        }
        guard !keys.isEmpty else {
            return true
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

        if let expectedResourceIdentifier = expectedFingerprint.resourceIdentifier {
            let observedResourceIdentifier = values.fileResourceIdentifier.map { String(describing: $0) }
            guard observedResourceIdentifier == expectedResourceIdentifier else {
                return false
            }
        }

        return true
    }
}

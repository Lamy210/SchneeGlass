import Foundation
import SchneeGlassApplication
import SchneeGlassPOSIXSupport

enum RecoveryDestinationRuntimeIdentityValidator {
    static func matchesAcquiredIdentity(_ access: FolderAccessHandle) -> Bool {
        guard let expected = access.runtimeDirectoryIdentity else {
            // Older/fallback access paths may not have descriptor-derived runtime identity.
            // Preserve their existing compatibility behavior rather than inventing new authority.
            return true
        }

        guard let observed = POSIXDirectoryIdentityReader.identity(
            at: access.url.standardizedFileURL
        ) else {
            return false
        }

        return observed.device == expected.deviceIdentifier
            && observed.inode == expected.objectIdentifier
    }
}

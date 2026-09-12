import Foundation
import SchneeGlassApplication
import SchneeGlassPOSIXSupport
import Testing

func testRuntimeDirectoryIdentity(for url: URL) throws -> RuntimeDirectoryIdentity {
    let identity = try #require(POSIXDirectoryIdentityReader.identity(at: url))
    return RuntimeDirectoryIdentity(
        deviceIdentifier: identity.device,
        objectIdentifier: identity.inode
    )
}

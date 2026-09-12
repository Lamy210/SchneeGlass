import Foundation
import SchneeGlassPOSIXSupport

protocol RuntimeDirectoryIdentityReading: Sendable {
    func identity(for url: URL) async -> POSIXDirectoryIdentity?
}

struct POSIXRuntimeDirectoryIdentityReader: RuntimeDirectoryIdentityReading {
    func identity(for url: URL) async -> POSIXDirectoryIdentity? {
        POSIXDirectoryIdentityReader.identity(at: url)
    }
}

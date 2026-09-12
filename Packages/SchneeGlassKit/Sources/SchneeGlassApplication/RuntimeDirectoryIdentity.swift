/// Runtime-only physical directory identity captured while an authorized folder access is active.
///
/// This value deliberately does not conform to `Codable`: it is valid only for live-operation
/// continuity checks and must never become persistent folder authority. Concrete filesystem adapters
/// may derive these opaque coordinates from descriptor metadata such as POSIX device/object IDs.
public struct RuntimeDirectoryIdentity: Hashable, Sendable {
    public let deviceIdentifier: UInt64
    public let objectIdentifier: UInt64

    public init(deviceIdentifier: UInt64, objectIdentifier: UInt64) {
        self.deviceIdentifier = deviceIdentifier
        self.objectIdentifier = objectIdentifier
    }
}

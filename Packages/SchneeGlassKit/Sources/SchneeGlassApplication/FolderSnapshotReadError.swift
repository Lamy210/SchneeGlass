/// Semantic snapshot failures that affect the runtime lifecycle rather than representing a
/// transient enumeration or metadata failure.
///
/// Concrete snapshot adapters throw these errors so Application can fail closed without depending
/// on adapter-specific error types.
public enum FolderSnapshotReadError: Error, Hashable, Sendable {
    case rootIdentityMismatch
}

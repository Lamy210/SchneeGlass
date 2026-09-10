import SchneeGlassApplication

/// Declares the optimistic-concurrency capability implemented by `JSONConfigurationStore`.
/// The witness method lives with the store implementation so comparison and commit remain inside
/// the same actor-isolated persistence boundary.
extension JSONConfigurationStore: ConditionalConfigurationPersisting {}

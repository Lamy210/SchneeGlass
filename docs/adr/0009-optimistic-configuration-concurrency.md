# ADR 0009: Optimistic Configuration Concurrency

## Status

Accepted

## Context

SchneeGlass has multiple application commands that update the same persisted Glass configuration: Create Glass, Remove Glass, placement updates, position reset, bookmark refresh during restore, and Pending Copy destination reconnect.

`JSONConfigurationStore` is an actor, so each individual `load` or `save` call is serialized. That does not make an application-level `load -> derive -> save` sequence atomic. Two different use cases can both load the same generation, derive different replacements, and then save in sequence. The later save can silently overwrite the earlier writer even though both individual persistence calls are internally serialized.

This is especially unsafe for Pending Copy destination reconnect because a stale whole-configuration save can erase a concurrent user-visible configuration change or restore an obsolete destination mapping.

## Decision

Read-modify-write commands depend on `ConditionalConfigurationPersisting`, which extends `ConfigurationPersisting` with:

```swift
func save(
    _ configurations: [GlassConfiguration],
    ifCurrentMatches expectedCurrent: [GlassConfiguration]
) async throws -> Bool
```

The persistence implementation must compare the current configuration with `expectedCurrent` and commit the replacement as one serialized persistence operation.

`JSONConfigurationStore` performs the comparison and replacement while isolated to the same actor and without a suspension point between comparison and commit. If another in-process SchneeGlass writer changed the current configuration after the caller loaded its snapshot, the conditional save returns `false` and performs no configuration or backup mutation.

Application commands must not retry a rejected conditional save using their already-derived stale value. They surface an explicit stale/configuration-changed result or fail the command so the caller can start again from fresh state.

Unconditional `save(_:)` remains available for operations whose contract intentionally replaces the complete current state, including explicit persistence/recovery flows that already own their own validation boundary.

## Consequences

- Concurrent read-modify-write commands cannot silently clobber a newer in-process configuration generation.
- `JSONConfigurationStore` remains the concurrency authority; callers do not need to share an application-wide lock or know about each other.
- Create Glass must tear down any newly acquired runtime resources if its conditional commit loses the race.
- Remove, placement reset/update, and Pending Copy reconnect treat a rejected commit as stale state rather than as a successful write.
- A rejected conditional save creates no backup generation because no visible configuration mutation occurred.
- This protects against concurrent SchneeGlass writers in the same process. It does not claim cross-process compare-and-swap semantics for arbitrary external modification of the app-owned configuration files.

## Alternatives considered

### Shared application mutation lock

A global actor/gate around every configuration command would serialize current writers, but correctness would depend on every future writer remembering to participate. It also couples otherwise independent application use cases.

### Retry stale writes automatically

Retrying the same derived replacement after a conflict could still overwrite the concurrent writer. Safe retry would require reloading and re-running command-specific business logic, so commands fail stale and let their caller restart from fresh state instead.

### Rely on `JSONConfigurationStore` actor serialization

Actor serialization protects individual method calls only. It does not protect a sequence containing separate `load` and `save` calls, which is the lost-update race addressed here.

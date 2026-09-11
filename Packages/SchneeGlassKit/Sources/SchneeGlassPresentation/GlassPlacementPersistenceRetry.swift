import SchneeGlassDomain

private let placementPersistenceRetryDelayNanoseconds: UInt64 = 200_000_000

@MainActor
func retryPlacementPersistenceWhileBusy(
    retryDelayNanoseconds: UInt64,
    operation: @MainActor () async -> GlassPlacementPersistenceResult
) async {
    while !Task.isCancelled {
        let result = await operation()
        guard result == .busy else {
            return
        }

        do {
            try await Task.sleep(nanoseconds: retryDelayNanoseconds)
        } catch {
            return
        }
    }
}

public extension SchneeGlassWorkspaceModel {
    /// Persists a debounced Desktop Glass placement once configuration mutation is available.
    ///
    /// The caller owns cancellation. A newer placement or panel teardown should cancel the task so
    /// an older position can never be written after a more recent user interaction.
    func persistPlacementWhenAvailable(
        glassID: GlassID,
        placement: GlassPlacement
    ) async {
        await retryPlacementPersistenceWhileBusy(
            retryDelayNanoseconds: placementPersistenceRetryDelayNanoseconds
        ) {
            await self.persistPlacement(glassID: glassID, placement: placement)
        }
    }
}

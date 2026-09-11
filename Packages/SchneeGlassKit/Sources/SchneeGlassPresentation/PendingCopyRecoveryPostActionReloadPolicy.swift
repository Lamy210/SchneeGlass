/// A successful Recovery action may have changed or removed the record that produced the current
/// UI rows. If the mandatory post-action reload then fails, those old rows are no longer
/// authoritative and must not remain actionable.
enum PendingCopyRecoveryPostActionReloadPolicy {
    static func itemsAfterFailedReload<Item>(
        currentItems: [Item]
    ) -> [Item] {
        _ = currentItems
        return []
    }
}

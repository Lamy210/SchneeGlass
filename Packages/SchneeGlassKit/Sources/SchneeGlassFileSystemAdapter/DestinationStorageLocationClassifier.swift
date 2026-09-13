import FileDomain

enum DestinationStorageLocationClassifier {
    static func locationKind(
        isLocal: Bool?,
        isRemovable: Bool?
    ) -> StorageLocationKind? {
        guard let isLocal else {
            return nil
        }
        guard isLocal else {
            return .network
        }
        return isRemovable == true ? .localRemovable : .localFixed
    }
}

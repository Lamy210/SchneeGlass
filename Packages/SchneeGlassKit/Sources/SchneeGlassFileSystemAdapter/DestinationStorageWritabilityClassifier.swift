enum DestinationStorageWritabilityClassifier {
    static func isWritable(
        volumeIsReadOnly: Bool?,
        pathAppearsWritable: Bool
    ) -> Bool {
        guard volumeIsReadOnly == false else {
            return false
        }
        return pathAppearsWritable
    }
}

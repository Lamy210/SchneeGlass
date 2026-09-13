enum RegularSourceSemanticClassifier {
    static func isPlainFile(
        isAlias: Bool?,
        isPackage: Bool?
    ) -> Bool {
        isAlias == false && isPackage == false
    }
}

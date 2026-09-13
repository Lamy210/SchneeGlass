import Testing
@testable import SchneeGlassFileSystemAdapter

@Test
func regularSourceSemanticClassifierAcceptsExplicitPlainFileMetadata() {
    #expect(
        RegularSourceSemanticClassifier.isPlainFile(
            isAlias: false,
            isPackage: false
        )
    )
}

@Test
func regularSourceSemanticClassifierRejectsAliasMetadata() {
    #expect(
        !RegularSourceSemanticClassifier.isPlainFile(
            isAlias: true,
            isPackage: false
        )
    )
}

@Test
func regularSourceSemanticClassifierRejectsPackageMetadata() {
    #expect(
        !RegularSourceSemanticClassifier.isPlainFile(
            isAlias: false,
            isPackage: true
        )
    )
}

@Test
func regularSourceSemanticClassifierRejectsUnknownAliasMetadata() {
    #expect(
        !RegularSourceSemanticClassifier.isPlainFile(
            isAlias: nil,
            isPackage: false
        )
    )
}

@Test
func regularSourceSemanticClassifierRejectsUnknownPackageMetadata() {
    #expect(
        !RegularSourceSemanticClassifier.isPlainFile(
            isAlias: false,
            isPackage: nil
        )
    )
}

@Test
func regularSourceSemanticClassifierRejectsFullyUnknownMetadata() {
    #expect(
        !RegularSourceSemanticClassifier.isPlainFile(
            isAlias: nil,
            isPackage: nil
        )
    )
}

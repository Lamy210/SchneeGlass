import Foundation

struct SourceSemanticMetadata: Hashable, Sendable {
    let isAlias: Bool?
    let isPackage: Bool?
}

protocol SourceSemanticMetadataReading: Sendable {
    func metadata(at url: URL) throws -> SourceSemanticMetadata
}

struct FoundationSourceSemanticMetadataReader: SourceSemanticMetadataReading {
    func metadata(at url: URL) throws -> SourceSemanticMetadata {
        let values = try url.standardizedFileURL.resourceValues(forKeys: [
            .isAliasFileKey,
            .isPackageKey,
        ])
        return SourceSemanticMetadata(
            isAlias: values.isAliasFile,
            isPackage: values.isPackage
        )
    }
}

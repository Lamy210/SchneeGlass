import Foundation
import Testing
@testable import FileDomain

@Test(arguments: [
    FileKind.regular,
    .directory,
    .package,
    .alias,
    .symbolicLink,
    .unsupported
])
func fileKindIsSendableAndStable(kind: FileKind) {
    #expect(FileKind(rawValue: kind.rawValue) == kind)
}

@Test
func fileIdentityStandardizesURL() {
    let url = URL(fileURLWithPath: "/tmp/example/../file.txt")
    let identity = FileIdentity(resourceIdentifier: nil, standardizedURL: url)

    #expect(identity.standardizedURL.path == "/tmp/file.txt")
}

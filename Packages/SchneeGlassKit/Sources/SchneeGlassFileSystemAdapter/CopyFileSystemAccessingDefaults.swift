import Foundation

extension CopyFileSystemAccessing {
    func supportsCaseSensitiveNames(at url: URL) async -> Bool? {
        nil
    }

    func itemExists(at url: URL, operationID: UUID) async -> Bool {
        _ = operationID
        return await itemExists(at: url)
    }
}

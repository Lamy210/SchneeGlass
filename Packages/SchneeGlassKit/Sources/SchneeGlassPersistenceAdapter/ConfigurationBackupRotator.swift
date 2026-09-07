import Foundation

enum ConfigurationBackupRotator {
    static func removeBackups(
        _ urls: ArraySlice<URL>,
        fileManager: FileManager
    ) throws {
        for url in urls {
            try fileManager.removeItem(at: url)
        }
    }
}

import Darwin
import Foundation

enum ConfigurationBackupRotationError: Error, Hashable, Sendable {
    case invalidPath
    case unlinkFailed(Int32)
}

enum ConfigurationBackupRotator {
    static func removeBackups(_ urls: ArraySlice<URL>) throws {
        for url in urls {
            let candidate = url.standardizedFileURL
            guard let result = candidate.withUnsafeFileSystemRepresentation({ path -> (status: Int32, error: Int32)? in
                guard let path else {
                    return nil
                }

                let status = unlink(path)
                return (status, status == 0 ? 0 : errno)
            }) else {
                throw ConfigurationBackupRotationError.invalidPath
            }

            guard result.status == 0 else {
                throw ConfigurationBackupRotationError.unlinkFailed(result.error)
            }
        }
    }
}

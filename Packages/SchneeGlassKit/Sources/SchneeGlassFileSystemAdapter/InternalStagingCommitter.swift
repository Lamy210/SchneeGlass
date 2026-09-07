import Foundation

public enum StagingCommitError: Error, Hashable, Sendable {
    case invalidStagingFile
    case crossDirectoryCommit
    case collision
    case stagingMissing
    case commitFailed
}

protocol StagingCommitting: Sendable {
    func commit(stagingURL: URL, finalURL: URL) async throws
}

public actor InternalStagingCommitter: StagingCommitting {
    private let fileManager: FileManager

    public init() {
        self.fileManager = .default
    }

    init(fileManager: FileManager) {
        self.fileManager = fileManager
    }

    public func commit(stagingURL: URL, finalURL: URL) throws {
        let staging = stagingURL.standardizedFileURL
        let final = finalURL.standardizedFileURL

        guard staging.deletingLastPathComponent() == final.deletingLastPathComponent() else {
            throw StagingCommitError.crossDirectoryCommit
        }

        let stagingName = staging.lastPathComponent
        guard stagingName.hasPrefix(".schneeglass-copy-"), stagingName.hasSuffix(".partial") else {
            throw StagingCommitError.invalidStagingFile
        }

        guard fileManager.fileExists(atPath: staging.path) else {
            throw StagingCommitError.stagingMissing
        }

        guard !fileManager.fileExists(atPath: final.path) else {
            throw StagingCommitError.collision
        }

        do {
            try fileManager.moveItem(at: staging, to: final)
        } catch {
            if fileManager.fileExists(atPath: final.path) {
                throw StagingCommitError.collision
            }
            throw StagingCommitError.commitFailed
        }
    }
}

import Foundation

public enum DropCandidateAvailability: Hashable, Sendable {
    case available
    case sourceUnavailable
    case cloudPlaceholderUnavailable
}

public struct DropPlanningContext: Sendable {
    public let candidates: [DropCandidate]
    public let destination: DestinationDescriptor
    public let availabilityBySourceURL: [URL: DropCandidateAvailability]
    public let collidingSourceURLs: Set<URL>

    public init(
        candidates: [DropCandidate],
        destination: DestinationDescriptor,
        availabilityBySourceURL: [URL: DropCandidateAvailability] = [:],
        collidingSourceURLs: Set<URL> = []
    ) {
        self.candidates = candidates
        self.destination = destination
        self.availabilityBySourceURL = availabilityBySourceURL
        self.collidingSourceURLs = collidingSourceURLs
    }
}

public enum DropPlanner {
    public static func plan(_ context: DropPlanningContext) -> DropPlan {
        guard !context.candidates.isEmpty else {
            return .reject(.unsupportedItem)
        }

        if context.destination.capabilities.locationKind == .network {
            return .reject(.networkDestinationUnsupported)
        }

        guard context.destination.capabilities.isWritable else {
            return .reject(.destinationReadOnly)
        }

        let standardizedDestination = context.destination.url.standardizedFileURL
        let supportsCaseSensitiveNames =
            context.destination.capabilities.supportsCaseSensitiveNames ?? false
        var sameDirectoryCount = 0
        var plannedDestinationNames: Set<String> = []
        var copyItems: [CopyItemPlan] = []
        copyItems.reserveCapacity(context.candidates.count)

        for candidate in context.candidates {
            let sourceURL = candidate.url.standardizedFileURL

            switch context.availabilityBySourceURL[sourceURL] ?? .available {
            case .available:
                break
            case .sourceUnavailable:
                return .reject(.sourceUnavailable)
            case .cloudPlaceholderUnavailable:
                return .reject(.cloudPlaceholderUnavailable)
            }

            switch candidate.kind {
            case .regular:
                break
            case .directory:
                return .reject(.unsupportedFolder)
            case .package:
                return .reject(.unsupportedPackage)
            case .symbolicLink:
                return .reject(.unsupportedSymbolicLink)
            case .alias, .unsupported:
                return .reject(.unsupportedItem)
            }

            if context.collidingSourceURLs.contains(sourceURL) {
                return .reject(.collision)
            }

            if sourceURL.deletingLastPathComponent().standardizedFileURL == standardizedDestination {
                sameDirectoryCount += 1
            }

            let filename = sourceURL.lastPathComponent
            let destinationNameKey = collisionKey(
                for: filename,
                supportsCaseSensitiveNames: supportsCaseSensitiveNames
            )
            guard plannedDestinationNames.insert(destinationNameKey).inserted else {
                return .reject(.collision)
            }

            copyItems.append(
                CopyItemPlan(
                    sourceURL: sourceURL,
                    originalFilename: filename,
                    destinationFilename: filename,
                    expectedSize: candidate.size
                )
            )
        }

        if sameDirectoryCount == context.candidates.count {
            return .noOperation
        }

        if sameDirectoryCount > 0 {
            return .reject(.containsSameDirectoryItem)
        }

        do {
            return .copy(
                try CopyBatchPlan(
                    destination: context.destination,
                    items: copyItems
                )
            )
        } catch {
            return .reject(.unsupportedItem)
        }
    }

    private static func collisionKey(
        for filename: String,
        supportsCaseSensitiveNames: Bool
    ) -> String {
        let canonicallyNormalized = filename.precomposedStringWithCanonicalMapping
        if supportsCaseSensitiveNames {
            return canonicallyNormalized
        }
        return canonicallyNormalized.lowercased()
    }
}

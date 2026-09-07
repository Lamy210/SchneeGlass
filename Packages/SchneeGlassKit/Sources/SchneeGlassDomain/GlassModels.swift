import Foundation

public struct GlassID: Hashable, Codable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct ResourceFingerprint: Hashable, Codable, Sendable {
    public let volumeIdentifier: String?
    public let resourceIdentifier: String?

    public init(volumeIdentifier: String?, resourceIdentifier: String?) {
        self.volumeIdentifier = volumeIdentifier
        self.resourceIdentifier = resourceIdentifier
    }
}

public struct FolderSource: Hashable, Codable, Sendable {
    public let bookmarkData: Data
    public let lastKnownPath: String
    public let fingerprint: ResourceFingerprint?

    public init(bookmarkData: Data, lastKnownPath: String, fingerprint: ResourceFingerprint? = nil) {
        self.bookmarkData = bookmarkData
        self.lastKnownPath = lastKnownPath
        self.fingerprint = fingerprint
    }
}

public enum GlassPlacementValidationError: Error, Equatable, Sendable {
    case widthBelowMinimum
    case heightBelowMinimum
}

public struct GlassPlacement: Hashable, Codable, Sendable {
    public static let minimumWidth = 240.0
    public static let minimumHeight = 160.0
    public static let defaultWidth = 360.0
    public static let defaultHeight = 260.0

    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public let displayHint: String?

    public init(
        x: Double,
        y: Double,
        width: Double = Self.defaultWidth,
        height: Double = Self.defaultHeight,
        displayHint: String? = nil
    ) throws {
        guard width >= Self.minimumWidth else {
            throw GlassPlacementValidationError.widthBelowMinimum
        }
        guard height >= Self.minimumHeight else {
            throw GlassPlacementValidationError.heightBelowMinimum
        }

        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.displayHint = displayHint
    }

    private enum CodingKeys: String, CodingKey {
        case x, y, width, height, displayHint
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            x: container.decode(Double.self, forKey: .x),
            y: container.decode(Double.self, forKey: .y),
            width: container.decode(Double.self, forKey: .width),
            height: container.decode(Double.self, forKey: .height),
            displayHint: container.decodeIfPresent(String.self, forKey: .displayHint)
        )
    }
}

public enum GlassConfigurationValidationError: Error, Equatable, Sendable {
    case emptyTitle
    case titleTooLong
}

public struct GlassConfiguration: Hashable, Codable, Sendable {
    public let id: GlassID
    public let title: String
    public let source: FolderSource
    public let placement: GlassPlacement
    public let showOnAllSpaces: Bool
    public let createdAt: Date

    public init(
        id: GlassID = GlassID(),
        title: String,
        source: FolderSource,
        placement: GlassPlacement,
        showOnAllSpaces: Bool = false,
        createdAt: Date = Date()
    ) throws {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else {
            throw GlassConfigurationValidationError.emptyTitle
        }
        guard normalizedTitle.count <= 100 else {
            throw GlassConfigurationValidationError.titleTooLong
        }

        self.id = id
        self.title = normalizedTitle
        self.source = source
        self.placement = placement
        self.showOnAllSpaces = showOnAllSpaces
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, source, placement, showOnAllSpaces, createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(GlassID.self, forKey: .id),
            title: container.decode(String.self, forKey: .title),
            source: container.decode(FolderSource.self, forKey: .source),
            placement: container.decode(GlassPlacement.self, forKey: .placement),
            showOnAllSpaces: container.decode(Bool.self, forKey: .showOnAllSpaces),
            createdAt: container.decode(Date.self, forKey: .createdAt)
        )
    }
}

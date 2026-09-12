import Foundation

public struct GlassID: Hashable, Codable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

/// Boot/session-local filesystem identity used only while a resolved folder access is active.
///
/// Foundation's `volumeIdentifier` and `fileResourceIdentifier` are intentionally not persistent
/// across system restarts. This type therefore remains available to runtime safety code, but it must
/// never be treated as a persisted folder identity.
public struct ResourceFingerprint: Hashable, Codable, Sendable {
    public let volumeIdentifier: String?
    public let resourceIdentifier: String?

    public init(volumeIdentifier: String?, resourceIdentifier: String?) {
        self.volumeIdentifier = volumeIdentifier
        self.resourceIdentifier = resourceIdentifier
    }
}

/// Restart-safe supplemental identity for a security-scoped folder reference.
///
/// The security-scoped bookmark remains the primary persistent resource reference. These values are
/// persisted only when Foundation exposes restart-safe identifiers for the selected volume. A
/// document identifier is meaningful only together with its volume UUID because document IDs are
/// unique within a volume, not globally.
public struct PersistentFolderIdentity: Hashable, Codable, Sendable {
    public let volumeUUIDString: String?
    public let documentIdentifier: Int?

    public init(volumeUUIDString: String?, documentIdentifier: Int?) {
        self.volumeUUIDString = volumeUUIDString
        self.documentIdentifier = documentIdentifier
    }

    public var hasDirectoryIdentity: Bool {
        volumeUUIDString != nil && documentIdentifier != nil
    }
}

public struct FolderSource: Hashable, Codable, Sendable {
    public let bookmarkData: Data
    public let lastKnownPath: String

    /// Runtime-only compatibility value. New persistence never writes this field because its
    /// Foundation identifiers are not stable across a system restart.
    public let fingerprint: ResourceFingerprint?

    /// Optional restart-safe proof captured alongside the security-scoped bookmark.
    public let persistentIdentity: PersistentFolderIdentity?

    public init(
        bookmarkData: Data,
        lastKnownPath: String,
        fingerprint: ResourceFingerprint? = nil,
        persistentIdentity: PersistentFolderIdentity? = nil
    ) {
        self.bookmarkData = bookmarkData
        self.lastKnownPath = lastKnownPath
        self.fingerprint = fingerprint
        self.persistentIdentity = persistentIdentity
    }

    private enum CodingKeys: String, CodingKey {
        case bookmarkData
        case lastKnownPath
        case fingerprint
        case persistentIdentity
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bookmarkData = try container.decode(Data.self, forKey: .bookmarkData)
        lastKnownPath = try container.decode(String.self, forKey: .lastKnownPath)

        // Decode the legacy boot-local fingerprint so schema-v1 configuration/backups remain
        // readable. Production restore/reconnect code must not use it as restart-safe authority.
        fingerprint = try container.decodeIfPresent(ResourceFingerprint.self, forKey: .fingerprint)
        persistentIdentity = try container.decodeIfPresent(
            PersistentFolderIdentity.self,
            forKey: .persistentIdentity
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bookmarkData, forKey: .bookmarkData)
        try container.encode(lastKnownPath, forKey: .lastKnownPath)
        try container.encodeIfPresent(persistentIdentity, forKey: .persistentIdentity)

        // Never persist `fingerprint`: fileResourceIdentifier/volumeIdentifier are explicitly not
        // stable across system restarts. Legacy files that contain it are migrated on the next save.
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

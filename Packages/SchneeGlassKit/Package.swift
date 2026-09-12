// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SchneeGlassKit",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "SchneeGlassKit",
            targets: [
                "SchneeGlassDomain",
                "FileDomain",
                "SchneeGlassApplication",
                "SchneeGlassPresentation",
                "SchneeGlassDesignSystem",
                "SchneeGlassFileSystemAdapter",
                "SchneeGlassPersistenceAdapter",
                "SchneeGlassMacOSAdapter"
            ]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/sindresorhus/KeyboardShortcuts",
            exact: "2.4.0"
        ),
        .package(
            url: "https://github.com/pointfreeco/swift-snapshot-testing",
            exact: "1.19.4"
        )
    ],
    targets: [
        .target(name: "SchneeGlassDomain"),
        .target(
            name: "FileDomain",
            dependencies: ["SchneeGlassDomain"]
        ),
        .target(
            name: "SchneeGlassApplication",
            dependencies: ["SchneeGlassDomain", "FileDomain"]
        ),
        .target(name: "SchneeGlassDesignSystem"),
        .target(name: "SchneeGlassPOSIXSupport"),
        .target(
            name: "SchneeGlassPresentation",
            dependencies: [
                "SchneeGlassApplication",
                "SchneeGlassDomain",
                "FileDomain",
                "SchneeGlassDesignSystem"
            ]
        ),
        .target(
            name: "SchneeGlassFileSystemAdapter",
            dependencies: [
                "SchneeGlassApplication",
                "FileDomain",
                "SchneeGlassPOSIXSupport"
            ]
        ),
        .target(
            name: "SchneeGlassPersistenceAdapter",
            dependencies: [
                "SchneeGlassApplication",
                "SchneeGlassDomain",
                "SchneeGlassPOSIXSupport"
            ]
        ),
        .target(
            name: "SchneeGlassMacOSAdapter",
            dependencies: [
                "SchneeGlassApplication",
                "SchneeGlassDomain",
                .product(
                    name: "KeyboardShortcuts",
                    package: "KeyboardShortcuts"
                )
            ]
        ),
        .testTarget(
            name: "SchneeGlassDomainTests",
            dependencies: ["SchneeGlassDomain"]
        ),
        .testTarget(
            name: "FileDomainTests",
            dependencies: ["FileDomain"]
        ),
        .testTarget(
            name: "SchneeGlassApplicationTests",
            dependencies: ["SchneeGlassApplication"]
        ),
        .testTarget(
            name: "SchneeGlassPresentationTests",
            dependencies: [
                "SchneeGlassPresentation",
                "SchneeGlassApplication",
                "SchneeGlassDomain",
                "FileDomain"
            ]
        ),
        .testTarget(
            name: "SchneeGlassVisualSnapshotTests",
            dependencies: [
                "SchneeGlassPresentation",
                "SchneeGlassApplication",
                "SchneeGlassDomain",
                "FileDomain",
                .product(
                    name: "SnapshotTesting",
                    package: "swift-snapshot-testing"
                )
            ]
        ),
        .testTarget(
            name: "SchneeGlassPOSIXSupportTests",
            dependencies: ["SchneeGlassPOSIXSupport"]
        ),
        .testTarget(
            name: "SchneeGlassFileSystemAdapterTests",
            dependencies: [
                "SchneeGlassFileSystemAdapter",
                "SchneeGlassApplication",
                "SchneeGlassDomain",
                "FileDomain",
                "SchneeGlassPOSIXSupport"
            ]
        ),
        .testTarget(
            name: "SchneeGlassPersistenceAdapterTests",
            dependencies: [
                "SchneeGlassPersistenceAdapter",
                "SchneeGlassApplication",
                "SchneeGlassDomain"
            ]
        ),
        .testTarget(
            name: "SchneeGlassMacOSAdapterTests",
            dependencies: [
                "SchneeGlassMacOSAdapter",
                "SchneeGlassApplication",
                "SchneeGlassDomain"
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)

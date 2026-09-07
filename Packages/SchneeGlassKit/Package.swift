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
            dependencies: ["SchneeGlassApplication", "FileDomain"]
        ),
        .target(
            name: "SchneeGlassPersistenceAdapter",
            dependencies: ["SchneeGlassApplication", "SchneeGlassDomain"]
        ),
        .target(
            name: "SchneeGlassMacOSAdapter",
            dependencies: ["SchneeGlassApplication", "SchneeGlassDomain"]
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
            name: "SchneeGlassFileSystemAdapterTests",
            dependencies: [
                "SchneeGlassFileSystemAdapter",
                "SchneeGlassApplication",
                "SchneeGlassDomain",
                "FileDomain"
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)

// swift-tools-version: 6.2
import PackageDescription

let upcoming: [SwiftSetting] = [.enableUpcomingFeature("MemberImportVisibility")]

let package = Package(
    name: "EtagereKit",
    platforms: [.macOS("26.0"), .iOS("26.0"), .tvOS("27.0")],
    products: [
        .library(name: "EtagereKit", targets: ["EtagereKit"])
    ],
    targets: [
        // The Etagere: shelves of rotating card rings. Mirrors the app: MainActor default isolation; the model value
        // types and the ring geometry are explicitly nonisolated (docs/etagere.md §4.4).
        .target(
            name: "EtagereKit",
            swiftSettings: upcoming + [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "EtagereKitTests",
            dependencies: ["EtagereKit"],
            swiftSettings: upcoming + [.defaultIsolation(MainActor.self)]
        )
    ],
    swiftLanguageModes: [.v6]
)

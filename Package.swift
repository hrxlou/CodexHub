// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "CodexHub",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CodexHub", targets: ["CodexHub"])
    ],
    targets: [
        .executableTarget(
            name: "CodexHub",
            path: ".",
            exclude: [
                "Tools",
                "Tests",
                "build",
                "dist",
                "docs",
                "scripts",
                "build.sh",
                "LICENSE",
                "README.md",
                "THIRD_PARTY_NOTICES.md",
                "Resources/CodexHub.icns",
                "Resources/CodexHub.iconset",
                "Resources/CodexHubIcon.png",
                "Resources/CodexHubIconDark.png",
                "Resources/CodexHubIconLight.png",
                "Resources/CodexHubIconSource.png",
                "Resources/CodexHubMenuIcon.png"
            ],
            sources: [
                "Sources"
            ],
            resources: [
                .copy("Resources/PriceBook.json")
            ],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
        .testTarget(
            name: "CodexHubTests",
            dependencies: ["CodexHub"],
            path: "Tests/CodexHubTests"
        )
    ]
)

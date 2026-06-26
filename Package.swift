// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SpotifyLyrics",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "SpotifyLyricsCore",
            path: "Sources/SpotifyLyricsCore",
            swiftSettings: [.swiftLanguageMode(.v5), .unsafeFlags(["-enable-testing"])]
        ),
        .executableTarget(
            name: "SpotifyLyrics",
            dependencies: ["SpotifyLyricsCore"],
            path: "Sources/App",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "SpotifyLyricsTests",
            dependencies: ["SpotifyLyricsCore"],
            path: "Tests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)

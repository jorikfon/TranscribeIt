// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TranscribeIt",
    platforms: [.macOS(.v14)],
    dependencies: [
        // WhisperKit для распознавания речи на Apple Silicon
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0")
    ],
    targets: [
        // Библиотека с общими компонентами
        .target(
            name: "TranscribeItCore",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit")
            ],
            path: "Sources",
            exclude: [
                "App/TranscribeItApp.swift",
                "App/AppDelegate.swift"
            ]
        ),

        // Основное приложение
        .executableTarget(
            name: "TranscribeIt",
            dependencies: [
                "TranscribeItCore",
                .product(name: "WhisperKit", package: "WhisperKit")
            ],
            path: "Sources/App",
            sources: ["TranscribeItApp.swift", "AppDelegate.swift"]
        ),

        // Unit-тесты
        .testTarget(
            name: "TranscribeItCoreTests",
            dependencies: [
                "TranscribeItCore",
                .product(name: "WhisperKit", package: "WhisperKit")
            ],
            path: "Tests",
            exclude: [
                "README.md"
            ],
            resources: [
                .copy("Fixtures/audio")
            ]
        )
    ]
)

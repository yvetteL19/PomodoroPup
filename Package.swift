// swift-tools-version: 6.0
import PackageDescription

// Exercise the app's production model without launching its menu bar UI.
let package = Package(
    name: "PomodoroPup",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "PomodoroPupCore", targets: ["PomodoroPupCore"])
    ],
    targets: [
        .target(
            name: "PomodoroPupCore",
            path: "PomodoroPup",
            exclude: [
                "Assets.xcassets",
                "ContentView.swift",
                "DogView.swift",
                "OnboardingView.swift",
                "PomodoroPupApp.swift",
                "PomodoroPup.entitlements",
                "SettingsView.swift",
                "achievement.MP3",
                "bark.MP3",
                "sigh.MP3",
                "en.lproj",
                "zh-Hans.lproj"
            ],
            sources: [
                "DogViewModel.swift",
                "NotificationService.swift",
                "SoundManager.swift",
                "StateStore.swift",
                "TimerClock.swift"
            ]
        ),
        .testTarget(
            name: "PomodoroPupCoreTests",
            dependencies: ["PomodoroPupCore"]
        )
    ],
    swiftLanguageModes: [.v5]
)

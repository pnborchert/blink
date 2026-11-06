// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Blink",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Blink", targets: ["Blink"]),
    ],
    targets: [
        // Pure, AppKit-free logic (screen geometry, shortcuts, config). Unit tested.
        .target(name: "BlinkCore"),
        // The menu bar app: hotkeys, cursor warping, window focusing, UI.
        .executableTarget(
            name: "Blink",
            dependencies: ["BlinkCore"]
        ),
        .testTarget(
            name: "BlinkCoreTests",
            dependencies: ["BlinkCore"]
        ),
    ]
)

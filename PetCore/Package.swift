// swift-tools-version: 6.0
// Pure-Swift pet logic shared by the app and every extension.
// Must stay free of Apple-only frameworks (SwiftUI, ActivityKit, FamilyControls, ...)
// so it builds and tests on Linux: `swift test --package-path PetCore`.
import PackageDescription

let package = Package(
    name: "PetCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "PetCore", targets: ["PetCore"]),
    ],
    targets: [
        .target(name: "PetCore"),
        .testTarget(name: "PetCoreTests", dependencies: ["PetCore"]),
    ]
)

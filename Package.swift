// swift-tools-version: 5.9
import PackageDescription

// MaximizeCore holds all business logic so that CI can verify it without Xcode,
// a simulator, or a signed build. See CLAUDE.md — "thin shell, fat core".
let package = Package(
    name: "MaximizeCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "MaximizeCore", targets: ["MaximizeCore"]),
    ],
    targets: [
        .target(name: "MaximizeCore"),
        .testTarget(name: "MaximizeCoreTests", dependencies: ["MaximizeCore"]),
    ]
)

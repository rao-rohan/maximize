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
        // Test doubles (e.g. FakeAnthropicAPIKeyStore) shared by test targets. Kept
        // out of the MaximizeCore product itself so scaffolding never ships in the
        // app binary — see MAX-022.
        .target(name: "MaximizeCoreTestSupport", dependencies: ["MaximizeCore"]),
        .testTarget(
            name: "MaximizeCoreTests",
            dependencies: ["MaximizeCore", "MaximizeCoreTestSupport"]
        ),
    ]
)

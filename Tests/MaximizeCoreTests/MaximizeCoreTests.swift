import XCTest
@testable import MaximizeCore

/// Pipeline smoke test.
///
/// This asserts something trivial on purpose. Its job is to prove the harness runs
/// at all — that CI compiles the package, links the test target, and reports
/// failures — before any real logic depends on that guarantee.
final class MaximizeCoreTests: XCTestCase {
    func testVersionIsPresent() {
        XCTAssertFalse(MaximizeCore.version.isEmpty)
    }
}

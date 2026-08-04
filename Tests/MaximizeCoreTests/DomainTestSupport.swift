import Foundation
import XCTest
@testable import MaximizeCore

/// The *kind* of a `DomainError`, without its message payload.
///
/// Assertions match on this rather than on a fully-constructed error so a reworded
/// field name doesn't fail a test that is really about "this was rejected as
/// out-of-order".
enum DomainErrorKind: String {
    case outOfRange
    case notFinite
    case empty
    case outOfOrder
    case duplicate
    case inconsistent
    case malformed
}

extension DomainError {
    var kind: DomainErrorKind {
        switch self {
        case .outOfRange: return .outOfRange
        case .notFinite: return .notFinite
        case .empty: return .empty
        case .outOfOrder: return .outOfOrder
        case .duplicate: return .duplicate
        case .inconsistent: return .inconsistent
        case .malformed: return .malformed
        }
    }
}

func assertThrows<T>(
    _ expected: DomainErrorKind,
    _ expression: @autoclosure () throws -> T,
    _ message: String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertThrowsError(try expression(), message, file: file, line: line) { error in
        guard let domainError = error as? DomainError else {
            XCTFail("Expected DomainError.\(expected.rawValue), got \(error)", file: file, line: line)
            return
        }
        XCTAssertEqual(
            domainError.kind,
            expected,
            "Expected DomainError.\(expected.rawValue), got \(domainError)",
            file: file,
            line: line
        )
    }
}

/// Container for round-tripping. Several domain types encode as bare scalars, and
/// top-level JSON fragments are not portable across Foundation versions.
struct CodableBox<Wrapped: Codable>: Codable {
    let wrapped: Wrapped
}

func roundTripped<T: Codable & Equatable>(_ value: T) throws -> T {
    let data = try JSONEncoder().encode(CodableBox(wrapped: value))
    return try JSONDecoder().decode(CodableBox<T>.self, from: data).wrapped
}

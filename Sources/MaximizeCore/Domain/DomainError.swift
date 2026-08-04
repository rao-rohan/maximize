import Foundation

/// The single failure type the domain layer raises when a value would violate an
/// invariant.
///
/// Every validated initializer in `MaximizeCore` throws one of these. Keeping the
/// set small and structured (rather than a free-form message) means tests can assert
/// on the *reason* a value was rejected, not on prose that will be reworded later.
public enum DomainError: Error, Hashable, Sendable, CustomStringConvertible {
    /// A numeric value fell outside its permitted range. Bounds are inclusive; a nil
    /// bound means unbounded on that side.
    case outOfRange(field: String, value: Double, lowerBound: Double?, upperBound: Double?)

    /// A numeric value was NaN or infinite. Sensor pipelines produce these more often
    /// than one would like, and they poison every average computed downstream.
    case notFinite(field: String)

    /// A collection or string that must carry content was empty.
    case empty(field: String)

    /// An ordered collection was not ordered. `index` is the offending element's
    /// position.
    case outOfOrder(field: String, index: Int)

    /// A collection that must have unique keys had a repeat.
    case duplicate(field: String, key: String)

    /// Two or more fields were individually valid but contradicted each other.
    case inconsistent(reason: String)

    /// A textual value could not be parsed into the type it names.
    case malformed(field: String, value: String)

    public var description: String {
        switch self {
        case let .outOfRange(field, value, lower, upper):
            let low = lower.map { "\($0)" } ?? "-∞"
            let high = upper.map { "\($0)" } ?? "+∞"
            return "\(field) must be within [\(low), \(high)], got \(value)"
        case let .notFinite(field):
            return "\(field) must be a finite number"
        case let .empty(field):
            return "\(field) must not be empty"
        case let .outOfOrder(field, index):
            return "\(field) must be ordered; element at index \(index) breaks the order"
        case let .duplicate(field, key):
            return "\(field) contains a duplicate entry for \(key)"
        case let .inconsistent(reason):
            return reason
        case let .malformed(field, value):
            return "\(field) could not be parsed from \"\(value)\""
        }
    }
}

/// Shared guards used by validated initializers.
///
/// Internal on purpose: these are an implementation detail of the value types, not
/// part of the package's surface.
enum Validate {
    static func finite(_ value: Double, _ field: String) throws {
        guard value.isFinite else { throw DomainError.notFinite(field: field) }
    }

    static func nonNegative(_ value: Double, _ field: String) throws {
        try finite(value, field)
        guard value >= 0 else {
            throw DomainError.outOfRange(field: field, value: value, lowerBound: 0, upperBound: nil)
        }
    }

    static func positive(_ value: Double, _ field: String) throws {
        try finite(value, field)
        guard value > 0 else {
            throw DomainError.outOfRange(field: field, value: value, lowerBound: 0, upperBound: nil)
        }
    }

    static func within(_ value: Double, _ range: ClosedRange<Double>, _ field: String) throws {
        try finite(value, field)
        guard range.contains(value) else {
            throw DomainError.outOfRange(
                field: field,
                value: value,
                lowerBound: range.lowerBound,
                upperBound: range.upperBound
            )
        }
    }

    static func optionalNonNegative(_ value: Double?, _ field: String) throws {
        guard let value else { return }
        try nonNegative(value, field)
    }

    static func optionalPositive(_ value: Double?, _ field: String) throws {
        guard let value else { return }
        try positive(value, field)
    }

    static func optionalWithin(_ value: Double?, _ range: ClosedRange<Double>, _ field: String) throws {
        guard let value else { return }
        try within(value, range, field)
    }

    /// Rejects strings that are empty or whitespace-only.
    static func nonEmpty(_ text: String, _ field: String) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DomainError.empty(field: field)
        }
    }
}

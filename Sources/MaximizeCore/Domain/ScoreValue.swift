import Foundation

/// An effectiveness score: an integer 0...100 (PRD §10.3).
///
/// A separate type rather than an `Int` so that "101" cannot exist anywhere in the
/// system — not in a rubric band, not in a manual annotation, not in a decoded
/// record. Every producer of a score has to pass through this door.
public struct ScoreValue: Hashable, Sendable, Comparable, Codable, CustomStringConvertible {
    /// The permitted range, exposed so rubric authoring and UI can reference it
    /// rather than restating `0...100`.
    public static let permittedRange: ClosedRange<Int> = 0...100

    public let points: Int

    public init(_ points: Int) throws {
        guard ScoreValue.permittedRange.contains(points) else {
            throw DomainError.outOfRange(
                field: "ScoreValue.points",
                value: Double(points),
                lowerBound: Double(ScoreValue.permittedRange.lowerBound),
                upperBound: Double(ScoreValue.permittedRange.upperBound)
            )
        }
        self.points = points
    }

    private init(unchecked points: Int) {
        self.points = points
    }

    /// For call sites that are computing a score and would rather saturate than fail
    /// — e.g. a rubric arithmetic result of 103. Rejecting is still the default;
    /// this is opt-in and named so it shows up in review.
    public static func clamping(_ points: Int) -> ScoreValue {
        ScoreValue(unchecked: min(permittedRange.upperBound, max(permittedRange.lowerBound, points)))
    }

    public static let zero = ScoreValue(unchecked: 0)
    public static let maximum = ScoreValue(unchecked: 100)

    /// The default effective-day threshold from D4/§10.4. It is only a *default*:
    /// the threshold actually applied lives in the plan's rubric, because changing it
    /// must be a new plan version rather than a code change (D1).
    public static let defaultEffectiveThreshold = ScoreValue(unchecked: 70)

    public static func < (lhs: ScoreValue, rhs: ScoreValue) -> Bool {
        lhs.points < rhs.points
    }

    public var description: String { "\(points)" }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(container.decode(Int.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(points)
    }
}

/// An inclusive band of scores, as written in a rubric ("easy run, on cap, low drift
/// → 90–100").
public struct ScoreRange: Hashable, Sendable, Codable, CustomStringConvertible {
    public let lowest: ScoreValue
    public let highest: ScoreValue

    public init(lowest: ScoreValue, highest: ScoreValue) throws {
        guard lowest <= highest else {
            throw DomainError.inconsistent(
                reason: "ScoreRange.lowest (\(lowest)) must not exceed highest (\(highest))"
            )
        }
        self.lowest = lowest
        self.highest = highest
    }

    public init(lowest: Int, highest: Int) throws {
        try self.init(lowest: ScoreValue(lowest), highest: ScoreValue(highest))
    }

    public func contains(_ score: ScoreValue) -> Bool {
        score >= lowest && score <= highest
    }

    /// The midpoint, rounded down — a reasonable "pick a number in this band" default
    /// for a scorer that has matched a band but has nothing finer to say.
    public var midpoint: ScoreValue {
        ScoreValue.clamping((lowest.points + highest.points) / 2)
    }

    public var description: String { "\(lowest)–\(highest)" }

    private enum CodingKeys: String, CodingKey {
        case lowest, highest
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            lowest: container.decode(ScoreValue.self, forKey: .lowest),
            highest: container.decode(ScoreValue.self, forKey: .highest)
        )
    }
}

/// Monotonically increasing plan version (D1). Version 1 is the first plan; there is
/// no version 0.
public struct PlanVersion: Hashable, Sendable, Comparable, Codable, CustomStringConvertible {
    public let number: Int

    public init(_ number: Int) throws {
        guard number >= 1 else {
            throw DomainError.outOfRange(
                field: "PlanVersion.number", value: Double(number), lowerBound: 1, upperBound: nil
            )
        }
        self.number = number
    }

    public static func < (lhs: PlanVersion, rhs: PlanVersion) -> Bool {
        lhs.number < rhs.number
    }

    public var description: String { "v\(number)" }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(container.decode(Int.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(number)
    }
}

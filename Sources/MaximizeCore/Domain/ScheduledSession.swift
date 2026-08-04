import Foundation

/// What the plan asks for on a given day.
///
/// `rest` exists only on the scheduled side — you cannot *perform* a rest — which is
/// why this is a separate type from `WorkoutClassification` rather than one enum with
/// a case that is illegal in half its uses.
public enum ScheduledSessionKind: String, Hashable, Sendable, Codable, CaseIterable {
    case easy
    case long
    case hard
    case rest
    /// Scheduled, but not one of the three run types the rubric reasons about
    /// (cross-training, strength, mobility).
    case other

    public init(_ classification: WorkoutClassification) {
        switch classification {
        case .easy: self = .easy
        case .long: self = .long
        case .hard: self = .hard
        case .other: self = .other
        }
    }
}

/// What the athlete actually did, as classified from workout type + HR profile
/// (§10.2). MAX-013 owns the classifier; this is the vocabulary it speaks.
public enum WorkoutClassification: String, Hashable, Sendable, Codable, CaseIterable {
    case easy
    case long
    case hard
    case other

    /// Drift is "near-meaningless on interval/hard runs" (§9), so it is surfaced
    /// conditionally. Encoding that here keeps the rule in one place instead of in
    /// every view that draws a drift number.
    public var driftIsMeaningful: Bool {
        self == .easy || self == .long
    }
}

/// A prescribed session: the plan's ask for one day (PRD §8 `plan_day`'s
/// `scheduled_session` + `scheduled_distance`, folded into one value because the
/// distance is meaningless without the kind it qualifies).
public struct ScheduledSession: Hashable, Sendable, Codable {
    public let kind: ScheduledSessionKind

    /// Prescribed distance in **meters**, or nil where the plan prescribes a session
    /// without a distance (e.g. "hard: 6 × 800m" is captured in `note` until the plan
    /// model grows structure for intervals).
    public let distanceMeters: Double?

    /// Free text from the plan, shown in the verdict header and passed to the scorer
    /// as context.
    public let note: String?

    public init(kind: ScheduledSessionKind, distanceMeters: Double? = nil, note: String? = nil) throws {
        try Validate.optionalPositive(distanceMeters, "ScheduledSession.distanceMeters")
        guard !(kind == .rest && distanceMeters != nil) else {
            throw DomainError.inconsistent(reason: "A rest day cannot carry a scheduled distance")
        }
        self.kind = kind
        self.distanceMeters = distanceMeters
        self.note = note
    }

    private init(uncheckedKind kind: ScheduledSessionKind) {
        self.kind = kind
        self.distanceMeters = nil
        self.note = nil
    }

    /// The canonical rest day. A constant rather than a computed value so identity
    /// comparisons in tests and templates read cleanly.
    public static let rest = ScheduledSession(uncheckedKind: .rest)

    public var isRest: Bool { kind == .rest }

    private enum CodingKeys: String, CodingKey {
        case kind, distanceMeters, note
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            kind: container.decode(ScheduledSessionKind.self, forKey: .kind),
            distanceMeters: container.decodeIfPresent(Double.self, forKey: .distanceMeters),
            note: container.decodeIfPresent(String.self, forKey: .note)
        )
    }
}

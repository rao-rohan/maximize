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
    /// (cross-training, mobility). Strength work left this case when `.lift` arrived —
    /// A17's argument is that a discipline the plan sets goals about cannot be the
    /// residual, because the residual is by definition the cheapest thing to forgive.
    case other

    /// A prescribed lifting session (A16, A17).
    ///
    /// **Appended, not inserted.** `CaseIterable` order is what the plan screen prints a
    /// band's `appliesTo` list in, so putting `.lift` anywhere but last would reorder
    /// copy the athlete already reads.
    ///
    /// Nothing can prescribe one yet: the weekly template still has a single slot per
    /// weekday and MAX-111 is what gives it a second. `ScheduledSessionKind.prescribable`
    /// is what keeps the authoring picker honest about that in the meantime.
    case lift

    public init(_ classification: WorkoutClassification) {
        switch classification {
        case .easy: self = .easy
        case .long: self = .long
        case .hard: self = .hard
        case .other: self = .other
        // The only mapping A17 permits. Sending a lift to `.other` here would put it
        // back in the residual the case above just took it out of.
        case .lift: self = .lift
        }
    }

    /// The kinds a weekly template may actually prescribe today.
    ///
    /// `.lift` is in the vocabulary before there is anywhere to put it. Offering it in
    /// the only slot that exists would let the athlete prescribe a lift where the run
    /// ask goes, and the day's run would then be judged against a lift ask — the exact
    /// cross-discipline judgement A17 exists to make impossible. MAX-111 gives the
    /// template its second slot; MAX-119 gives the screen its second row set, and this
    /// property is what they replace.
    ///
    /// In the core rather than in the picker that reads it because "what may be
    /// prescribed" is a rule about the plan, and a rule in a view is a rule CI never
    /// checks.
    public static let prescribable: [ScheduledSessionKind] = Self.allCases.filter { $0 != .lift }
}

/// What the athlete actually did, as classified from workout type + HR profile
/// (§10.2). MAX-013 owns the classifier; this is the vocabulary it speaks.
public enum WorkoutClassification: String, Hashable, Sendable, Codable, CaseIterable {
    case easy
    case long
    case hard
    case other

    /// A lifting session (A16, A17).
    ///
    /// **Appended, not inserted**, for the same `CaseIterable`-order reason
    /// `ScheduledSessionKind.lift` is.
    ///
    /// Nothing produces one yet: `WorkoutClassifier` still answers `.other` for every
    /// non-run, and MAX-111's gate leaves a lift unscored, so no stored `Score` can
    /// carry this. It exists so the rest of the lifting build has a word for what a
    /// lift *is* — and because expressing one as `.other` is backwards, per A17.
    case lift

    /// Drift is "near-meaningless on interval/hard runs" (§9), so it is surfaced
    /// conditionally. Encoding that here keeps the rule in one place instead of in
    /// every view that draws a drift number.
    ///
    /// A `switch` rather than the `==` chain it replaces: the chain answered `false`
    /// for any case added later without anyone being asked, which is correct for
    /// `.lift` — drift measures cardiac cost creeping up at a held effort, and a lift
    /// holds no effort — but would have been correct only by luck for the next one.
    public var driftIsMeaningful: Bool {
        switch self {
        case .easy, .long: return true
        case .hard, .other, .lift: return false
        }
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

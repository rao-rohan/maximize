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
    /// The weekly template has had a second slot since MAX-129, the authoring screen
    /// can prescribe one as of MAX-137, and a chat proposal can as of MAX-141 — each
    /// through the lift slot's own picker or wire field (`liftPrescribable`), never
    /// through `prescribable`, which still gates the run slot only.
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

    /// The kinds the **run** slot may be set to.
    ///
    /// Offering `.lift` here would let the athlete prescribe a lift where the run ask
    /// goes, and the day's run would then be judged against a lift ask: the exact
    /// cross-discipline judgement A17 exists to make impossible. MAX-137 gives the lift
    /// slot its own picker and its own vocabulary (`liftPrescribable`) rather than
    /// widening this one, so a lift can never reach the run picker no matter how the
    /// screen grows.
    ///
    /// In the core rather than in the picker that reads it because "what may be
    /// prescribed" is a rule about the plan, and a rule in a view is a rule CI never
    /// checks.
    public static let prescribable: [ScheduledSessionKind] = Self.allCases.filter { $0 != .lift }

    /// The kinds the **lift** slot may be set to (MAX-137).
    ///
    /// Not `prescribable` minus one case swapped for another — a genuinely smaller,
    /// different vocabulary. The run slot distinguishes easy/long/hard/other because the
    /// rubric reasons about those distinctly; the lift slot has no such gradient
    /// (LIFTING-SPEC §3.5 — the only bands a lift day can match are adherence bands over
    /// `.lift` itself, there is no "long lift" or "hard lift" the plan can ask for). So a
    /// lift day is either prescribed or it is not: two cases, not the run slot's five.
    /// Offering `.easy`, `.long`, `.hard` or `.other` here would let a plan write a
    /// run-shaped ask into the lift slot — the same cross-discipline confusion
    /// `prescribable` exists to keep out of the run slot, arriving from the other side.
    public static let liftPrescribable: [ScheduledSessionKind] = [.rest, .lift]
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
    /// non-run, so a lift scored under MAX-168's opened gate stores `.other` as its
    /// classification while being judged by a band that names `.lift` — the rubric reads
    /// the *discipline*, a fact, and never this, a judgement (see
    /// `RubricCondition.actualDiscipline`). Teaching the classifier to answer `.lift` is
    /// its own ticket. The case exists so the rest of the lifting build has a word for
    /// what a lift *is* — and because expressing one as `.other` is backwards, per A17.
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

    /// Prescribed duration in **seconds**, or nil where the plan prescribes a session
    /// without one.
    ///
    /// **The plan's first duration, and the closure of tracker gap P3** ("`Plan` records
    /// no durations at all"). It arrives because a lift has no distance to be prescribed
    /// in: A20 scores a lift on whether the session the plan asked for happened, and "for
    /// roughly how long" is the only part of that judgement the record can measure. A run
    /// may carry one too — the field is about what a plan may *say*, and "45 minutes
    /// easy" is a sentence a plan says — but nothing authors one for a run today.
    ///
    /// **Optional on a lift as well, on purpose.** "Lift on Tuesday, length unstated" is
    /// a thing a plan may mean, and it is a different statement from `.rest`. A rubric
    /// band written against `.scheduledDuration` simply does not match on such a day —
    /// see `RubricEvaluator`, which treats an unresolvable reference as no-match, exactly
    /// as it already does for a `.scheduledDistance` on a day with no prescribed
    /// distance. Requiring a duration would make the shorter statement inexpressible to
    /// buy a guarantee the evaluator does not need.
    public let durationSeconds: Double?

    /// Free text from the plan, shown in the verdict header and passed to the scorer
    /// as context.
    public let note: String?

    /// What a prescribed lift is for — "Tuesday is chest and shoulders".
    ///
    /// A **set**, because a real session is rarely one group and a plan that forced one
    /// would be wrong the first time it was used. Empty on every session that is not a
    /// lift, and legitimately empty on a lift as well: "lift on Tuesday, groups
    /// unstated" is a thing a plan may say, and it is a different statement from "no
    /// lift on Tuesday", which is `.rest`. Both remain expressible, which is what keeps
    /// the lift slot's totality meaningful rather than merely non-nil.
    ///
    /// **Nothing checks this.** HealthKit does not report which muscles a strength
    /// workout worked, so a prescription of chest-and-shoulders cannot be verified any
    /// more than a set count can (A20). See `MuscleGroup` — this is what a plan may
    /// state, and no scoring, tallies or adherence code reads it.
    public let muscleGroups: Set<MuscleGroup>

    public init(
        kind: ScheduledSessionKind,
        distanceMeters: Double? = nil,
        durationSeconds: Double? = nil,
        note: String? = nil,
        muscleGroups: Set<MuscleGroup> = []
    ) throws {
        try Validate.optionalPositive(distanceMeters, "ScheduledSession.distanceMeters")
        try Validate.optionalPositive(durationSeconds, "ScheduledSession.durationSeconds")
        guard !(kind == .rest && distanceMeters != nil) else {
            throw DomainError.inconsistent(reason: "A rest day cannot carry a scheduled distance")
        }
        // The same rule as the line above, for the same reason: a rest day asks for
        // nothing, so a length attached to one is a number no reader can interpret.
        guard !(kind == .rest && durationSeconds != nil) else {
            throw DomainError.inconsistent(reason: "A rest day cannot carry a scheduled duration")
        }
        // Same shape of rule as the one above, for the same reason: a value that cannot
        // mean anything for this kind is a value somebody will later try to read. A run
        // does not work a muscle group in the sense a plan means by it, and a rest day
        // works none, so only a lift may name them.
        guard muscleGroups.isEmpty || kind == .lift else {
            throw DomainError.inconsistent(
                reason: "Only a lift can prescribe muscle groups; \(kind) cannot"
            )
        }
        self.kind = kind
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.note = note
        self.muscleGroups = muscleGroups
    }

    private init(uncheckedKind kind: ScheduledSessionKind) {
        self.kind = kind
        self.distanceMeters = nil
        self.durationSeconds = nil
        self.note = nil
        self.muscleGroups = []
    }

    /// The canonical rest day. A constant rather than a computed value so identity
    /// comparisons in tests and templates read cleanly.
    public static let rest = ScheduledSession(uncheckedKind: .rest)

    public var isRest: Bool { kind == .rest }

    private enum CodingKeys: String, CodingKey {
        case kind, distanceMeters, durationSeconds, note, muscleGroups
    }

    /// **`durationSeconds` is omitted when absent** (MAX-131), for the reason MAX-129
    /// gave for `liftSession` and `muscleGroups`: every `ScheduledSession` already on
    /// disk — inside a stored plan, and inside every stored `Score`, which is immutable
    /// under D8 — prescribes no duration, so leaving the key out leaves those bytes
    /// exactly as they are, and a plan authored before this ticket decodes to a plan that
    /// prescribed no duration, which is precisely what it meant.
    ///
    /// **`muscleGroups` is written as a canonically ordered array**, and omitted entirely
    /// when empty.
    ///
    /// Ordered because a `Set`'s iteration order is not stable, and `PersistencePayload`
    /// leans on an unchanged value re-encoding to identical bytes. Omitted when empty
    /// because every `ScheduledSession` already on disk — inside a stored plan and
    /// inside every stored `Score` (D8: those are immutable) — has no muscle groups, so
    /// the shorter form is the one that leaves those bytes exactly as they are.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(distanceMeters, forKey: .distanceMeters)
        try container.encodeIfPresent(durationSeconds, forKey: .durationSeconds)
        try container.encodeIfPresent(note, forKey: .note)
        if !muscleGroups.isEmpty {
            try container.encode(muscleGroups.ordered, forKey: .muscleGroups)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            kind: container.decode(ScheduledSessionKind.self, forKey: .kind),
            distanceMeters: container.decodeIfPresent(Double.self, forKey: .distanceMeters),
            durationSeconds: container.decodeIfPresent(Double.self, forKey: .durationSeconds),
            note: container.decodeIfPresent(String.self, forKey: .note),
            muscleGroups: Set(
                container.decodeIfPresent([MuscleGroup].self, forKey: .muscleGroups) ?? []
            )
        )
    }
}

/// What a **lift** slot's ask reads as — its own totality distinction, kept separate
/// from `ScheduledSessionKind` so "no lift" (`.rest`) and "a lift with no groups named"
/// (`.lift` with an empty `muscleGroups`) can never collapse into the same rendered
/// state (A17).
///
/// Free-standing rather than a computed property on `ScheduledSession` alone, because
/// `PlanDraft.DayDraft` wants the identical decision computed from its own loose (kind,
/// groups) pair *before* it has assembled a session to ask — see
/// `PlanDraft.DayDraft.liftSummary`. One initializer taking the two raw values is what
/// keeps the two call sites from drifting into two readings of the same day.
public enum LiftPrescriptionSummary: Hashable, Sendable {
    /// The plan asks nothing of this slot.
    case rest
    /// A lift is asked for, and the plan has not said which muscle groups — a real,
    /// intentional statement (see `ScheduledSession.muscleGroups`), not a gap.
    case unstatedGroups
    /// A lift is asked for, naming these groups. Never empty — an empty set is
    /// `.unstatedGroups`, which is what keeps the two states from overlapping.
    case groups(Set<MuscleGroup>)

    public init(kind: ScheduledSessionKind, muscleGroups: Set<MuscleGroup>) {
        guard kind == .lift else {
            self = .rest
            return
        }
        self = muscleGroups.isEmpty ? .unstatedGroups : .groups(muscleGroups)
    }
}

extension ScheduledSession {
    /// This session's ask, read as the lift slot's own vocabulary.
    public var liftPrescriptionSummary: LiftPrescriptionSummary {
        LiftPrescriptionSummary(kind: kind, muscleGroups: muscleGroups)
    }
}

/// Whether a weekday carries a run ask, a lift ask, both, or neither (A17) — the fact
/// a scannable week view leads with, before either slot's own detail.
///
/// Shared, deliberately, between `PlanDraft.DayDraft` (MAX-137: the week an athlete is
/// mid-edit on) and `PlanDisplayData.WeekdayRow` (MAX-138: the week a stored, governing
/// plan already carries). Both answer the identical question — "what does this weekday
/// ask of the two slots" — off the identical two `ScheduledSessionKind` values, so it
/// is one type with one initializer rather than two enums that happen to have the same
/// four cases today and nothing stopping them drifting apart tomorrow.
public enum ObligationSummary: Hashable, Sendable {
    case rest
    case runOnly
    case liftOnly
    case both

    public init(runKind: ScheduledSessionKind, liftKind: ScheduledSessionKind) {
        switch (runKind != .rest, liftKind != .rest) {
        case (false, false): self = .rest
        case (true, false): self = .runOnly
        case (false, true): self = .liftOnly
        case (true, true): self = .both
        }
    }
}

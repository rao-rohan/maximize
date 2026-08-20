import Foundation

/// How recently, and how long, each muscle group was last worked — a decay curve over
/// the entries A22 already collects (MAX-179).
///
/// One figure per `MuscleGroup`: take the most recent session the athlete said worked
/// that group, weight it by how long that session lasted, and decay it by how long ago
/// it ended. Nothing else is read, because nothing else is recorded.
///
/// ## What this model cannot know, and why no ticket should "fix" it
///
/// **There are no sets here. No reps. No load. No exercises.** Not because they were
/// left for later, but because the record does not contain them: HealthKit reports a
/// strength session's start, end, duration, energy and heart-rate series and carries no
/// quantity type for repetitions, sets or weight lifted. A20 settled that wall by
/// scoring lifting on adherence rather than volume, and its cost is stated there in the
/// same plain terms it must be stated in here:
///
/// > Forty-five minutes of moving light weights scores like forty-five real minutes.
///
/// That sentence is this type's limit too. **A hard session and a token one of the same
/// length produce the same figure**, and no arrangement of the arithmetic below can
/// separate them.
///
/// **The obvious follow-up is the one to refuse.** "It is only a weight field" — or a
/// sets field, or an RPE slider — makes this model sharper at the exact price PRD §3
/// exists to avoid, and A20's tripwire governs that decision, not A22's permission:
///
/// - A22 spent the manual-entry non-goal **narrowly and once**: the athlete may say
///   *which* muscles a session worked, on one screen, on one kind of workout. It is
///   explicit that a later ticket "does not inherit this amendment's permission."
/// - A20 says what admitting load would cost, and requires it to arrive **as an
///   amendment superseding PRD §3, with a scoped answer to what else the app then owes
///   the athlete — never as a text field arriving inside a lifting ticket.**
///
/// So this type reads *which* and *when* and *how long*, because that is what the app
/// was given. If someone wants *how much*, the answer is not a field: it is an
/// amendment, and the app that comes out the other side of it is a lifting logger with
/// an exercise library, a previous-session recall and a rest timer.
///
/// ## It is coarse, and it is meant to read that way
///
/// A figure with three decimal places invites being used as though it had three
/// decimal places. This one has roughly one bit of real information — *recently and for
/// a while* versus *a while ago or briefly* — so:
///
/// - **It is a recency signal, not a physiological one.** The half-life is a training
///   week's timescale, not a measurement of protein synthesis or of this athlete's
///   recovery. Nothing here has been calibrated against a person.
/// - **It does not accumulate.** Only the *last* session naming a group is read, so
///   three hard leg days in four days read exactly like the last of them. Summing
///   sessions was considered and declined for MAX-179 — it turns a coarse signal into
///   an arbitrary one, because the sum's scale would be unanchored to anything measured.
/// - **It scores nothing and gates nothing.** No verdict, no rubric band, no adherence
///   consequence reads this figure, which is also why its constants live here rather
///   than in a versioned plan record: D1 protects the reproducibility of *stored
///   scores*, and this produces none. If a fatigue figure ever reaches the scorer, its
///   constants become plan data in the same change — that is the D1 line, stated in
///   advance so it is not crossed by accident.
///
/// ## Absence is not zero, and there are two absences
///
/// A group with no logged session has **no figure at all** (MAX-175: where the data a
/// judgement needs is absent, produce no judgement rather than a degraded one). A zero
/// would say *fully recovered*, which is a claim, and the app has no evidence for it —
/// the athlete may have trained legs every day and told the app nothing.
///
/// `MuscleFatigueReading` therefore has three cases and they are three different facts:
/// **never logged** ("you have never named this group"), **fresh** ("you did, long
/// enough ago that the curve has run out"), and **fatigued**. Only the first is an
/// absence, and only the first is silent about the athlete's body.
public struct MuscleFatigue: Hashable, Sendable {

    /// The group this figure describes.
    public let group: MuscleGroup

    /// The decayed, duration-weighted figure, `0...1`.
    ///
    /// `1.0` is "a full session's worth of work, finished just now" — the model's
    /// ceiling, not a measured maximum, and not comparable between athletes or against
    /// anything outside this app.
    public let fraction: Double

    /// When the most recent session naming this group **ended**. The end is what
    /// recovery runs from; a ninety-minute session that started three hours ago
    /// finished ninety minutes ago.
    public let lastWorkedAt: Date

    /// Seconds between `lastWorkedAt` and the instant the map was computed. Never
    /// negative — see `MuscleFatigueCalculator` for the clamp and why it exists.
    public let elapsedSeconds: Double

    /// What that session counted for before decay, `0...1` — today the duration
    /// weighting described on `MuscleFatigueModel.Weighting.duration`.
    ///
    /// Carried separately from `fraction` so a reader can tell *a short session just
    /// now* from *a long session two days ago*, which the product of the two cannot
    /// distinguish.
    public let sessionWeight: Double

    public init(
        group: MuscleGroup,
        fraction: Double,
        lastWorkedAt: Date,
        elapsedSeconds: Double,
        sessionWeight: Double
    ) throws {
        try Validate.within(fraction, 0...1, "MuscleFatigue.fraction")
        try Validate.within(sessionWeight, 0...1, "MuscleFatigue.sessionWeight")
        try Validate.nonNegative(elapsedSeconds, "MuscleFatigue.elapsedSeconds")
        self.group = group
        self.fraction = fraction
        self.lastWorkedAt = lastWorkedAt
        self.elapsedSeconds = elapsedSeconds
        self.sessionWeight = sessionWeight
    }

    /// Whole days since the session ended, rounded down. A convenience for the surfaces
    /// that say "3 days ago"; the figure itself is computed from seconds.
    public var elapsedDays: Int {
        Int(elapsedSeconds / 86_400)
    }
}

/// One group's state: the three facts a muscle map has to be able to tell apart.
///
/// The three cases exist rather than an `Optional<Double>` because the two absences
/// are not the same absence and a caller that had to infer the difference from a
/// number would eventually infer it wrongly. See `MuscleFatigue` for the rule
/// (MAX-175) and `MuscleFatigueCopy` for the sentences.
public enum MuscleFatigueReading: Hashable, Sendable {

    /// No session on file has ever named this group. **No figure**, deliberately: the
    /// app does not know whether the athlete trains it and has not said so, or does
    /// not train it at all.
    case neverLogged

    /// Logged, but long enough ago that the curve has decayed below
    /// `MuscleFatigueModel.negligibleFraction`. A figure exists and is carried — the
    /// reading is a *judgement of recovery*, which the record supports, rather than an
    /// absence, which it does not.
    case fresh(MuscleFatigue)

    /// Logged recently enough to carry a measurable figure.
    case fatigued(MuscleFatigue)

    /// The figure, when there is one. Nil only for `.neverLogged`.
    public var fatigue: MuscleFatigue? {
        switch self {
        case .neverLogged: return nil
        case let .fresh(fatigue), let .fatigued(fatigue): return fatigue
        }
    }

    /// The decayed figure, when there is one — nil is "nothing to report", never zero.
    public var fraction: Double? { fatigue?.fraction }

    /// Whether the app has ever been told this group was worked.
    public var isLogged: Bool { fatigue != nil }
}

/// The decay model's constants, and the seam the weighting comes through.
///
/// A value rather than a scatter of literals so a test can state the curve it is
/// checking, and so `MuscleFatigueMap` can carry the model that produced it — a figure
/// whose scale is not recoverable from the figure is a figure that will be compared
/// against one computed differently.
///
/// **These are code constants, and that is a decision.** See `MuscleFatigue` on why D1
/// does not reach them today and exactly what would make it reach them.
public struct MuscleFatigueModel: Hashable, Sendable {

    /// How a session's work is measured before decay.
    ///
    /// ## The seam MAX-176 swaps
    ///
    /// One case today, and it is written as an enum rather than inlined because
    /// **strain is a better weight than duration and is being built in parallel**.
    /// MAX-176 computes a zone-weighted integral of the stored heart-rate curve once at
    /// ingestion (D2) and stores it per workout; when it lands, a `.strain` case joins
    /// this enum, `MuscleFatigueSession` gains an optional stored strain alongside its
    /// duration, and `MuscleFatigueCalculator.weight(for:model:)` gains one branch. Nothing
    /// else in this file moves.
    ///
    /// **Duration does not become dead code when that happens.** A lift whose strap
    /// dropped has no heart-rate curve and therefore no strain, and MAX-175's rule says
    /// such a session must not be judged on a fabricated one — so `.duration` stays as
    /// the honest fallback, and the choice between them stays the caller's.
    public enum Weighting: Hashable, Sendable {

        /// The session's **active** duration, saturating at
        /// `MuscleFatigueModel.fullSessionSeconds`.
        ///
        /// Saturating rather than proportional because the alternative is worse in both
        /// directions: unbounded, a three-hour session would read as four times a
        /// forty-five-minute one on a scale where nothing measured justifies the factor;
        /// normalised to the athlete's longest session, one outlier would rescale every
        /// other figure in the app. A ceiling is a coarse answer, and this is a coarse
        /// model.
        case duration
    }

    /// Seconds after which a session's contribution has halved. See
    /// `MuscleFatigueModel.standard` for why the standard value is what it is.
    public let halfLifeSeconds: Double

    /// The session length that counts as a full one, in seconds. Longer sessions do not
    /// count for more — see `Weighting.duration`.
    public let fullSessionSeconds: Double

    /// Below this, a figure is reported as `.fresh` rather than `.fatigued`.
    ///
    /// The floor exists because an exponential never reaches zero, and a curve that
    /// draws a group as faintly-fatigued four months after its last session is stating
    /// a precision the model does not have. It is a **presentation boundary, not a
    /// clamp**: the figure below it is still carried and still ordered, so a group
    /// worked last week and one worked last year do not read as identical.
    public let negligibleFraction: Double

    public let weighting: Weighting

    public init(
        halfLifeSeconds: Double,
        fullSessionSeconds: Double,
        negligibleFraction: Double,
        weighting: Weighting
    ) throws {
        try Validate.positive(halfLifeSeconds, "MuscleFatigueModel.halfLifeSeconds")
        try Validate.positive(fullSessionSeconds, "MuscleFatigueModel.fullSessionSeconds")
        try Validate.within(negligibleFraction, 0...1, "MuscleFatigueModel.negligibleFraction")
        self.halfLifeSeconds = halfLifeSeconds
        self.fullSessionSeconds = fullSessionSeconds
        self.negligibleFraction = negligibleFraction
        self.weighting = weighting
    }

    /// **48-hour half-life, 45-minute full session, 1% floor, weighted by duration.**
    ///
    /// The half-life is chosen against the timescale a training week is *written* at,
    /// not against a physiological one: 48 hours is the interval a split repeats a group
    /// at, so a group trained Monday reads half-fatigued on Wednesday — the day the plan
    /// would next ask for it — and about a twelfth as fatigued the following Monday.
    /// 72 hours was the other defensible choice and is not more correct; the model is
    /// coarse enough that the difference between them is smaller than the difference
    /// between a hard session and a token one, which neither can see at all.
    ///
    /// Forty-five minutes is a strength session that reads as a full one on this
    /// athlete's plan; the seed's authored duration floor is 600 seconds, which is a
    /// different question (what counts as having *shown up*).
    ///
    /// The 1% floor puts the `.fresh` boundary at about 13 days and 7 hours for a full
    /// session — inside a fortnight, outside a fortnight's plan.
    ///
    /// Built through the unchecked initializer for `RestDayBudget.standard`'s reason —
    /// a `static let` cannot throw and these literals are known-good. A test asserts
    /// the same arguments pass the validating initializer, so the two cannot drift.
    public static let standard = MuscleFatigueModel(
        unchecked: 48 * 3_600,
        45 * 60,
        0.01,
        .duration
    )

    private init(
        unchecked halfLifeSeconds: Double,
        _ fullSessionSeconds: Double,
        _ negligibleFraction: Double,
        _ weighting: Weighting
    ) {
        self.halfLifeSeconds = halfLifeSeconds
        self.fullSessionSeconds = fullSessionSeconds
        self.negligibleFraction = negligibleFraction
        self.weighting = weighting
    }
}

/// Every muscle group's reading at one instant — what MAX-180 draws.
///
/// Total over `MuscleGroup.allCases` by construction: a group the calculator saw no
/// session for is present as `.neverLogged` rather than missing, so a caller cannot
/// silently omit a region of the figure by looking up a key that is not there.
public struct MuscleFatigueMap: Hashable, Sendable {

    /// The instant the readings describe. Carried because every figure in here is a
    /// function of *now*: the same records recomputed tomorrow give different numbers,
    /// which is the whole point and is also how a stale copy gives itself away.
    public let computedAt: Date

    /// The model the figures were computed on. See `MuscleFatigueModel` on why a figure
    /// travels with its scale.
    public let model: MuscleFatigueModel

    private let readingsByGroup: [MuscleGroup: MuscleFatigueReading]

    /// Missing groups are filled in as `.neverLogged`.
    public init(
        computedAt: Date,
        model: MuscleFatigueModel,
        readings: [MuscleGroup: MuscleFatigueReading]
    ) {
        var filled = readings
        for group in MuscleGroup.allCases where filled[group] == nil {
            filled[group] = .neverLogged
        }
        self.computedAt = computedAt
        self.model = model
        self.readingsByGroup = filled
    }

    /// Total: every group has a reading, and a group nothing is known about says so.
    public subscript(group: MuscleGroup) -> MuscleFatigueReading {
        readingsByGroup[group] ?? .neverLogged
    }

    /// Every group in `MuscleGroup.allCases` order — the canonical order
    /// `Set<MuscleGroup>.ordered` exists for, so the map does not draw its regions in a
    /// different sequence on the next launch.
    public var ordered: [GroupReading] {
        MuscleGroup.allCases.map { GroupReading(group: $0, reading: self[$0]) }
    }

    /// The groups no session has ever named.
    public var neverLogged: Set<MuscleGroup> {
        Set(MuscleGroup.allCases.filter { !self[$0].isLogged })
    }

    /// Whether the athlete has never logged a strength session at all — the map's own
    /// absence state, distinct from any single group's, and the one a screen should
    /// answer with a sentence rather than with six empty regions.
    public var hasNoLoggedSessions: Bool {
        MuscleGroup.allCases.allSatisfy { !self[$0].isLogged }
    }

    /// The logged groups, most fatigued first, ties broken by the canonical group
    /// order. Never-logged groups are **absent** rather than sorted to the bottom: they
    /// have no place on a ranking of a figure they do not have.
    public var mostFatiguedFirst: [GroupReading] {
        // Ranked over `ordered.enumerated()` rather than by looking each group's index
        // up again: the canonical position is already in hand here, and a lookup would
        // be an optional this file would then have to justify unwrapping.
        ordered
            .enumerated()
            .filter { $0.element.reading.isLogged }
            .sorted { lhs, rhs in
                let left = lhs.element.reading.fraction ?? 0
                let right = rhs.element.reading.fraction ?? 0
                if left != right { return left > right }
                return lhs.offset < rhs.offset
            }
            .map { $0.element }
    }

    /// One group and its reading, paired for iteration.
    public struct GroupReading: Hashable, Sendable, Identifiable {
        public let group: MuscleGroup
        public let reading: MuscleFatigueReading

        public init(group: MuscleGroup, reading: MuscleFatigueReading) {
            self.group = group
            self.reading = reading
        }

        public var id: MuscleGroup { group }
    }
}

/// What a surface says about a muscle group's fatigue.
///
/// Copy lives in the core for `MuscleGroupEntryCopy`'s reason: a sentence a person
/// reads is a product decision, and a product decision inside a SwiftUI view is
/// verified only when a human opens Xcode.
///
/// **The two absences get two sentences.** "You have never logged this group" and "this
/// group is fresh" are different facts about the athlete — the first is about what the
/// app was told, the second is about their body — and one string covering both would be
/// the degraded judgement MAX-175 forbids, wearing the voice of a designed state.
public enum MuscleFatigueCopy {

    /// The section's heading.
    public static let sectionTitle = "Muscle recovery"

    /// A group no logged session has ever named.
    public static let neverLoggedHeadline = "Not logged yet"

    /// Says what is missing and who can supply it, without implying the athlete has
    /// not trained it — the app genuinely does not know.
    public static let neverLoggedDetail =
        "No session you've logged has named this group, so there's nothing to measure."

    /// A group worked long enough ago that the curve has run out. A statement about
    /// elapsed time, which is what was actually measured.
    public static let freshHeadline = "Fresh"

    public static let freshDetail =
        "Enough time has passed since the last session that worked this group."

    /// The whole map, when nothing has ever been logged. The prompt form
    /// `MuscleGroupEntryCopy` uses, for the same reason: it is where the athlete learns
    /// the entry exists.
    public static let noSessionsHeadline = "Nothing logged yet"

    public static let noSessionsDetail =
        "Set the muscle groups on a strength session and this map starts filling in."

    /// The honest caption. Any surface drawing this model carries it, and it says the
    /// limit rather than gesturing at it — see `MuscleFatigue` for the reasoning, and
    /// A20 for the amendment that settled it.
    public static let modelCaption =
        "Estimated from when each group was last worked and for how long. "
        + "HealthKit records no sets, reps or weight, so this reads recency — not how hard a session was."

    /// The sentence for one group, given its reading. A `.fatigued` group's figure is
    /// left to the surface that draws it: the number belongs on the figure, not in a
    /// sentence that would restate it in words.
    public static func detail(for reading: MuscleFatigueReading) -> String {
        switch reading {
        case .neverLogged: return neverLoggedDetail
        case .fresh: return freshDetail
        case .fatigued: return "Worked recently enough to still be recovering."
        }
    }
}

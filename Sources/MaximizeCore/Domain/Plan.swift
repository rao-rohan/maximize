import Foundation

/// The plan's cadence target band, in **steps per minute** (currently 165–170,
/// FR-1.3).
///
/// The band is a single value rather than two loose `Double`s on `Plan` because
/// `lo > hi` is the one way to write a band that can never be satisfied, and it is
/// exactly the sort of typo a hand-authored plan record invites.
public struct CadenceBand: Hashable, Sendable, Codable, CustomStringConvertible {
    public let lowStepsPerMinute: Double
    public let highStepsPerMinute: Double

    public init(lowStepsPerMinute: Double, highStepsPerMinute: Double) throws {
        try Validate.positive(lowStepsPerMinute, "CadenceBand.lowStepsPerMinute")
        try Validate.positive(highStepsPerMinute, "CadenceBand.highStepsPerMinute")
        guard lowStepsPerMinute <= highStepsPerMinute else {
            throw DomainError.inconsistent(
                reason: "CadenceBand.lowStepsPerMinute (\(lowStepsPerMinute)) must not exceed "
                    + "highStepsPerMinute (\(highStepsPerMinute))"
            )
        }
        self.lowStepsPerMinute = lowStepsPerMinute
        self.highStepsPerMinute = highStepsPerMinute
    }

    public func contains(_ stepsPerMinute: Double) -> Bool {
        stepsPerMinute >= lowStepsPerMinute && stepsPerMinute <= highStepsPerMinute
    }

    public var description: String { "\(lowStepsPerMinute)–\(highStepsPerMinute) spm" }

    private enum CodingKeys: String, CodingKey {
        case lowStepsPerMinute, highStepsPerMinute
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            lowStepsPerMinute: container.decode(Double.self, forKey: .lowStepsPerMinute),
            highStepsPerMinute: container.decode(Double.self, forKey: .highStepsPerMinute)
        )
    }
}

/// The recurring week: what the plan asks for on each weekday, **for each discipline**
/// (A17).
///
/// Every (weekday, discipline) pair has an entry — rest is an explicit
/// `ScheduledSession`, not a missing key — so resolving a calendar day to its scheduled
/// session is a total function in *both* arguments. A partial template would push an
/// "I don't know what today is" case into the scorer, which PRD §13 names as the
/// load-bearing risk ("the `plan_day` calendar is load-bearing"). A17's argument for
/// two slots is precisely that this property now applies twice rather than being
/// weakened once: two runs' worth of totality, not half of one.
public struct WeeklyTemplate: Hashable, Sendable, Codable {
    /// One weekday of the recurring week: its run ask and its lift ask.
    ///
    /// ## Both slots on one entry, not two parallel arrays
    ///
    /// Two arrays can disagree about which weekdays they cover, and reconciling them
    /// would be a second totality check somebody has to remember to write. One array of
    /// seven entries, each carrying both asks, makes totality in the *discipline*
    /// argument free: it is a property of `Entry` itself rather than of the container.
    ///
    /// ## Why the run slot keeps the unqualified name
    ///
    /// `session` is the run ask; `liftSession` is the lift ask. The asymmetry is
    /// deliberate and it is what buys A17's third property — no migration. `session` is
    /// the wire key every plan authored before lifting existed already wrote, so a
    /// stored payload decodes into byte-identical run prescriptions, and an absent
    /// `liftSession` decodes to rest — which is exactly what "this plan prescribed no
    /// lifting" meant. Renaming the run slot would have rewritten the wire format of
    /// every stored plan to buy symmetry and nothing else.
    ///
    /// New readers should ask `session(for:)`, which is total and names its discipline.
    public struct Entry: Hashable, Sendable, Codable {
        public let weekday: Weekday

        /// The **run** slot's ask. See the type note on why this is not `runSession`.
        public let session: ScheduledSession

        /// The **lift** slot's ask (A17).
        ///
        /// `.rest` where the plan prescribes no lifting — which is every weekday of
        /// every plan on disk today, because none of them had a lift slot to fill.
        public let liftSession: ScheduledSession

        public init(
            weekday: Weekday,
            session: ScheduledSession,
            liftSession: ScheduledSession = .rest
        ) {
            self.weekday = weekday
            self.session = session
            self.liftSession = liftSession
        }

        /// Total in `discipline`: both slots always have an answer, and rest is one.
        public func session(for discipline: Discipline) -> ScheduledSession {
            switch discipline {
            case .run: return self.session
            case .lift: return liftSession
            }
        }

        private enum CodingKeys: String, CodingKey {
            case weekday, session, liftSession
        }

        /// **Rest and absent are the same statement** (A17), so the encoder writes the
        /// shorter one. A plan that prescribes no lifting therefore encodes to exactly
        /// the bytes it encoded to before this ticket — which makes the no-op claim a
        /// property of the round trip rather than only of the decode.
        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(weekday, forKey: .weekday)
            try container.encode(session, forKey: .session)
            if liftSession != .rest {
                try container.encode(liftSession, forKey: .liftSession)
            }
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                weekday: try container.decode(Weekday.self, forKey: .weekday),
                session: try container.decode(ScheduledSession.self, forKey: .session),
                liftSession: try container.decodeIfPresent(
                    ScheduledSession.self,
                    forKey: .liftSession
                ) ?? .rest
            )
        }
    }

    /// Exactly seven entries, ordered Monday-first. Canonical ordering keeps value
    /// equality meaningful — two templates that prescribe the same week are equal
    /// regardless of the order they were authored in.
    public let entries: [Entry]

    /// - Parameters:
    ///   - sessions: the run slot, which must cover all seven weekdays. A missing
    ///     weekday is rejected rather than defaulted, because it is far more likely to
    ///     be an authoring mistake than a deliberate "nothing here" — and the error
    ///     names the days.
    ///   - liftSessions: the lift slot. A weekday left out is rest, not an error. The
    ///     asymmetry is the point: "no lifting on Wednesday" is the ordinary case and
    ///     it is the *only* thing a plan authored before lifting existed can mean, so
    ///     making it the default is what lets a stored payload and a fresh template
    ///     reach the same value.
    public init(
        _ sessions: [Weekday: ScheduledSession],
        lift liftSessions: [Weekday: ScheduledSession] = [:]
    ) throws {
        var paired: [Entry] = []
        for (weekday, session) in sessions {
            paired.append(
                Entry(
                    weekday: weekday,
                    session: session,
                    liftSession: liftSessions[weekday] ?? .rest
                )
            )
        }
        try self.init(entries: paired)
    }

    public init(entries: [Entry]) throws {
        var byWeekday: [Weekday: Entry] = [:]
        for entry in entries {
            guard byWeekday[entry.weekday] == nil else {
                throw DomainError.duplicate(field: "WeeklyTemplate.entries", key: "\(entry.weekday)")
            }
            byWeekday[entry.weekday] = entry
        }
        let missing = Weekday.allCases.filter { byWeekday[$0] == nil }
        guard missing.isEmpty else {
            throw DomainError.inconsistent(
                reason: "WeeklyTemplate is missing a session for: "
                    + missing.map { "\($0)" }.joined(separator: ", ")
            )
        }
        self.entries = Weekday.allCases.sorted().compactMap { byWeekday[$0] }
    }

    /// Total by construction in **both** arguments: every (weekday, discipline) pair
    /// has a session, and rest is one.
    ///
    /// The discipline is not defaulted. A caller that does not say which slot it means
    /// is a caller that has not decided, and the whole point of A17 is that a run is
    /// never judged against the lift ask or the reverse.
    public func session(on weekday: Weekday, for discipline: Discipline) -> ScheduledSession {
        for entry in entries where entry.weekday == weekday {
            return entry.session(for: discipline)
        }
        // Unreachable: the initializer rejects incomplete templates.
        return ScheduledSession.rest
    }

    public func session(on day: CalendarDay, for discipline: Discipline) -> ScheduledSession {
        session(on: day.weekday, for: discipline)
    }

    /// How many of the seven days prescribe a run — the **run slot** only. Useful for
    /// sanity-checking a plan against the rest-day budget (D9).
    public var scheduledRunCount: Int {
        entries.filter { !$0.session.isRest && $0.session.kind != .other }.count
    }

    /// How many of the seven days prescribe a lift.
    public var scheduledLiftCount: Int {
        entries.filter { !$0.liftSession.isRest }.count
    }

    private enum CodingKeys: String, CodingKey {
        case entries
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(entries: container.decode([Entry].self, forKey: .entries))
    }
}

/// The long-run progression across the training block (§8 `longrun_arc`, "16-week
/// arc" in D1).
///
/// Weeks are 1-based and indexed relative to the plan's `effectiveFrom`; the arc need
/// not be contiguous or complete, but it must be strictly ascending so "the ask for
/// week N" has one answer.
public struct LongRunArc: Hashable, Sendable, Codable {
    public struct Week: Hashable, Sendable, Codable {
        /// 1-based week index from the plan's effective date.
        public let index: Int
        /// Prescribed long-run distance in **meters**.
        public let distanceMeters: Double

        public init(index: Int, distanceMeters: Double) throws {
            guard index >= 1 else {
                throw DomainError.outOfRange(
                    field: "LongRunArc.Week.index", value: Double(index), lowerBound: 1, upperBound: nil
                )
            }
            try Validate.positive(distanceMeters, "LongRunArc.Week.distanceMeters")
            self.index = index
            self.distanceMeters = distanceMeters
        }

        private enum CodingKeys: String, CodingKey {
            case index, distanceMeters
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                index: container.decode(Int.self, forKey: .index),
                distanceMeters: container.decode(Double.self, forKey: .distanceMeters)
            )
        }
    }

    public let weeks: [Week]

    public init(weeks: [Week]) throws {
        guard !weeks.isEmpty else {
            throw DomainError.empty(field: "LongRunArc.weeks")
        }
        for position in 1..<weeks.count where weeks[position].index <= weeks[position - 1].index {
            if weeks[position].index == weeks[position - 1].index {
                throw DomainError.duplicate(field: "LongRunArc.weeks", key: "index=\(weeks[position].index)")
            }
            throw DomainError.outOfOrder(field: "LongRunArc.weeks", index: position)
        }
        self.weeks = weeks
    }

    public func distanceMeters(forWeek index: Int) -> Double? {
        weeks.first { $0.index == index }?.distanceMeters
    }

    public var weekCount: Int { weeks.count }

    private enum CodingKeys: String, CodingKey {
        case weeks
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(weeks: container.decode([Week].self, forKey: .weeks))
    }
}

/// The plan's stated goals (§8 `goals`, json).
///
/// Deliberately loose: goals are narrative context handed to the scorer and the chat
/// (D3), not something the code branches on. Adding structure here would be inventing
/// requirements the PRD does not have.
public struct PlanGoals: Hashable, Sendable, Codable {
    /// One line per goal, in the athlete's own words.
    public let statements: [String]
    /// The event this block builds toward, if there is one.
    public let targetDay: CalendarDay?

    public init(statements: [String] = [], targetDay: CalendarDay? = nil) {
        self.statements = statements
        self.targetDay = targetDay
    }
}

/// A versioned training plan (PRD §8 `plan`, D1).
///
/// **The plan is data, not code.** The HR cap, the cadence band, the weekly shape,
/// the long-run arc and the entire scoring rubric live inside this record. Changing
/// any of them is authoring a new `Plan` with a higher `version` and a later
/// `effectiveFrom` — never a code edit — because scoring resolves the version in
/// effect on the workout's date, and historical scores must stay reproducible.
public struct Plan: Hashable, Sendable, Codable, Identifiable {
    public var id: PlanVersion { version }

    public let version: PlanVersion
    /// First calendar day this version governs. Resolution of *which* version governs
    /// a given day is MAX-011's job; this type only carries the fact.
    public let effectiveFrom: CalendarDay
    public let weeklyTemplate: WeeklyTemplate
    public let longRunArc: LongRunArc
    /// Easy-run heart-rate ceiling in **beats per minute** (currently 150, FR-1.2).
    public let heartRateCapBPM: Double
    public let cadenceTarget: CadenceBand
    public let rubric: ScoringRubric
    public let goals: PlanGoals

    public init(
        version: PlanVersion,
        effectiveFrom: CalendarDay,
        weeklyTemplate: WeeklyTemplate,
        longRunArc: LongRunArc,
        heartRateCapBPM: Double,
        cadenceTarget: CadenceBand,
        rubric: ScoringRubric,
        goals: PlanGoals = PlanGoals()
    ) throws {
        try Validate.within(heartRateCapBPM, HeartRateSample.plausibleBPM, "Plan.heartRateCapBPM")
        self.version = version
        self.effectiveFrom = effectiveFrom
        self.weeklyTemplate = weeklyTemplate
        self.longRunArc = longRunArc
        self.heartRateCapBPM = heartRateCapBPM
        self.cadenceTarget = cadenceTarget
        self.rubric = rubric
        self.goals = goals
    }

    /// Resolves a rubric reference against this plan. Kept here rather than in the
    /// scorer so there is exactly one interpretation of "cap + 8" in the system
    /// (the D3 spirit: one notion of the numbers, not two).
    ///
    /// - Parameter scheduledDistanceMeters: the day's prescribed distance, needed
    ///   only by `.scheduledDistance`; nil yields nil for that case.
    public func resolve(
        _ reference: RubricReference,
        scheduledDistanceMeters: Double? = nil
    ) -> Double? {
        switch reference {
        case let .constant(value):
            return value
        case let .heartRateCap(offset):
            return heartRateCapBPM + offset
        case let .cadenceTargetLow(offset):
            return cadenceTarget.lowStepsPerMinute + offset
        case let .cadenceTargetHigh(offset):
            return cadenceTarget.highStepsPerMinute + offset
        case let .scheduledDistance(fraction):
            guard let scheduledDistanceMeters else { return nil }
            return scheduledDistanceMeters * fraction
        }
    }

    private enum CodingKeys: String, CodingKey {
        case version, effectiveFrom, weeklyTemplate, longRunArc
        case heartRateCapBPM, cadenceTarget, rubric, goals
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            version: container.decode(PlanVersion.self, forKey: .version),
            effectiveFrom: container.decode(CalendarDay.self, forKey: .effectiveFrom),
            weeklyTemplate: container.decode(WeeklyTemplate.self, forKey: .weeklyTemplate),
            longRunArc: container.decode(LongRunArc.self, forKey: .longRunArc),
            heartRateCapBPM: container.decode(Double.self, forKey: .heartRateCapBPM),
            cadenceTarget: container.decode(CadenceBand.self, forKey: .cadenceTarget),
            rubric: container.decode(ScoringRubric.self, forKey: .rubric),
            goals: container.decode(PlanGoals.self, forKey: .goals)
        )
    }
}

/// A resolved calendar entry — the materialized `plan_day` of PRD §8, carrying the
/// day's ask **for each discipline** (A17).
///
/// Materializing the calendar is what makes scoring deterministic: the day's ask is
/// recorded once, so a later plan version cannot retroactively change what yesterday
/// was supposed to be.
///
/// ## What a `PlanDay` means now, and why it answers twice
///
/// It used to answer "what does the plan ask of this day". A day now has two asks, and
/// three shapes were available:
///
/// - **Answer once, and let callers re-ask `PlanCalendar` per discipline.** Rejected:
///   the same day would be resolved twice, and two resolutions of one day are two
///   places for the answer to drift — D2's failure mode with a date on it. One
///   resolution carrying both asks has no such seam.
/// - **Make the ask a list.** Rejected, per LIFTING-SPEC §2.1: every consumer would
///   have to decide what an arbitrary-length list means, and an empty list is a partial
///   template wearing a different hat — the totality property this file exists to
///   protect.
/// - **Answer twice, with `scheduledSession(for:)` as the total answer.** ✅
///
/// So a `PlanDay` carries exactly two sessions and `scheduledSession(for:)` is total in
/// its argument. That is what lets **a workout be judged only against the session of
/// its own discipline**, which is in turn what makes it impossible for a lift to match
/// a band written about an easy run. Downstream consumers inherit this shape: the
/// scorer, the calendar, the tallies and the fact sheet all read a `PlanDay`, and each
/// of them now has a discipline to name.
///
/// ## Why the run slot keeps the unqualified name
///
/// `scheduledSession` is the **run** ask. Every reader that says `scheduledSession`
/// today — planned weekly mileage, the verdict header, the fact sheet's "Planned:"
/// line, the rubric evaluator — means the run ask, so after this change each of them is
/// still *correct*, not merely still compiling. Breaking all of them here to have each
/// re-spell `.run` at the call site would buy nothing until those call sites genuinely
/// need to choose a discipline. They do, in MAX-133 through MAX-136 and MAX-140, and
/// that is where they change — one consumer at a time, with a reviewer on each.
///
/// `canBeMissed` is likewise still the **run** obligation's predicate. A19 makes the
/// unit of account the obligation rather than the day, and MAX-134 is what teaches the
/// rest-day budget and the tallies to count both. Until then this is unchanged
/// behaviour — and for every plan on disk, all of whose lift slots are rest, unchanged
/// behaviour is also the right behaviour.
public struct PlanDay: Hashable, Sendable, Codable, Identifiable {
    public var id: CalendarDay { date }

    public let date: CalendarDay
    /// The plan version that produced this entry — the provenance that makes a
    /// historical score reproducible (D1).
    public let planVersion: PlanVersion

    /// The **run** slot's ask. See the type note on why this is not `runSession`.
    public let scheduledSession: ScheduledSession

    /// The **lift** slot's ask (A17). `.rest` where the plan prescribes no lifting.
    public let liftSession: ScheduledSession

    public init(
        date: CalendarDay,
        planVersion: PlanVersion,
        scheduledSession: ScheduledSession,
        liftSession: ScheduledSession = .rest
    ) {
        self.date = date
        self.planVersion = planVersion
        self.scheduledSession = scheduledSession
        self.liftSession = liftSession
    }

    /// The day's ask for one discipline. Total: both slots always have an answer, and
    /// rest is one.
    ///
    /// **This is the accessor a new reader wants.** `Discipline` is closed at two cases,
    /// so a third would break this switch rather than silently take a default — which is
    /// the property that makes the closedness worth having.
    public func scheduledSession(for discipline: Discipline) -> ScheduledSession {
        switch discipline {
        case .run: return self.scheduledSession
        case .lift: return liftSession
        }
    }

    /// A day with a scheduled **run** and no workout is what surfaces red (D9); a
    /// scheduled rest day never can. See the type note: widening this to the day's
    /// obligations rather than the day's run is A19's change, and MAX-134's ticket.
    public var canBeMissed: Bool { !scheduledSession.isRest }

    private enum CodingKeys: String, CodingKey {
        case date, planVersion, scheduledSession, liftSession
    }

    /// A `PlanDay` is resolved, never stored — `PlanCalendar` explains why there is no
    /// materialized table. The custom coding is here anyway, and matches
    /// `WeeklyTemplate.Entry`'s exactly, so that the one shape "a prescription on the
    /// wire" has does not depend on which type happened to be encoded.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(date, forKey: .date)
        try container.encode(planVersion, forKey: .planVersion)
        try container.encode(scheduledSession, forKey: .scheduledSession)
        if liftSession != .rest {
            try container.encode(liftSession, forKey: .liftSession)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            date: try container.decode(CalendarDay.self, forKey: .date),
            planVersion: try container.decode(PlanVersion.self, forKey: .planVersion),
            scheduledSession: try container.decode(
                ScheduledSession.self,
                forKey: .scheduledSession
            ),
            liftSession: try container.decodeIfPresent(
                ScheduledSession.self,
                forKey: .liftSession
            ) ?? .rest
        )
    }
}

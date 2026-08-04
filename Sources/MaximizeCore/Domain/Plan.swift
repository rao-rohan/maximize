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

/// The recurring week: what the plan asks for on each weekday.
///
/// Every weekday has an entry — rest is an explicit `ScheduledSession`, not a missing
/// key — so resolving a calendar day to its scheduled session is a total function.
/// A partial template would push an "I don't know what today is" case into the scorer,
/// which PRD §13 names as the load-bearing risk ("the `plan_day` calendar is
/// load-bearing").
public struct WeeklyTemplate: Hashable, Sendable, Codable {
    public struct Entry: Hashable, Sendable, Codable {
        public let weekday: Weekday
        public let session: ScheduledSession

        public init(weekday: Weekday, session: ScheduledSession) {
            self.weekday = weekday
            self.session = session
        }
    }

    /// Exactly seven entries, ordered Monday-first. Canonical ordering keeps value
    /// equality meaningful — two templates that prescribe the same week are equal
    /// regardless of the order they were authored in.
    public let entries: [Entry]

    public init(_ sessions: [Weekday: ScheduledSession]) throws {
        let missing = Weekday.allCases.filter { sessions[$0] == nil }
        guard missing.isEmpty else {
            throw DomainError.inconsistent(
                reason: "WeeklyTemplate is missing a session for: "
                    + missing.map { "\($0)" }.joined(separator: ", ")
            )
        }
        entries = Weekday.allCases.sorted().compactMap { weekday in
            sessions[weekday].map { Entry(weekday: weekday, session: $0) }
        }
    }

    public init(entries: [Entry]) throws {
        var sessions: [Weekday: ScheduledSession] = [:]
        for entry in entries {
            guard sessions[entry.weekday] == nil else {
                throw DomainError.duplicate(field: "WeeklyTemplate.entries", key: "\(entry.weekday)")
            }
            sessions[entry.weekday] = entry.session
        }
        try self.init(sessions)
    }

    /// Total by construction: every weekday has a session.
    public func session(on weekday: Weekday) -> ScheduledSession {
        for entry in entries where entry.weekday == weekday {
            return entry.session
        }
        // Unreachable: the initializer rejects incomplete templates.
        return ScheduledSession.rest
    }

    public func session(on day: CalendarDay) -> ScheduledSession {
        session(on: day.weekday)
    }

    /// How many of the seven days prescribe a run. Useful for sanity-checking a plan
    /// against the rest-day budget (D9).
    public var scheduledRunCount: Int {
        entries.filter { !$0.session.isRest && $0.session.kind != .other }.count
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

/// A resolved calendar entry — the materialized `plan_day` of PRD §8.
///
/// Materializing the calendar is what makes scoring deterministic: the day's ask is
/// recorded once, so a later plan version cannot retroactively change what yesterday
/// was supposed to be.
public struct PlanDay: Hashable, Sendable, Codable, Identifiable {
    public var id: CalendarDay { date }

    public let date: CalendarDay
    /// The plan version that produced this entry — the provenance that makes a
    /// historical score reproducible (D1).
    public let planVersion: PlanVersion
    public let scheduledSession: ScheduledSession

    public init(date: CalendarDay, planVersion: PlanVersion, scheduledSession: ScheduledSession) {
        self.date = date
        self.planVersion = planVersion
        self.scheduledSession = scheduledSession
    }

    /// A day with a scheduled session and no workout is what surfaces red (D9); a
    /// scheduled rest day never can.
    public var canBeMissed: Bool { !scheduledSession.isRest }
}

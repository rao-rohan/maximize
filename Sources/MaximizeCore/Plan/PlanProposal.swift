import Foundation

/// Why a model's plan proposal could not be accepted (CHAT-FIRST-SPEC.md §4.5, A13).
///
/// ## Why this is not simply `PlanAuthoringError`
///
/// §4.5 observes that `PlanAuthoringError` "already covers every failure this can
/// produce", and for *field values* that is exactly right — so those failures are
/// carried through unchanged in `rejectedByAuthoring`, rather than restated in a second
/// vocabulary that could drift from the door's. The plan's rules are the door's rules.
///
/// What the door has no case for is the class of failure that only exists at a model
/// boundary: a reply that is not JSON, a session kind the app has never heard of, a week
/// naming Tuesday twice. `PlanDraft` makes each of those unrepresentable — a draft always
/// has seven weekdays and a legal `ScheduledSessionKind` — so a screen can never produce
/// one and `PlanAuthoringSession` was right not to have a case for it. A model can produce
/// all of them.
///
/// ## Every case is worth one retry, and no case is worth two
///
/// There is deliberately no `isWorthRetrying` here, unlike `ScoringError`. That property
/// exists there because the scoring failures genuinely split — some are the model's fault
/// and some are the plan data's. These are all the model's fault: the request carries no
/// version and no date, so the two `PlanAuthoringError` cases that describe a *stored*
/// conflict (`effectiveFromTooEarly`, `wouldRewriteHistory`) cannot arise here at all.
/// §4.5's policy is therefore uniform — one automatic retry, whatever failed, then show
/// the athlete the text and stop — and a discriminator that always answered `true` would
/// be a decoration a caller could mistake for a decision. The policy is MAX-101's.
///
/// ## What these never carry
///
/// The athlete's fact sheet, and the model's raw reply. `description` is appended to a
/// retry instruction (§4.5) *and* shown on screen, so it is read by both the model and
/// the athlete — but it is assembled from this enum's own payloads, which are bounded
/// values (a field name, a weekday, a week index) and never a block of text something
/// else wrote. `ScoreProposal.parse` holds the same line for the same reason.
public enum PlanProposalError: Error, Hashable, Sendable, CustomStringConvertible {

    // MARK: - The reply was not a proposal at all

    /// The reply was not the single JSON object the schema asks for.
    case malformedResponse(reason: String)

    /// A field the schema requires was absent, or was sent as null.
    case missingField(name: String)

    /// A field the model must not set was present (§4.4).
    ///
    /// **Refused rather than ignored**, which is the less obvious choice, since
    /// `JSONDecoder` would drop an unknown key for free. The reason is that a model
    /// sending `effectiveFrom` is a model that believes it chose the start date, and the
    /// long-run arc it sent alongside is indexed *from* that date. Dropping the field
    /// silently would keep the arc and lose the anchor it was written against, which is a
    /// plan that is wrong in a way nothing on screen shows. Saying so costs one retry and
    /// buys a proposal whose weeks mean what the model meant.
    case forbiddenField(name: String)

    // MARK: - The vocabulary was wrong

    case unknownSessionKind(name: String)
    case unknownWeekday(name: String)

    /// The recurring week did not name each of the seven weekdays exactly once.
    ///
    /// Unrepresentable in a `PlanDraft`, whose initializer fills every weekday and
    /// defaults the rest — so `PlanAuthoringSession` has no case for it. A model hands
    /// over the whole week at once and can leave a hole in it.
    case weekIsNotOneSessionPerWeekday(missing: [Weekday], duplicated: [Weekday])

    /// A rest day carried a distance or a note.
    ///
    /// Also unrepresentable in a draft, and for a reason worth restating:
    /// `PlanDraft.DayDraft.setKind` *clears* the distance when a day becomes rest,
    /// because a screen sets the two with separate taps and the intermediate state would
    /// otherwise only fail at save time. A proposal arrives whole, so there is no
    /// intermediate state to protect and nothing to clear on the athlete's behalf — the
    /// model said two contradictory things about one day, and coercing one of them away
    /// would be this parser deciding which one it meant.
    case restDayIsNotEmpty(weekday: Weekday)

    /// The goal's target day was not `YYYY-MM-DD`.
    case malformedGoalTargetDay(value: String)

    // MARK: - The long-run arc

    /// `LongRunArc` rejects an empty arc; `PlanDraft` rejects one too, so again there is
    /// no `PlanAuthoringError` for it.
    case longRunArcIsEmpty

    /// Arc weeks are 1-based (`LongRunArc.Week`).
    ///
    /// Distinguished from `rejectedByAuthoring(.longRunDistanceNotPositive)` on purpose:
    /// `PlanAuthoringSession` reports both a bad index and a bad distance as the latter,
    /// because a draft's indices are assigned by `appendLongRunWeek` rather than typed.
    /// A model types them, so the two failures are worth telling apart in the sentence
    /// the model is asked to correct.
    case longRunArcWeekNotPositive(week: Int)

    /// Arc weeks must strictly ascend (`LongRunArc`, `PlanDraft`).
    case longRunArcOutOfOrder(week: Int)

    // MARK: - The plan's own rules

    /// A field value the plan-authoring door itself refuses, carried through verbatim so
    /// the proposal boundary and the storage door cannot disagree about what a legal plan
    /// is. See the type's note.
    case rejectedByAuthoring(PlanAuthoringError)

    public var description: String {
        switch self {
        case let .malformedResponse(reason):
            return "The reply was not the single JSON object the plan schema asks for: \(reason)."
        case let .missingField(name):
            return "The reply left out \"\(name)\", which the plan schema requires."
        case let .forbiddenField(name):
            return "The reply set \"\(name)\". A proposed plan does not carry that field — "
                + "the app derives it. Send only the fields the schema lists."
        case let .unknownSessionKind(name):
            return "\"\(name)\" is not a session kind this plan understands. Use one of: "
                + "\(PlanProposal.sessionKindVocabulary)."
        case let .unknownWeekday(name):
            return "\"\(name)\" is not a weekday. Use one of: \(PlanProposal.weekdayVocabulary)."
        case let .weekIsNotOneSessionPerWeekday(missing, duplicated):
            var sentence = "The week has to name each of the seven weekdays exactly once."
            if !missing.isEmpty {
                sentence += " Missing: \(PlanProposal.list(missing))."
            }
            if !duplicated.isEmpty {
                sentence += " Named more than once: \(PlanProposal.list(duplicated))."
            }
            return sentence
        case let .restDayIsNotEmpty(weekday):
            return "\(PlanProposal.wireName(for: weekday).capitalized) is a rest day, so it cannot "
                + "carry a distance or a note. Give it a session kind, or leave it empty."
        case let .malformedGoalTargetDay(value):
            return "\"\(value)\" is not a date. Give the goal's target day as YYYY-MM-DD, "
                + "or leave it out."
        case .longRunArcIsEmpty:
            return "The long-run arc needs at least one week."
        case let .longRunArcWeekNotPositive(week):
            return "Long-run arc weeks are numbered from 1; \(week) is not a week number."
        case let .longRunArcOutOfOrder(week):
            return "The long-run arc has to ascend by week. Week \(week) does not come after "
                + "the week before it."
        case let .rejectedByAuthoring(error):
            return error.description
        }
    }
}

/// A plan a model has proposed, parsed and validated — and **not** a `Plan`
/// (CHAT-FIRST-SPEC.md §4, PRD-AMENDMENTS.md A13).
///
/// ## The boundary this type exists to hold
///
/// D1 says the plan is versioned data whose immutability keeps historical scores
/// reproducible. Generating one is an *authoring* act, and the two stay compatible only
/// because there is exactly one door into storage:
/// `PlanAuthoringSession.plan(from:effectiveFrom:)`, which stamps the version and checks
/// the effective date against the calendar the write would produce.
///
/// **A proposal is not on that path and cannot reach it.** Nothing in this file returns a
/// `Plan`, builds a `PlanDraft`, or names a repository. A proposal becomes a plan version
/// when the athlete taps through the same screen they would have used to type it by hand,
/// and not before. The near-miss A13 names in advance — a helper that applies a proposal
/// *and stores it* — has no half in this file to be built from.
///
/// ## What it does not carry, and why each one (§4.4)
///
/// - **No `version`.** Derived as the successor of the highest stored version. A version
///   number anything can propose is a back-dated version waiting to happen.
/// - **No `effectiveFrom`.** The session derives the earliest and suggested dates and the
///   athlete moves within that range. So a back-dated plan is not a failure mode that is
///   *validated and rejected* here — it is one that cannot be expressed.
/// - **No rubric bands.** The bands decide what every future run scores. A hallucinated
///   condition there does not produce a visibly wrong plan; it produces a plan that looks
///   fine and quietly mis-scores for sixteen weeks. `PlanAuthoringSession` carries the
///   athlete's bands forward verbatim, and a proposal must not disturb that. A
///   `RubricBandProposal` over a closed condition grammar is its own ticket (§12, q2).
///
/// The first two are refused rather than ignored when a reply sends them anyway — see
/// `PlanProposalError.forbiddenField`.
///
/// ## Validated, and validated against the door's own rules
///
/// Every value here has already passed the checks
/// `PlanAuthoringSession.plan(from:effectiveFrom:)` performs, in the door's own
/// vocabulary (`PlanAuthoringError`, carried in `rejectedByAuthoring`). That is a
/// deliberate constraint rather than a convenience: a proposal that parsed and *then*
/// failed at the door would be a card the athlete can see, tap, and get nowhere with —
/// a dead end produced by two components disagreeing about what a legal plan is.
///
/// The three checks the door does *not* have — a complete week, an empty rest day, a
/// non-empty ascending arc — are ones `PlanDraft` makes unrepresentable rather than ones
/// it permits, so enforcing them here is agreement with the door, not a divergence from
/// it. `PlanProposalTests` pins the property end to end by running a parsed proposal
/// through a real `PlanAuthoringSession`.
///
/// ## Deliberately shaped like `PlanDraft`, field for field
///
/// Bare `Double`s and `Int`s, in the spirit of `ScoreProposal`'s bare `Int`: a 400 bpm cap
/// has to survive decoding long enough to be refused *as an implausible heart-rate cap*
/// rather than collapsing into "the JSON did not decode", which tells a retry nothing.
/// Matching `PlanDraft`'s fields is what keeps MAX-101's handoff a copy rather than a
/// translation — a translation is where a field quietly stops being carried.
public struct PlanProposal: Hashable, Sendable, Codable {

    /// One weekday of the proposed recurring week.
    ///
    /// Holds the `ScheduledSession` it validated to, rather than a loose kind/distance
    /// pair, so a consumer cannot re-derive the session a second way and get a different
    /// answer. The wire form stays flat — see `CodingKeys`.
    public struct Day: Hashable, Sendable, Codable, Identifiable {
        public var id: Weekday { weekday }

        public let weekday: Weekday

        /// The plan's ask for this day, already legal.
        public let session: ScheduledSession

        public var kind: ScheduledSessionKind { session.kind }
        public var distanceMeters: Double? { session.distanceMeters }
        public var note: String? { session.note }

        /// - Throws: `PlanProposalError.restDayIsNotEmpty` when a rest day carries work.
        ///   `ScheduledSession` permits a rest day with a note; a *draft* cannot express
        ///   one, so accepting it here would mean the note vanished somewhere between the
        ///   card the athlete approved and the plan they saved.
        public init(weekday: Weekday, session: ScheduledSession) throws {
            guard !(session.isRest && (session.distanceMeters != nil || session.note != nil)) else {
                throw PlanProposalError.restDayIsNotEmpty(weekday: weekday)
            }
            self.weekday = weekday
            self.session = session
        }

        /// Convenience for the shape the wire carries.
        public init(
            weekday: Weekday,
            kind: ScheduledSessionKind,
            distanceMeters: Double? = nil,
            note: String? = nil
        ) throws {
            let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleaned = (trimmed?.isEmpty ?? true) ? nil : trimmed
            guard !(kind == .rest && (distanceMeters != nil || cleaned != nil)) else {
                throw PlanProposalError.restDayIsNotEmpty(weekday: weekday)
            }
            let session: ScheduledSession
            do {
                session = try ScheduledSession(
                    kind: kind,
                    distanceMeters: distanceMeters,
                    note: cleaned
                )
            } catch {
                // A non-positive distance is the only way `ScheduledSession` refuses a
                // pair the rest check above has already cleared. Reported in the door's
                // vocabulary, so the proposal boundary and the door say the same thing.
                throw PlanProposalError.rejectedByAuthoring(
                    .scheduledDistanceNotPositive(weekday: weekday)
                )
            }
            try self.init(weekday: weekday, session: session)
        }

        private enum CodingKeys: String, CodingKey {
            case weekday, kind, distanceMeters, note
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(PlanProposal.wireName(for: weekday), forKey: .weekday)
            try container.encode(kind.rawValue, forKey: .kind)
            try container.encodeIfPresent(distanceMeters, forKey: .distanceMeters)
            try container.encodeIfPresent(note, forKey: .note)
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let weekdayName = try PlanProposal.decodeString(.weekday, from: container)
            let kindName = try PlanProposal.decodeString(.kind, from: container)
            guard let weekday = PlanProposal.weekday(named: weekdayName) else {
                throw PlanProposalError.unknownWeekday(name: weekdayName)
            }
            guard let kind = PlanProposal.sessionKind(named: kindName) else {
                throw PlanProposalError.unknownSessionKind(name: kindName)
            }
            try self.init(
                weekday: weekday,
                kind: kind,
                distanceMeters: try container.decodeIfPresent(Double.self, forKey: .distanceMeters),
                note: try container.decodeIfPresent(String.self, forKey: .note)
            )
        }
    }

    /// One week of the proposed long-run arc.
    ///
    /// Holds a validated `LongRunArc.Week` for the same reason `Day` holds a
    /// `ScheduledSession`.
    public struct ArcWeek: Hashable, Sendable, Codable, Identifiable {
        public var id: Int { index }

        public let week: LongRunArc.Week

        public var index: Int { week.index }
        public var distanceMeters: Double { week.distanceMeters }

        public init(index: Int, distanceMeters: Double) throws {
            guard index >= 1 else {
                throw PlanProposalError.longRunArcWeekNotPositive(week: index)
            }
            let resolved: LongRunArc.Week
            do {
                resolved = try LongRunArc.Week(index: index, distanceMeters: distanceMeters)
            } catch {
                throw PlanProposalError.rejectedByAuthoring(.longRunDistanceNotPositive(week: index))
            }
            self.week = resolved
        }

        private enum CodingKeys: String, CodingKey {
            case index, distanceMeters
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(index, forKey: .index)
            try container.encode(distanceMeters, forKey: .distanceMeters)
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                index: try PlanProposal.decode(Int.self, .index, from: container),
                distanceMeters: try PlanProposal.decode(Double.self, .distanceMeters, from: container)
            )
        }
    }

    /// Easy-run heart-rate ceiling in **beats per minute** (FR-1.2).
    public let heartRateCapBPM: Double
    public let cadenceLowStepsPerMinute: Double
    public let cadenceHighStepsPerMinute: Double
    /// Score at or above which a day counts as effective (§10.4).
    public let effectiveThresholdPoints: Int
    /// Score at or above which a day is marginal rather than ineffective.
    public let marginalThresholdPoints: Int

    /// Exactly seven entries, Monday-first — `WeeklyTemplate`'s and `PlanDraft.week`'s
    /// own ordering, canonicalised here so two proposals prescribing the same week are
    /// equal regardless of the order the model listed them in.
    public let week: [Day]

    /// At least one week, strictly ascending by index.
    public let longRunArc: [ArcWeek]

    /// The athlete's goals in their own words, one per entry, blanks dropped.
    ///
    /// Normalised exactly as `PlanAuthoringSession` normalises the draft's newline-joined
    /// text, so the `PlanGoals` this proposal implies and the one the door produces are
    /// the same value rather than two renderings of it.
    public let goalStatements: [String]

    /// The event this block builds toward, if the conversation named one.
    ///
    /// **Not `effectiveFrom`, and not adjacent to it.** This is a fact about the athlete's
    /// season that `PlanDraft` already carries and `PlanGoals` already stores as narrative
    /// context; nothing branches on it, and it has no bearing on which plan version governs
    /// which day. §4.4's argument against a model-supplied date is about the field that
    /// orders the version set, and this is not that field.
    public let goalTargetDay: CalendarDay?

    /// - Throws: `PlanProposalError`. Checks run in the order the schema lists the fields,
    ///   so the error names the first thing wrong reading top to bottom.
    public init(
        heartRateCapBPM: Double,
        cadenceLowStepsPerMinute: Double,
        cadenceHighStepsPerMinute: Double,
        effectiveThresholdPoints: Int,
        marginalThresholdPoints: Int,
        week: [Day],
        longRunArc: [ArcWeek],
        goalStatements: [String] = [],
        goalTargetDay: CalendarDay? = nil
    ) throws {
        // The plan's own rules, in `PlanAuthoringSession`'s vocabulary and in its order.
        guard heartRateCapBPM.isFinite, HeartRateSample.plausibleBPM.contains(heartRateCapBPM) else {
            throw PlanProposalError.rejectedByAuthoring(
                .heartRateCapImplausible(permitted: HeartRateSample.plausibleBPM)
            )
        }
        guard cadenceLowStepsPerMinute.isFinite, cadenceLowStepsPerMinute > 0,
              cadenceHighStepsPerMinute.isFinite, cadenceHighStepsPerMinute > 0
        else {
            throw PlanProposalError.rejectedByAuthoring(.cadenceBandNotPositive)
        }
        guard cadenceLowStepsPerMinute <= cadenceHighStepsPerMinute else {
            throw PlanProposalError.rejectedByAuthoring(.cadenceBandInverted)
        }
        guard ScoreValue.permittedRange.contains(effectiveThresholdPoints),
              ScoreValue.permittedRange.contains(marginalThresholdPoints)
        else {
            throw PlanProposalError.rejectedByAuthoring(
                .scoreThresholdOutOfRange(permitted: ScoreValue.permittedRange)
            )
        }
        guard marginalThresholdPoints <= effectiveThresholdPoints else {
            throw PlanProposalError.rejectedByAuthoring(.thresholdsInverted)
        }

        // The rules a draft makes unrepresentable, which a whole-week reply can break.
        var seen: [Weekday: Int] = [:]
        for day in week {
            seen[day.weekday, default: 0] += 1
        }
        let missing = Weekday.allCases.sorted().filter { seen[$0] == nil }
        let duplicated = Weekday.allCases.sorted().filter { (seen[$0] ?? 0) > 1 }
        guard missing.isEmpty, duplicated.isEmpty else {
            throw PlanProposalError.weekIsNotOneSessionPerWeekday(
                missing: missing,
                duplicated: duplicated
            )
        }

        guard !longRunArc.isEmpty else {
            throw PlanProposalError.longRunArcIsEmpty
        }
        for position in longRunArc.indices.dropFirst()
        where longRunArc[position].index <= longRunArc[position - 1].index {
            throw PlanProposalError.longRunArcOutOfOrder(week: longRunArc[position].index)
        }

        self.heartRateCapBPM = heartRateCapBPM
        self.cadenceLowStepsPerMinute = cadenceLowStepsPerMinute
        self.cadenceHighStepsPerMinute = cadenceHighStepsPerMinute
        self.effectiveThresholdPoints = effectiveThresholdPoints
        self.marginalThresholdPoints = marginalThresholdPoints
        self.week = week.sorted { $0.weekday < $1.weekday }
        self.longRunArc = longRunArc
        self.goalStatements = PlanProposal.normalizedGoalStatements(goalStatements)
        self.goalTargetDay = goalTargetDay
    }

    /// The proposed session for a weekday. Total by construction: the initializer refuses
    /// an incomplete week.
    public subscript(weekday: Weekday) -> ScheduledSession {
        for day in week where day.weekday == weekday {
            return day.session
        }
        // Unreachable: `init` rejects a week that does not name all seven days.
        return .rest
    }

    /// The goals this proposal implies, in the shape `Plan` stores them.
    ///
    /// A value conversion, not a step toward storage: `PlanGoals` is an immutable
    /// narrative record with no path of its own to disk.
    public var goals: PlanGoals {
        PlanGoals(statements: goalStatements, targetDay: goalTargetDay)
    }

    // MARK: - Parsing a reply

    /// Decodes and validates the model's reply.
    ///
    /// Tolerant about *formatting*, strict about *content*, exactly as
    /// `ScoreProposal.parse` is. A leading code fence is stripped, and a weekday or kind
    /// spelt `"Monday"` is accepted, because refusing either would burn a retry on
    /// punctuation. Prose wrapped around the JSON is **not** salvaged by hunting for the
    /// first `{`: a model that explained itself instead of answering did not follow the
    /// contract, and digging the object out of the commentary hides that from the retry
    /// logic and from anyone reading the logs.
    ///
    /// Unlike `ScoreProposal.parse`, this returns a value that has already been checked
    /// against the plan's rules — see the type's note on why a proposal the authoring door
    /// would refuse must not be able to exist.
    public static func parse(_ raw: String) throws -> PlanProposal {
        // Deliberately a second copy of `ScoreProposal.parse`'s envelope handling rather
        // than a shared helper: extracting one means editing `Scoring/`, which this ticket
        // does not own. `PlanProposalTests` pins that the two tolerate the same
        // formatting, so the duplication cannot drift unnoticed while it lasts.
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if text.hasPrefix("```") {
            var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            lines.removeFirst() // ``` or ```json
            if let last = lines.last, last.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                lines.removeLast()
            }
            text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard text.hasPrefix("{"), text.hasSuffix("}") else {
            throw PlanProposalError.malformedResponse(
                reason: "expected a single JSON object and nothing else"
            )
        }
        guard let data = text.data(using: .utf8) else {
            throw PlanProposalError.malformedResponse(reason: "the reply was not valid UTF-8")
        }
        do {
            return try JSONDecoder().decode(PlanProposal.self, from: data)
        } catch let error as PlanProposalError {
            // Already specific — a field was wrong, not the envelope. Rethrowing rather
            // than wrapping is what makes a retry worth attempting.
            throw error
        } catch let error as DecodingError {
            throw PlanProposalError.malformedResponse(reason: describe(error))
        } catch {
            throw PlanProposalError.malformedResponse(reason: "\(error)")
        }
    }

    // MARK: - The schema, derived from the core types

    /// The response shape and the plan vocabulary, worded for the prompt (§4.8a).
    ///
    /// **Generated from the core types, never hand-written.** The vocabulary a plan speaks
    /// is `ScheduledSessionKind.allCases` and `Weekday.allCases`; its bounds are
    /// `HeartRateSample.plausibleBPM` and `ScoreValue.permittedRange`. Hand-writing them
    /// here would make this a second source of truth that goes stale the first time
    /// somebody adds a session kind — and the failure would be silent, producing a model
    /// that keeps proposing a vocabulary the app no longer has. `PlanProposalTests` pins
    /// that every case of every enum named below appears in the rendered text, so adding a
    /// kind and forgetting the prompt fails CI instead.
    ///
    /// It lives beside the type it describes for the reason `ScoreProposal` gives: the
    /// instruction and the decoder must not be able to drift apart.
    ///
    /// **Carries no health data**, which is what lets it travel in the instruction next to
    /// `task` rather than through `WorkoutContext.Audience`. `Audience` selects what health
    /// data leaves the device; `task` selects what the model is asked to do. Never conflate
    /// them (§4.9).
    public static let schemaDescription: String = renderedSchema()

    private static func renderedSchema() -> String {
        let heartRate = HeartRateSample.plausibleBPM
        let scores = ScoreValue.permittedRange
        let kindLines = ScheduledSessionKind.allCases
            .map { "    - \"\($0.rawValue)\" — \(gloss(for: $0))" }
            .joined(separator: "\n")

        return """
            Reply with a single JSON object and nothing else — no prose before it, none \
            after it, no code fence:

            {
              "heartRateCapBPM": <number>,
              "cadenceLowStepsPerMinute": <number>,
              "cadenceHighStepsPerMinute": <number>,
              "effectiveThresholdPoints": <integer>,
              "marginalThresholdPoints": <integer>,
              "week": [
                {"weekday": "<weekday>", "kind": "<kind>", "distanceMeters": <number>, "note": "<text>"}
              ],
              "longRunArc": [{"index": <integer>, "distanceMeters": <number>}],
              "goalStatements": ["<one line per goal>"],
              "goalTargetDay": "<YYYY-MM-DD>"
            }

            Every distance is in metres.

            - "heartRateCapBPM" is the easy-run heart-rate ceiling, in beats per minute, \
            between \(Int(heartRate.lowerBound)) and \(Int(heartRate.upperBound)).
            - "cadenceLowStepsPerMinute" and "cadenceHighStepsPerMinute" are the cadence \
            target band, in steps per minute. Both above zero, and the low figure at or \
            below the high one.
            - "effectiveThresholdPoints" and "marginalThresholdPoints" are score cuts \
            between \(scores.lowerBound) and \(scores.upperBound). A day scoring at or \
            above the effective threshold counted as effective; one below the marginal \
            threshold went wrong. The marginal threshold must not exceed the effective one.
            - "week" is the recurring week: exactly seven entries, one for each weekday, \
            Monday first. A week is always Monday-first.
              - "weekday" is one of: \(weekdayVocabulary).
              - "kind" is one of:
            \(kindLines)
              - "distanceMeters" is the prescribed distance, above zero. Omit it for a \
            session described only by its "note" — "6 × 800m", say.
              - "note" is free text shown alongside the day. Omit it when there is nothing \
            to add.
              - A rest day carries neither a distance nor a note.
            - "longRunArc" is the long run's progression: at least one entry, "index" \
            counting weeks from 1 and strictly ascending, "distanceMeters" above zero. \
            Week 1 is the week the plan takes effect. The arc supplies the long day's \
            distance for the week it covers.
            - "goalStatements" is the athlete's goals in their own words, one per entry. \
            Omit "goalTargetDay", or give the day of the event the block builds toward as \
            YYYY-MM-DD.

            Send no other field. In particular:

            - No "version" and no "effectiveFrom". The app derives the version number, and \
            the athlete chooses the start date on the screen that saves the plan — a plan \
            carrying either could be back-dated over days that have already been scored.
            - No scoring rubric bands. The athlete's own bands are carried forward \
            unchanged into every new version, and a proposal that re-seeded them would \
            quietly change what every future run scores.
            """
    }

    /// One line per session kind, exhaustive by the compiler rather than by a dictionary
    /// somebody has to remember to extend. Adding a case stops this switch compiling,
    /// which is a stronger guarantee than the test that also checks it.
    private static func gloss(for kind: ScheduledSessionKind) -> String {
        switch kind {
        case .easy:
            return "an easy aerobic run, judged against the heart-rate cap"
        case .long:
            return "the week's long run; the long-run arc supplies its distance"
        case .hard:
            return "a hard session — intervals, tempo, hills. Put its structure in the note"
        case .rest:
            return "no session is asked for"
        case .other:
            return "scheduled, but not one of the three run types the scoring rubric "
                + "reasons about — cross-training, strength, mobility"
        }
    }

    /// "monday, tuesday, …", derived so a weekday cannot go missing from the prompt.
    static let weekdayVocabulary = Weekday.allCases.sorted()
        .map { PlanProposal.wireName(for: $0) }
        .joined(separator: ", ")

    /// "easy, long, …", derived from the enum for the same reason.
    static let sessionKindVocabulary = ScheduledSessionKind.allCases
        .map(\.rawValue)
        .joined(separator: ", ")

    // MARK: - Vocabulary

    /// The wire spelling of a weekday.
    ///
    /// A switch of its own rather than `FactSheetFormatting.weekdayName(_:).lowercased()`:
    /// that function renders a weekday for a *fact sheet*, and rewording it — "Tue" for
    /// "Tuesday", say — would silently change a wire contract with the model. Two
    /// audiences, two mappings, and this one is exhaustive so a new weekday cannot slip
    /// through untranslated.
    static func wireName(for weekday: Weekday) -> String {
        switch weekday {
        case .monday: return "monday"
        case .tuesday: return "tuesday"
        case .wednesday: return "wednesday"
        case .thursday: return "thursday"
        case .friday: return "friday"
        case .saturday: return "saturday"
        case .sunday: return "sunday"
        }
    }

    /// Case- and whitespace-insensitive: tolerant about formatting, strict about content.
    static func weekday(named text: String) -> Weekday? {
        let needle = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return Weekday.allCases.first { wireName(for: $0) == needle }
    }

    static func sessionKind(named text: String) -> ScheduledSessionKind? {
        let needle = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ScheduledSessionKind.allCases.first { $0.rawValue == needle }
    }

    /// `fileprivate` rather than `private` because `PlanProposalError.description`, one
    /// type up the file, is its only caller.
    fileprivate static func list(_ weekdays: [Weekday]) -> String {
        weekdays.map { wireName(for: $0) }.joined(separator: ", ")
    }

    /// The same normalisation `PlanAuthoringSession.goals(from:)` performs on the draft's
    /// newline-joined text, applied to an array instead: split embedded line breaks, trim,
    /// drop what is left empty. Doing it here rather than trusting the model means the
    /// proposal and the plan the door builds from it hold the identical `PlanGoals`.
    private static func normalizedGoalStatements(_ statements: [String]) -> [String] {
        statements
            .flatMap { $0.split(separator: "\n", omittingEmptySubsequences: true) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case heartRateCapBPM
        case cadenceLowStepsPerMinute, cadenceHighStepsPerMinute
        case effectiveThresholdPoints, marginalThresholdPoints
        case week, longRunArc, goalStatements, goalTargetDay

        // Never read into a proposal. Declared so `contains` can refuse a reply that
        // tries to set one, rather than `JSONDecoder` dropping it silently — see
        // `PlanProposalError.forbiddenField` for why silence is the worse outcome.
        case version, effectiveFrom, rubric, rubricBands, bands
    }

    /// The keys §4.4 forbids, in the spellings a model plausibly reaches for.
    private static let forbiddenKeys: [CodingKeys] = [
        .version, .effectiveFrom, .rubric, .rubricBands, .bands,
    ]

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(heartRateCapBPM, forKey: .heartRateCapBPM)
        try container.encode(cadenceLowStepsPerMinute, forKey: .cadenceLowStepsPerMinute)
        try container.encode(cadenceHighStepsPerMinute, forKey: .cadenceHighStepsPerMinute)
        try container.encode(effectiveThresholdPoints, forKey: .effectiveThresholdPoints)
        try container.encode(marginalThresholdPoints, forKey: .marginalThresholdPoints)
        try container.encode(week, forKey: .week)
        try container.encode(longRunArc, forKey: .longRunArc)
        try container.encode(goalStatements, forKey: .goalStatements)
        try container.encodeIfPresent(goalTargetDay, forKey: .goalTargetDay)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        for key in PlanProposal.forbiddenKeys where container.contains(key) {
            throw PlanProposalError.forbiddenField(name: key.stringValue)
        }

        // Read in the order the schema lists the fields, so a reply with two faults is
        // reported for the first one a person reading it top to bottom would find.
        let heartRateCapBPM = try PlanProposal.decode(Double.self, .heartRateCapBPM, from: container)
        let cadenceLow = try PlanProposal.decode(Double.self, .cadenceLowStepsPerMinute, from: container)
        let cadenceHigh = try PlanProposal.decode(Double.self, .cadenceHighStepsPerMinute, from: container)
        let effective = try PlanProposal.decode(Int.self, .effectiveThresholdPoints, from: container)
        let marginal = try PlanProposal.decode(Int.self, .marginalThresholdPoints, from: container)
        let week = try PlanProposal.decode([Day].self, .week, from: container)
        let arc = try PlanProposal.decode([ArcWeek].self, .longRunArc, from: container)
        let statements = try container.decodeIfPresent([String].self, forKey: .goalStatements) ?? []

        var goalTargetDay: CalendarDay?
        if let raw = try container.decodeIfPresent(String.self, forKey: .goalTargetDay) {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                guard let parsed = try? CalendarDay(iso8601: trimmed) else {
                    throw PlanProposalError.malformedGoalTargetDay(value: raw)
                }
                goalTargetDay = parsed
            }
        }

        try self.init(
            heartRateCapBPM: heartRateCapBPM,
            cadenceLowStepsPerMinute: cadenceLow,
            cadenceHighStepsPerMinute: cadenceHigh,
            effectiveThresholdPoints: effective,
            marginalThresholdPoints: marginal,
            week: week,
            longRunArc: arc,
            goalStatements: statements,
            goalTargetDay: goalTargetDay
        )
    }

    /// Decoding that reports an absent key as an absent *field*.
    ///
    /// "The reply left out heartRateCapBPM" is a sentence a model can act on; the
    /// `DecodingError` it replaces is a sentence about Swift.
    fileprivate static func decode<Key: CodingKey, Value: Decodable>(
        _ type: Value.Type,
        _ key: Key,
        from container: KeyedDecodingContainer<Key>
    ) throws -> Value {
        do {
            return try container.decode(type, forKey: key)
        } catch let error as DecodingError {
            switch error {
            case .keyNotFound, .valueNotFound:
                throw PlanProposalError.missingField(name: key.stringValue)
            default:
                throw error
            }
        }
    }

    fileprivate static func decodeString<Key: CodingKey>(
        _ key: Key,
        from container: KeyedDecodingContainer<Key>
    ) throws -> String {
        try decode(String.self, key, from: container)
    }

    /// A `DecodingError` in words, without the reply that produced it.
    ///
    /// The coding path and the failure's kind are enough for a retry to be worth
    /// attempting; the underlying value is not included, because an error string is a
    /// thing that gets logged and a proposal describes the athlete's training.
    private static func describe(_ error: DecodingError) -> String {
        func path(_ context: DecodingError.Context) -> String {
            let keys = context.codingPath.map(\.stringValue)
            return keys.isEmpty ? "the object" : "\"\(keys.joined(separator: "."))\""
        }
        switch error {
        case let .typeMismatch(type, context):
            return "\(path(context)) was not a \(type)"
        case let .valueNotFound(_, context):
            return "\(path(context)) was null"
        case let .keyNotFound(key, context):
            let container = context.codingPath.isEmpty
                ? "the object"
                : "\"\(context.codingPath.map(\.stringValue).joined(separator: "."))\""
            return "\(container) has no \"\(key.stringValue)\""
        case .dataCorrupted:
            return "it was not valid JSON"
        @unknown default:
            return "it could not be decoded"
        }
    }
}

import Foundation

/// Why a candidate plan version cannot be saved, in words an athlete can act on
/// (MAX-080).
///
/// Separate from `DomainError` on purpose. `DomainError`'s messages name fields and
/// bounds — "Plan.heartRateCapBPM must be within [20.0, 250.0], got 400.0" — which is
/// the right thing for a test assertion and the wrong thing for a screen. These say
/// what the athlete did and what to do instead. Carrying no free-form payload from the
/// underlying error also keeps this safe to log: nothing here can hold health data.
public enum PlanAuthoringError: Error, Hashable, Sendable, CustomStringConvertible {
    /// The chosen start date is on or before the date the current version began.
    ///
    /// This is D1's no-back-dating rule reaching the surface. `PlanCalendar` refuses
    /// such a version because it would re-govern days that have already been scored,
    /// and D8 makes those scores immutable — so the stored score and a recomputation
    /// would disagree, with no way to tell which is right.
    case effectiveFromTooEarly(earliestPermitted: CalendarDay)

    case heartRateCapImplausible(permitted: ClosedRange<Double>)
    case cadenceBandInverted
    case cadenceBandNotPositive
    case thresholdsInverted
    case scoreThresholdOutOfRange(permitted: ClosedRange<Int>)
    case scheduledDistanceNotPositive(weekday: Weekday)
    case longRunDistanceNotPositive(week: Int)

    /// The duration floor (`PlanDraft.minimumSessionDurationSeconds`, MAX-151) is set but
    /// not a positive, finite number of seconds.
    ///
    /// Reachable through the screen: a stepper's minutes are converted to seconds and
    /// clamped at zero the way the lift's own duration stepper is (`0` reads as "no
    /// floor" rather than a floor of zero) — but `PlanDraft`'s own property is a plain
    /// `var`, not gated behind a setter the way `DayDraft`'s fields are, so nothing stops
    /// a caller assembling a draft by hand from setting one non-positive. Checked here for
    /// the same belt-and-braces reason `liftSessionInvalid` is.
    case minimumSessionDurationNotPositive

    /// The run slot's kind is not one `ScheduledSessionKind.prescribable` permits — in
    /// practice, `.lift` (MAX-148).
    ///
    /// Unreachable through the screen: `PlanDraft.DayDraft.setKind` refuses `.lift`
    /// outright, so nothing authored here can produce this. Kept as a real, readable
    /// case rather than a `try!` for the same reason `wouldRewriteHistory` is — a
    /// `PlanDraft` built from a stored `Plan` whose run slot already held a lift
    /// (`WeeklyTemplate` itself does not forbid one) reaches this check on save rather
    /// than saving a plan judged against the wrong slot.
    case scheduledKindNotPrescribable(weekday: Weekday)

    /// The lift slot the athlete assembled is not a legal session.
    ///
    /// Reachable as of MAX-148: `setLiftDurationSeconds` accepts any value a stepper
    /// hands it, so a non-positive or non-finite duration reaches `liftSession()`
    /// unvalidated and this is where it is caught. The muscle-group combination
    /// `ScheduledSession` also rejects stays unreachable, for the reason
    /// `wouldRewriteHistory` documents: `setLiftKind` clears the groups the moment the
    /// kind leaves `.lift`, so `DayDraft.liftSession()` has no path left to it.
    case liftSessionInvalid(weekday: Weekday)

    /// The version set this plan would produce is not one `PlanCalendar` accepts.
    ///
    /// Unreachable in practice — `effectiveFromTooEarly` is checked first and covers
    /// the only way a session-built plan can break the ordering — and kept anyway
    /// because the alternative to a belt-and-braces case is a `try!`. If it ever fires,
    /// the plan set on disk is not what this session was built from.
    case wouldRewriteHistory

    public var description: String {
        switch self {
        case let .effectiveFromTooEarly(earliest):
            return "A new plan version has to start after the current one does. "
                + "The earliest date this version can take effect is \(PlanCopy.day(earliest))."
        case let .heartRateCapImplausible(permitted):
            return "The heart-rate cap has to be between \(Int(permitted.lowerBound)) and "
                + "\(Int(permitted.upperBound)) bpm."
        case .cadenceBandInverted:
            return "The cadence target's lower figure has to be at or below its upper figure."
        case .cadenceBandNotPositive:
            return "The cadence target has to be above zero steps per minute."
        case .thresholdsInverted:
            return "The marginal score threshold has to be at or below the effective one."
        case let .scoreThresholdOutOfRange(permitted):
            return "Score thresholds have to be between \(permitted.lowerBound) and "
                + "\(permitted.upperBound)."
        case let .scheduledDistanceNotPositive(weekday):
            return "\(PlanCopy.weekday(weekday)) prescribes a distance of zero. Give it a distance, "
                + "or leave the distance off entirely."
        case let .longRunDistanceNotPositive(week):
            return "Week \(week) of the long-run arc prescribes a distance of zero."
        case .minimumSessionDurationNotPositive:
            return "The duration floor has to be a positive number of seconds, or left "
                + "unset to state no floor at all."
        case let .scheduledKindNotPrescribable(weekday):
            return "\(PlanCopy.weekday(weekday))'s run slot cannot prescribe a lift. Use the lift "
                + "slot below it."
        case let .liftSessionInvalid(weekday):
            return "\(PlanCopy.weekday(weekday))'s lift prescription is not valid. Reopen the "
                + "screen and try again."
        case .wouldRewriteHistory:
            return "This version would change days an earlier plan version already governs, "
                + "so it cannot be saved. Reopen the screen and try again."
        }
    }
}

/// One sitting at the plan-authoring screen: what version is being written, the
/// earliest day it may take effect, and the draft it starts from (MAX-080).
///
/// ## Why the version and the date are derived here rather than chosen
///
/// D1's guarantee is that a historical score can always be reproduced, and MAX-011
/// implements it as two ordering rules on the version set: a later `effectiveFrom` must
/// carry a higher `version`, and no version may begin on or before one already stored.
/// A screen that let an athlete type either field would be a screen that can express a
/// rejected plan, and the rejection would arrive at save time — after the work.
///
/// So neither is an input. `version` is the successor of the highest stored version.
/// `earliestEffectiveFrom` is the day after the current version began. The screen's job
/// is to not offer anything earlier; `plan(from:effectiveFrom:)` checks anyway, because
/// "the UI won't send that" is not an invariant.
///
/// **MAX-011's validation is not weakened to make any of this easier.** The last thing
/// `plan(from:effectiveFrom:)` does is construct the `PlanCalendar` this write would
/// produce and let it throw — the same check `MaximizeStore.store(_:)` performs before
/// touching disk. The two agree because they run the same code, not because they were
/// written to match.
///
/// ## The rubric a revision writes (MAX-173)
///
/// Until MAX-173 a revision carried `current.rubric.bands` forward verbatim, and there
/// was no other path. That made the seed's bands unreachable for anybody whose plan
/// already existed: MAX-132's three `lift.*` adherence bands and MAX-146's
/// `.actualDiscipline(oneOf: [.run])` on `rest.ranAnyway` were corrections no device
/// could ever receive, which is why the lift ingestion gate could not open.
///
/// So a session now knows two band lists — the ones the superseded version was saved
/// with, and the ones this build ships — and `adoptsCurrentRubric` says which it will
/// write. **It writes the current ones by default**, for three reasons stated together
/// because no one of them carries it alone:
///
/// 1. **Nothing stored carries athlete intent.** There is no band editor and never has
///    been (`PlanDraft` deliberately omits the bands), so every band inside every stored
///    plan is a past copy of `StandardPlanSeed.rubricBands()`. Adopting is taking the
///    corrected version of rules the athlete never chose, not overwriting a position they
///    took. *If a band editor ever ships, this default must be revisited* — at that point
///    a stored rubric can mean something, and `adoptingCurrentRubric(false)` is the
///    behaviour to make the default.
/// 2. **It cannot move history.** A rubric change is a new version with its own
///    `effectiveFrom`, and scoring resolves the version in effect on the workout's own
///    date (D1/D8). The blast radius is days this version governs, all of which are on or
///    after a date the athlete picks.
/// 3. **Declining is the failure mode with no exit.** An athlete who leaves it off keeps
///    a rubric that stamps their lifts *"Ran on a scheduled rest day."* forever, and
///    nothing later can reach back and fix it.
///
/// None of that makes it silent: `rubricUpdate` describes the change and is non-empty
/// exactly when there is one, and `PlanAuthoringView` states it above the switch. What is
/// deliberately **not** offered is a band-level diff — see `PlanRubricUpdate` for why a
/// rendered `RubricCondition` is a sentence about a data structure rather than about
/// training.
public struct PlanAuthoringSession: Hashable, Sendable {

    public enum Mode: Hashable, Sendable {
        /// Nothing has been authored. Version 1, and — uniquely — free to start on any
        /// day, including a past one: there is no earlier version whose days could be
        /// re-governed, and back-dating is how already-captured runs come under a plan
        /// at all. See `PlanAuthoring.session(revising:today:)`.
        case firstPlan
        /// Superseding a stored version. Carries what it supersedes so a screen can say
        /// so without re-reading the calendar.
        case revision(supersedes: PlanVersion, inEffectSince: CalendarDay)
    }

    public let mode: Mode

    /// The version the saved plan will carry. Not editable — see the type's note.
    public let version: PlanVersion

    /// The earliest day this version may take effect, or nil when any day is permitted
    /// (a first plan). A screen must not offer a date before this.
    public let earliestEffectiveFrom: CalendarDay?

    /// Where the screen's date control should start.
    ///
    /// For a first plan, the day that covers the history already on the device — see
    /// `FirstPlanDating.suggestedEffectiveFrom(covering:today:)` for both halves of that
    /// and why the ceiling is still the current training week's Monday. **This used to be
    /// the training week's Monday unconditionally, and that was the MAX-165 defect**: an
    /// athlete who accepted it on install day permanently stranded most of a ninety-day
    /// backfill.
    ///
    /// For a revision, today — or the earliest permitted day if today is not yet
    /// permitted, which happens only when the current version began today.
    public let suggestedEffectiveFrom: CalendarDay

    /// The draft the screen starts from: the seed for a first plan, or an exact copy of
    /// the version being superseded.
    public let draft: PlanDraft

    /// The bands the version being superseded was saved with — the seed's own on a first
    /// plan, where there is nothing to supersede. See `PlanDraft`'s note on why the bands
    /// are not part of the draft.
    private let storedRubricBands: [RubricBand]

    /// The bands this build of the app ships (`StandardPlanSeed.rubricBands()`), read
    /// once at construction so the session's answers cannot change under a caller.
    private let currentRubricBands: [RubricBand]

    /// What adopting the current rules would change about the stored ones. Empty when
    /// there is nothing to adopt — always so for a first plan, whose two lists are the
    /// same list.
    public let rubricUpdate: PlanRubricUpdate

    /// Whether the version this session writes carries the current rules or the stored
    /// ones. True by default; see the type's note for the argument.
    ///
    /// `private(set)` with `adoptingCurrentRubric(_:)` as the only door, rather than a
    /// plain `var`: this decides what a saved plan permanently *means*, and a settable
    /// property is one a view could flip as a side effect of some unrelated binding.
    public private(set) var adoptsCurrentRubric: Bool

    /// The versions already stored. Kept so the ordering check runs against the real
    /// set rather than a remembered summary of it.
    private let existing: PlanCalendar?

    /// What is already captured, so the session can price a candidate date (MAX-165).
    ///
    /// Held rather than reduced to a single count at construction, because the count is a
    /// function of the date the athlete is currently pointing at and that changes as they
    /// drag the control.
    private let capturedHistory: CapturedWorkoutHistory

    init(
        mode: Mode,
        version: PlanVersion,
        earliestEffectiveFrom: CalendarDay?,
        suggestedEffectiveFrom: CalendarDay,
        draft: PlanDraft,
        storedRubricBands: [RubricBand],
        currentRubricBands: [RubricBand],
        existing: PlanCalendar?,
        capturedHistory: CapturedWorkoutHistory = .empty
    ) {
        self.mode = mode
        self.version = version
        self.earliestEffectiveFrom = earliestEffectiveFrom
        self.suggestedEffectiveFrom = suggestedEffectiveFrom
        self.draft = draft
        self.storedRubricBands = storedRubricBands
        self.currentRubricBands = currentRubricBands
        self.rubricUpdate = PlanRubricUpdate(stored: storedRubricBands, current: currentRubricBands)
        self.adoptsCurrentRubric = true
        self.existing = existing
        self.capturedHistory = capturedHistory
    }

    // MARK: - Which rules this version writes (MAX-173)

    /// The session that writes the current rules, or the stored ones.
    ///
    /// A returned copy rather than a mutation, so the choice travels with the value a
    /// screen is holding and there is no moment where a half-configured session exists.
    /// A no-op when the two lists agree — including for every first plan.
    public func adoptingCurrentRubric(_ adopt: Bool = true) -> PlanAuthoringSession {
        var updated = self
        updated.adoptsCurrentRubric = adopt
        return updated
    }

    /// What has changed since the superseded version was saved, in the athlete's words —
    /// nil when nothing has, or when there is no version to have moved on from.
    ///
    /// The decision and the sentence live together here for the reason
    /// `excludedWorkoutsNotice` does: what the athlete is told is then verified on every
    /// commit and cannot drift from the fact it is a sentence about.
    public var rubricUpdateNotice: String? {
        guard case let .revision(supersedes, _) = mode else { return nil }
        return PlanCopy.rubricUpdateNotice(rubricUpdate, supersedes: supersedes)
    }

    /// What declining leaves in place, or nil when there is nothing to decline.
    public var rubricUpdateDeclineNotice: String? {
        guard case let .revision(supersedes, _) = mode, !rubricUpdate.isEmpty else { return nil }
        return PlanCopy.rubricUpdateDeclineNotice(supersedes: supersedes)
    }

    /// The bands `plan(from:effectiveFrom:)` will write.
    private var rubricBands: [RubricBand] {
        adoptsCurrentRubric ? currentRubricBands : storedRubricBands
    }

    // MARK: - What a candidate date costs (MAX-165, A23)

    /// How many already-captured workouts a first plan taking effect on `day` would leave
    /// permanently unmeasurable.
    ///
    /// **Zero for a revision, always.** A revision cannot strand anything: every day
    /// before its effective date is already governed by the version it supersedes, which
    /// is exactly what `earliestEffectiveFrom` bounds it to. Asking this question of a
    /// revision is a category error, and answering it with the same arithmetic the first
    /// plan uses would put a frightening and false number on the screen of an athlete
    /// whose history is entirely covered.
    public func workoutsExcluded(byEffectiveFrom day: CalendarDay) -> Int {
        guard case .firstPlan = mode else { return 0 }
        return capturedHistory.workoutsExcluded(byEffectiveFrom: day)
    }

    /// The sentence a screen shows beneath its date control, or nil when the date costs
    /// nothing — see `PlanCopy.excludedWorkoutsNotice(count:)` for why nil rather than a
    /// rendered zero.
    ///
    /// The decision and the words are both here rather than beside the control, so what
    /// the athlete is told is verified on every commit and cannot drift from the number it
    /// is a sentence about.
    public func excludedWorkoutsNotice(forEffectiveFrom day: CalendarDay) -> String? {
        PlanCopy.excludedWorkoutsNotice(count: workoutsExcluded(byEffectiveFrom: day))
    }

    /// Whether a day is one this version may take effect on.
    ///
    /// Exposed so a screen can bound its date control rather than validate after the
    /// fact — constraint 2 of MAX-080 is that a rejected date should not be offered.
    public func permitsEffectiveFrom(_ day: CalendarDay) -> Bool {
        guard let earliestEffectiveFrom else { return true }
        return day >= earliestEffectiveFrom
    }

    /// The immutable plan this draft would become. **The only way a draft becomes a
    /// plan.**
    ///
    /// - Throws: `PlanAuthoringError`. Every failure is translated, so a caller can put
    ///   `error.description` on screen without leaking a field name at the athlete.
    public func plan(from draft: PlanDraft, effectiveFrom: CalendarDay) throws -> Plan {
        guard permitsEffectiveFrom(effectiveFrom) else {
            // `earliestEffectiveFrom` is non-nil whenever `permitsEffectiveFrom` is
            // false; the coalesce exists only because force unwraps are banned.
            throw PlanAuthoringError.effectiveFromTooEarly(
                earliestPermitted: earliestEffectiveFrom ?? effectiveFrom
            )
        }

        let plan = try Plan(
            version: version,
            effectiveFrom: effectiveFrom,
            weeklyTemplate: try weeklyTemplate(from: draft),
            longRunArc: try longRunArc(from: draft),
            heartRateCapBPM: try heartRateCap(from: draft),
            cadenceTarget: try cadenceBand(from: draft),
            rubric: try rubric(from: draft),
            goals: goals(from: draft),
            minimumSessionDurationSeconds: try minimumSessionDurationSeconds(from: draft)
        )

        _ = try calendar(including: plan)
        return plan
    }

    /// What this version would govern, resolved through the same calendar the scorer
    /// will use.
    ///
    /// This is the confirmation half of the screen: an athlete about to save a plan
    /// should be able to see the days it prescribes, and seeing them resolved — long
    /// runs already carrying the arc's distance for their week, not the template's
    /// placeholder — is the only way to catch an arc that starts on the wrong week.
    ///
    /// - Parameter dayCount: days from `effectiveFrom`, inclusive. Seven shows the
    ///   recurring week exactly once.
    public func governedDays(
        from draft: PlanDraft,
        effectiveFrom: CalendarDay,
        dayCount: Int = 7
    ) throws -> [PlanDay] {
        guard dayCount >= 1 else {
            throw DomainError.outOfRange(
                field: "PlanAuthoringSession.governedDays.dayCount",
                value: Double(dayCount),
                lowerBound: 1,
                upperBound: nil
            )
        }
        let candidate = try plan(from: draft, effectiveFrom: effectiveFrom)
        let resolved = try calendar(including: candidate)
        return try resolved.planDays(
            from: effectiveFrom,
            through: try effectiveFrom.adding(days: dayCount - 1)
        )
    }

    // MARK: - Translating a draft, one field at a time

    /// Runs MAX-011's rules over the set this write would produce.
    ///
    /// The same construction `MaximizeStore.store(_:)` performs before writing. Doing it
    /// here means the screen finds out while the plan is still a candidate, and finds
    /// out for the same reason the store would.
    private func calendar(including plan: Plan) throws -> PlanCalendar {
        var versions = existing?.versions ?? []
        versions.removeAll { $0.version == plan.version }
        versions.append(plan)
        do {
            return try PlanCalendar(versions)
        } catch {
            throw PlanAuthoringError.wouldRewriteHistory
        }
    }

    private func heartRateCap(from draft: PlanDraft) throws -> Double {
        guard draft.heartRateCapBPM.isFinite,
              HeartRateSample.plausibleBPM.contains(draft.heartRateCapBPM)
        else {
            throw PlanAuthoringError.heartRateCapImplausible(permitted: HeartRateSample.plausibleBPM)
        }
        return draft.heartRateCapBPM
    }

    /// The duration floor, validated the same way `Plan.init` validates it
    /// (`Validate.optionalPositive`). Unlike every other plan-level number this session
    /// translates, nil is itself a legal answer — "no opinion" — matching `Plan`'s own
    /// default; only a *stated* value has to be positive.
    private func minimumSessionDurationSeconds(from draft: PlanDraft) throws -> Double? {
        guard let value = draft.minimumSessionDurationSeconds else { return nil }
        guard value.isFinite, value > 0 else {
            throw PlanAuthoringError.minimumSessionDurationNotPositive
        }
        return value
    }

    private func cadenceBand(from draft: PlanDraft) throws -> CadenceBand {
        guard draft.cadenceLowStepsPerMinute.isFinite, draft.cadenceLowStepsPerMinute > 0,
              draft.cadenceHighStepsPerMinute.isFinite, draft.cadenceHighStepsPerMinute > 0
        else {
            throw PlanAuthoringError.cadenceBandNotPositive
        }
        guard draft.cadenceLowStepsPerMinute <= draft.cadenceHighStepsPerMinute else {
            throw PlanAuthoringError.cadenceBandInverted
        }
        return try CadenceBand(
            lowStepsPerMinute: draft.cadenceLowStepsPerMinute,
            highStepsPerMinute: draft.cadenceHighStepsPerMinute
        )
    }

    private func rubric(from draft: PlanDraft) throws -> ScoringRubric {
        guard ScoreValue.permittedRange.contains(draft.effectiveThresholdPoints),
              ScoreValue.permittedRange.contains(draft.marginalThresholdPoints)
        else {
            throw PlanAuthoringError.scoreThresholdOutOfRange(permitted: ScoreValue.permittedRange)
        }
        guard draft.marginalThresholdPoints <= draft.effectiveThresholdPoints else {
            throw PlanAuthoringError.thresholdsInverted
        }
        // The two thresholds come from the draft, because they are single numbers an
        // athlete has an opinion about; the bands come from the session, because they are
        // not editable anywhere and `adoptsCurrentRubric` is the only choice about them
        // (MAX-173).
        return try ScoringRubric(
            effectiveThreshold: ScoreValue(draft.effectiveThresholdPoints),
            marginalThreshold: ScoreValue(draft.marginalThresholdPoints),
            bands: rubricBands
        )
    }

    /// Both slots are assembled from the draft's own loose fields now (MAX-137) and can
    /// therefore both fail validation, each with its own readable error.
    ///
    /// The `prescribable` check runs first and independently of `day.session()`'s own
    /// throw (MAX-148): `WeeklyTemplate` itself does not refuse a `.lift` run slot — see
    /// `PlanAuthoringError.scheduledKindNotPrescribable`'s note on why this is
    /// belt-and-braces rather than dead code.
    private func weeklyTemplate(from draft: PlanDraft) throws -> WeeklyTemplate {
        var sessions: [Weekday: ScheduledSession] = [:]
        var liftSessions: [Weekday: ScheduledSession] = [:]
        for day in draft.week {
            guard ScheduledSessionKind.prescribable.contains(day.kind) else {
                throw PlanAuthoringError.scheduledKindNotPrescribable(weekday: day.weekday)
            }
            guard let session = try? day.session() else {
                throw PlanAuthoringError.scheduledDistanceNotPositive(weekday: day.weekday)
            }
            guard let liftSession = try? day.liftSession() else {
                throw PlanAuthoringError.liftSessionInvalid(weekday: day.weekday)
            }
            sessions[day.weekday] = session
            liftSessions[day.weekday] = liftSession
        }
        return try WeeklyTemplate(sessions, lift: liftSessions)
    }

    private func longRunArc(from draft: PlanDraft) throws -> LongRunArc {
        var weeks: [LongRunArc.Week] = []
        for week in draft.longRunArc {
            guard let resolved = try? LongRunArc.Week(
                index: week.index,
                distanceMeters: week.distanceMeters
            ) else {
                throw PlanAuthoringError.longRunDistanceNotPositive(week: week.index)
            }
            weeks.append(resolved)
        }
        return try LongRunArc(weeks: weeks)
    }

    /// Goals are narrative context, not something the code branches on (`PlanGoals`),
    /// so the only processing is dropping blank lines an athlete's stray return left
    /// behind.
    private func goals(from draft: PlanDraft) -> PlanGoals {
        let statements = draft.goalStatements
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return PlanGoals(statements: statements, targetDay: draft.goalTargetDay)
    }
}

/// Opening a plan-authoring session against whatever is already stored (MAX-080).
public enum PlanAuthoring {

    /// The session for writing the next plan version.
    ///
    /// - Parameters:
    ///   - calendar: every stored version, or nil when nothing has been authored —
    ///     `PlanRepository.planCalendar()`'s own shape. Nil is a real state on a fresh
    ///     install, and it is the state this ticket exists to get the app out of.
    ///   - today: the athlete's civil day. Passed in rather than read from a clock,
    ///     because turning an instant into a day needs a time zone and `MaximizeCore`
    ///     does not get to pick one (`CalendarDay.init(_:in:)`).
    ///   - capturedHistory: the days workouts are already stored on (MAX-165, A23). Only
    ///     a first plan reads it, and only to decide what date to *suggest* and what a
    ///     candidate date would cost; nothing here is validation, and no date becomes
    ///     illegal because of it. Defaults to `.empty`, which reproduces the pre-MAX-165
    ///     suggestion exactly — a caller that has not asked the store gets the answer it
    ///     always got rather than a guess.
    public static func session(
        revising calendar: PlanCalendar?,
        today: CalendarDay,
        capturedHistory: CapturedWorkoutHistory = .empty
    ) throws -> PlanAuthoringSession {
        // Read once, for both branches. A first plan's stored and current lists are the
        // same list — there is nothing to have moved on from — so its `rubricUpdate` is
        // empty and adoption is a no-op, exactly as it should be.
        let currentRubricBands = try StandardPlanSeed.rubricBands()

        guard let calendar, let current = currentVersion(of: calendar) else {
            return PlanAuthoringSession(
                mode: .firstPlan,
                version: try PlanVersion(1),
                // Unbounded backwards, and deliberately so. Every run captured before
                // the first plan sits in `.noPlanAuthored` with no derived metrics and
                // no score; back-dating the first version is the only thing that can
                // bring them under a plan, because MAX-011 forbids every *later*
                // version from reaching backwards. It is the one moment this is safe:
                // there is no earlier version, so there is nothing to re-govern.
                //
                // MAX-165: this permission has always been here. What was missing was a
                // suggestion that used it.
                earliestEffectiveFrom: nil,
                suggestedEffectiveFrom: try FirstPlanDating.suggestedEffectiveFrom(
                    covering: capturedHistory,
                    today: today
                ),
                draft: try StandardPlanSeed.draft(),
                storedRubricBands: currentRubricBands,
                currentRubricBands: currentRubricBands,
                existing: nil,
                capturedHistory: capturedHistory
            )
        }

        let earliest = try current.effectiveFrom.adding(days: 1)
        return PlanAuthoringSession(
            mode: .revision(supersedes: current.version, inEffectSince: current.effectiveFrom),
            version: try PlanVersion(current.version.number + 1),
            earliestEffectiveFrom: earliest,
            suggestedEffectiveFrom: max(today, earliest),
            draft: try PlanDraft(current),
            storedRubricBands: current.rubric.bands,
            currentRubricBands: currentRubricBands,
            existing: calendar,
            // Carried for symmetry and for a future reader, never consulted: a revision
            // cannot exclude anything, and `workoutsExcluded(byEffectiveFrom:)` says so
            // by returning zero before it ever reaches this.
            capturedHistory: capturedHistory
        )
    }

    /// The highest stored version — "the plan in force".
    ///
    /// `PlanCalendar` orders by `effectiveFrom` and guarantees the version number
    /// ascends with it, so the last element is also the highest version — but this asks
    /// for the highest version explicitly rather than relying on that coupling, since
    /// the successor version is the one thing that must never come out low.
    ///
    /// Public since MAX-101, because a third reader appeared. `PlanDisplayData` already
    /// answered the same question with the same `max(by:)` and a comment pointing here,
    /// and the proposal card needs it too — "what does this proposal change against" has
    /// to be the *same* version the authoring screen is superseding, or the diff
    /// describes a comparison the handoff will not make. Two notions of "current" is
    /// exactly the drift D2/D3 exist to prevent.
    ///
    /// Note what this is **not**: "the version governing today". A version saved this
    /// morning to take effect next Monday is the current one from the moment it is
    /// stored. See `PlanDisplayData`'s own note for why that is the right reading.
    public static func currentVersion(of calendar: PlanCalendar) -> Plan? {
        calendar.versions.max { $0.version < $1.version }
    }
}

import Foundation

/// A prepared, read-only view of a stored plan (MAX-102, A15).
///
/// ## Why this exists
///
/// The plan is legible today only while it is being edited — `PlanAuthoringView`
/// shows a *draft*, and nothing shows a saved version back. This is the other half:
/// every decision a screen would otherwise have to make (which version is "current",
/// which arc week is "this week", how a superseded version's effective range reads) is
/// resolved here, under test, so the view is left with nothing to do but lay out
/// values that are already decided (CLAUDE.md's thin-shell rule).
///
/// ## What "current" means, and why it is not "governs today"
///
/// `PlanAuthoringSession` already answers this question for the authoring screen — the
/// current plan is **the highest stored version**, full stop, independent of whether
/// its `effectiveFrom` has arrived yet (`PlanAuthoring.currentVersion(of:)`). A plan
/// saved this morning to take effect next Monday is "the current plan, in effect from
/// Monday" there, not "not current until Monday." This type answers the same question
/// the same way, for the same reason: two notions of "current" — one for authoring, one
/// for reading — would be exactly the drift D2/D3 exist to prevent, and an athlete who
/// just saved a revision would open this screen and not find it.
///
/// ## Historical versions are shown as-is (D1)
///
/// Viewing an older version never recomputes anything about *it* — its week, its arc,
/// its rubric are read verbatim off the stored `Plan`. The one thing that does not
/// carry over to a historical version is the "current arc week" marker: a week is only
/// "this week" relative to a plan that is actually governing days right now, and a
/// superseded version is not (see `currentArcWeekIndex`'s documentation).
public enum PlanDisplayData: Hashable, Sendable {
    /// No plan has ever been authored — a real state on a fresh install
    /// (`PlanRepository.planCalendar()` returning nil), and distinct from "the plan
    /// prescribes nothing." Mirrors `PlanAuthoringSession.Mode.firstPlan`.
    case notAuthored

    case authored(Authored)

    /// A stored plan calendar, prepared for display.
    public struct Authored: Hashable, Sendable {
        /// The version this screen is showing — the current one, or a historical one
        /// the athlete tapped into from `history`.
        public let viewing: VersionDetail

        /// Every stored version, newest first, so the current plan is also the first
        /// row. Includes the version being viewed, so the view can mark it rather than
        /// offer a redundant link to itself.
        public let history: [VersionSummary]
    }

    /// One weekday's ask, resolved off the stored `WeeklyTemplate` (Monday-first,
    /// matching `Weekday`'s own ordering).
    public struct WeekdayRow: Hashable, Sendable, Identifiable {
        public var id: Weekday { weekday }
        public let weekday: Weekday
        public let kind: ScheduledSessionKind
        /// Metres, matching storage (D2) — the view converts for display.
        public let distanceMeters: Double?
        public let note: String?
    }

    /// One row of the long-run arc.
    public struct ArcWeekRow: Hashable, Sendable, Identifiable {
        public var id: Int { index }
        public let index: Int
        /// Metres, matching storage (D2) — the view converts for display.
        public let distanceMeters: Double
        /// True on at most one row, and only when the plan being shown is the current
        /// one — see `VersionDetail.currentArcWeekIndex`.
        public let isCurrentWeek: Bool
    }

    /// One rubric band, read-only. Carries the athlete-facing rationale rather than the
    /// raw `RubricCondition` list — the conditions are the scorer's evaluation grammar,
    /// not something this screen renders; `rationale` is already the human-readable
    /// answer to "why does this band apply."
    public struct RubricBandRow: Hashable, Sendable, Identifiable {
        public var id: String { identifier }
        public let identifier: String
        /// Which scheduled kinds this band applies to. Empty means "any."
        public let appliesTo: [ScheduledSessionKind]
        public let scoreRange: ScoreRange
        public let rationale: String
    }

    /// One stored version, fully resolved.
    public struct VersionDetail: Hashable, Sendable {
        public let version: PlanVersion
        public let effectiveFrom: CalendarDay
        /// The last day this version governed, or nil while it is the current version
        /// — it has no successor yet. The day *before* the next version's
        /// `effectiveFrom`, since `PlanCalendar.plan(on:)` is inclusive of
        /// `effectiveFrom` (a version's reign ends the instant the next one begins).
        public let effectiveThrough: CalendarDay?
        public let isCurrent: Bool

        public let goalStatements: [String]
        public let goalTargetDay: CalendarDay?

        public let heartRateCapBPM: Double
        public let cadenceTarget: CadenceBand

        /// Exactly seven rows, Monday-first.
        public let week: [WeekdayRow]

        /// Ascending by week index.
        public let arc: [ArcWeekRow]

        /// The 1-based arc week `today` falls in, or nil. Present **only when
        /// `isCurrent` is true** — a superseded version is not governing any day right
        /// now, so it has no "this week" to mark, and marking one anyway would present
        /// a historical record as though it still applied (the thing D1 says not to
        /// do). Also nil for the current version itself when its `effectiveFrom` has
        /// not arrived yet, for the same reason: there is no week of it happening now.
        public let currentArcWeekIndex: Int?

        public let effectiveThreshold: ScoreValue
        public let marginalThreshold: ScoreValue
        /// Ordered; first match wins — the same order the scorer evaluates in.
        public let bands: [RubricBandRow]
    }

    /// One row of the version-history list.
    public struct VersionSummary: Hashable, Sendable, Identifiable {
        public var id: PlanVersion { version }
        public let version: PlanVersion
        public let effectiveFrom: CalendarDay
        public let effectiveThrough: CalendarDay?
        public let isCurrent: Bool
        /// True for the version `Authored.viewing` already shows — the row the view
        /// should render as "you are here" rather than as a link.
        public let isViewing: Bool
    }

    /// Builds the prepared display for a stored plan calendar.
    ///
    /// - Parameters:
    ///   - calendar: `PlanRepository.planCalendar()`'s own shape — nil is a real state
    ///     on a fresh install, and produces `.notAuthored` rather than throwing.
    ///   - version: which stored version to show. Nil shows the current one (the
    ///     highest stored version). A non-nil value not present in `calendar` is a
    ///     caller bug — every version a view can pass in was itself read off this same
    ///     calendar's `history` — and throws rather than silently substituting a
    ///     different version.
    ///   - today: the athlete's civil day, threaded in rather than read from the wall
    ///     clock — matching every other date-sensitive entry point in `MaximizeCore`
    ///     (`PlanAuthoring.session(revising:today:)`, `TalliesCalculator`).
    public static func build(
        from calendar: PlanCalendar?,
        viewing version: PlanVersion? = nil,
        today: CalendarDay
    ) throws -> PlanDisplayData {
        guard let calendar else { return .notAuthored }

        // `PlanCalendar.versions` is non-empty and ascending by `effectiveFrom`, and
        // version number ascends with it (`PlanCalendar.init`'s own invariant), so the
        // last element is also the highest version. Asked for explicitly rather than
        // relying on that coupling, matching `PlanAuthoring.currentVersion(of:)`.
        guard let current = calendar.versions.max(by: { $0.version < $1.version }) else {
            return .notAuthored
        }

        let target: Plan
        if let version {
            guard let match = calendar.versions.first(where: { $0.version == version }) else {
                throw DomainError.inconsistent(
                    reason: "PlanDisplayData: version \(version) is not in the stored plan calendar"
                )
            }
            target = match
        } else {
            target = current
        }

        let history = try calendar.versions
            .sorted { $0.version > $1.version }
            .map { plan in
                VersionSummary(
                    version: plan.version,
                    effectiveFrom: plan.effectiveFrom,
                    effectiveThrough: try effectiveThrough(of: plan, in: calendar.versions),
                    isCurrent: plan.version == current.version,
                    isViewing: plan.version == target.version
                )
            }

        let detail = try versionDetail(
            for: target,
            isCurrent: target.version == current.version,
            calendar: calendar,
            today: today
        )

        return .authored(Authored(viewing: detail, history: history))
    }

    // MARK: - Building one version's detail

    private static func versionDetail(
        for plan: Plan,
        isCurrent: Bool,
        calendar: PlanCalendar,
        today: CalendarDay
    ) throws -> VersionDetail {
        let week = Weekday.allCases.sorted().map { weekday -> WeekdayRow in
            // The run slot only. Showing the lift slot beside it is MAX-138's ticket —
            // this file builds rows a screen renders, and a row nothing draws is a row
            // nobody checks.
            let session = plan.weeklyTemplate.session(on: weekday, for: .run)
            return WeekdayRow(
                weekday: weekday,
                kind: session.kind,
                distanceMeters: session.distanceMeters,
                note: session.note
            )
        }

        // Reuses `PlanCalendar.arcWeek(for:under:)` rather than re-deriving the
        // Monday-anchored week formula — one interpretation of "what week is it",
        // shared with the calendar resolution the scorer itself uses (D2/D3).
        let currentArcWeekIndex: Int? = isCurrent ? try calendar.arcWeek(for: today, under: plan) : nil

        let arc = plan.longRunArc.weeks.map { arcWeek in
            ArcWeekRow(
                index: arcWeek.index,
                distanceMeters: arcWeek.distanceMeters,
                isCurrentWeek: arcWeek.index == currentArcWeekIndex
            )
        }

        let bands = plan.rubric.bands.map { band in
            RubricBandRow(
                identifier: band.identifier,
                appliesTo: band.appliesTo,
                scoreRange: band.scoreRange,
                rationale: band.rationale
            )
        }

        return VersionDetail(
            version: plan.version,
            effectiveFrom: plan.effectiveFrom,
            effectiveThrough: try effectiveThrough(of: plan, in: calendar.versions),
            isCurrent: isCurrent,
            goalStatements: plan.goals.statements,
            goalTargetDay: plan.goals.targetDay,
            heartRateCapBPM: plan.heartRateCapBPM,
            cadenceTarget: plan.cadenceTarget,
            week: week,
            arc: arc,
            currentArcWeekIndex: currentArcWeekIndex,
            effectiveThreshold: plan.rubric.effectiveThreshold,
            marginalThreshold: plan.rubric.marginalThreshold,
            bands: bands
        )
    }

    /// The last day `plan` governed, or nil while it is the most recent version.
    ///
    /// - Parameter versions: every stored version, in any order — this looks the
    ///   successor up by version number rather than by position, so it does not depend
    ///   on the caller's ordering.
    private static func effectiveThrough(of plan: Plan, in versions: [Plan]) throws -> CalendarDay? {
        guard let successor = versions.first(where: { $0.version.number == plan.version.number + 1 }) else {
            return nil
        }
        return try successor.effectiveFrom.adding(days: -1)
    }
}

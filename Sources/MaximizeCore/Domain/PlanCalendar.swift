import Foundation

/// The set of plan versions, and the resolution of a calendar day to the plan that
/// governs it (MAX-011, PRD §8 `plan_day`, D1).
///
/// ## The guarantee this exists to provide
///
/// D1: *"Scoring reads the plan version in effect on the workout's date, so historical
/// scores stay reproducible."* Everything here serves that sentence. A workout scored
/// last month must resolve to the same plan, the same HR cap and the same rubric today
/// as it did then, no matter how many times the plan has been rewritten since.
///
/// ## Why the calendar is resolved rather than stored
///
/// PRD §8 describes `plan_day` as "materialized so scoring is deterministic", which in
/// a Postgres design means a table. On-device (amendment A1) the same determinism comes
/// from two properties instead, and they are stronger than a cache:
///
/// 1. Resolution is a **pure function** of the plan set and the date. Same inputs, same
///    answer, forever.
/// 2. The plan set **cannot gain a version that rewrites the past** — `init` rejects
///    any version whose `effectiveFrom` precedes an existing one (see below). A new
///    plan can only ever govern days after every plan already recorded.
///
/// Together those mean a stored table could never disagree with a fresh resolution, so
/// storing one would add a second source of truth with nothing to gain. `planDays(from:through:)`
/// materializes a range when a caller genuinely wants a list — the dashboard calendar
/// does — without making that list authoritative.
public struct PlanCalendar: Hashable, Sendable {
    /// Every plan version, ascending by `effectiveFrom`.
    public let versions: [Plan]

    /// - Throws: if the set could produce an ambiguous or history-rewriting answer.
    ///
    ///   Three rules, each closing a way D1 could be violated by data rather than by
    ///   code:
    ///
    ///   - **Non-empty.** A calendar with no plans has no opinion about any day, which
    ///     is a different thing from a plan that prescribes rest, and callers should
    ///     not have to distinguish them.
    ///   - **No two versions share an `effectiveFrom`.** Two plans starting the same
    ///     day is a coin flip, and a coin flip is not reproducible.
    ///   - **`version` ascends with `effectiveFrom`.** This is the one that protects
    ///     the past: a plan authored later must also *begin* later. Authoring version 3
    ///     with an `effectiveFrom` before version 2's would retroactively re-govern days
    ///     that have already been scored, and D8 makes those scores immutable — so the
    ///     stored score and a recomputation would disagree with no way to tell which is
    ///     right. Correcting an old plan is not a supported operation, and it should
    ///     fail loudly rather than quietly rewrite history.
    public init(_ plans: [Plan]) throws {
        guard !plans.isEmpty else {
            throw DomainError.empty(field: "PlanCalendar.versions")
        }

        let ordered = plans.sorted { $0.effectiveFrom < $1.effectiveFrom }
        for position in 1..<ordered.count {
            let earlier = ordered[position - 1]
            let later = ordered[position]

            guard later.effectiveFrom != earlier.effectiveFrom else {
                throw DomainError.duplicate(
                    field: "PlanCalendar.versions",
                    key: "effectiveFrom=\(later.effectiveFrom)"
                )
            }
            guard later.version > earlier.version else {
                throw DomainError.inconsistent(
                    reason: "PlanCalendar: version \(later.version) takes effect on "
                        + "\(later.effectiveFrom), after version \(earlier.version) on "
                        + "\(earlier.effectiveFrom), so it must be the higher version. "
                        + "A later plan that re-governs earlier days would rewrite "
                        + "already-scored history (D1/D8)."
                )
            }
        }

        self.versions = ordered
    }

    /// The plan governing `day`, or nil if `day` precedes every version.
    ///
    /// **Inclusive of `effectiveFrom`**: a workout on the day a plan takes effect is
    /// governed by that plan, not its predecessor. "Effective from the 1st" reads as
    /// including the 1st in every other context, and a boundary that behaved otherwise
    /// would be wrong exactly once per plan version — rarely enough to survive casual
    /// testing and land in production.
    ///
    /// Nil rather than the earliest plan for a day before any of them. A day the plan
    /// does not reach has no scheduled session, which is a real state (the athlete
    /// existed before the app did); answering with the first plan would invent an ask
    /// that was never made and could mark a pre-history day as *missed*.
    public func plan(on day: CalendarDay) -> Plan? {
        var governing: Plan?
        for plan in versions {
            guard plan.effectiveFrom <= day else { break }
            governing = plan
        }
        return governing
    }

    /// The resolved calendar entry for `day`, or nil if no plan governs it.
    public func planDay(on day: CalendarDay) throws -> PlanDay? {
        guard let plan = plan(on: day) else { return nil }
        return PlanDay(
            date: day,
            planVersion: plan.version,
            scheduledSession: try scheduledSession(on: day, under: plan)
        )
    }

    /// Every resolved entry from `start` through `end`, inclusive, ascending.
    ///
    /// Days no plan governs are **omitted** rather than represented as an empty entry:
    /// the dashboard calendar (D4/FR-3.2) needs to distinguish "the plan asked for
    /// nothing" from "the plan did not exist yet", and a `PlanDay` cannot express the
    /// second.
    public func planDays(from start: CalendarDay, through end: CalendarDay) throws -> [PlanDay] {
        try CalendarDay.days(from: start, through: end).compactMap { try planDay(on: $0) }
    }

    /// The 1-based arc week `day` falls in under `plan`, or nil if it precedes the plan.
    ///
    /// **Weeks are Monday-anchored**, counted from the Monday on or before the plan's
    /// `effectiveFrom` — not from `effectiveFrom` itself. The weekly template is written
    /// Monday-first (`Weekday` is ISO-8601 for that reason), so the athlete's training
    /// week begins on Monday. Counting arc weeks from an arbitrary start weekday would
    /// let a single template week straddle two arc weeks, and the long run prescribed
    /// for arc week 2 could land in what the athlete plainly experiences as week 1.
    ///
    /// The cost is that a plan starting mid-week has a short week 1. That is the honest
    /// representation: the athlete really does get a partial first week, and pretending
    /// otherwise would shift every subsequent week by a few days.
    public func arcWeek(for day: CalendarDay, under plan: Plan) throws -> Int? {
        try day.weekIndex(since: plan.effectiveFrom.startOfTrainingWeek())
    }

    /// The template's ask for the day, with a long run's distance taken from the arc.
    ///
    /// The weekly template says *which* days are long runs; the arc says *how far* in a
    /// given week. Only the distance is substituted — kind and note stay the template's.
    ///
    /// When the arc has no entry for the week, the template's own distance stands. The
    /// arc is a finite progression (D1's "16-week arc"), so running past its end is
    /// expected, and the alternatives are worse: clamping to the final week would have
    /// the code silently prescribe a peak long run indefinitely, which is a training
    /// decision this type has no standing to make. A plan whose arc has run out is a
    /// plan that wants a new version — which is exactly what D1 asks for.
    private func scheduledSession(on day: CalendarDay, under plan: Plan) throws -> ScheduledSession {
        let template = plan.weeklyTemplate.session(on: day)
        guard template.kind == .long,
              let week = try arcWeek(for: day, under: plan),
              let distanceMeters = plan.longRunArc.distanceMeters(forWeek: week)
        else {
            return template
        }
        return try ScheduledSession(
            kind: .long,
            distanceMeters: distanceMeters,
            note: template.note
        )
    }
}

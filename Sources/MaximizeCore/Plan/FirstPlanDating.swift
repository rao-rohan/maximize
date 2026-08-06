import Foundation

/// The days the athlete's already-captured workouts fall on, and what a candidate first
/// effective date would cost them (MAX-165, A23).
///
/// ## Why this type exists at all
///
/// Three correct behaviours combined into permanent, silent data loss. The ingester
/// backfills ninety days on its first successful pass (`AnchoredIngestionPolicy.standard`).
/// The authoring screen suggested the Monday of the current training week as a first
/// plan's effective date. And a workout on a day no plan governs is stored **without**
/// derived metrics and reported as `.workoutPredatesEveryPlan` — a reason that never
/// resolves, because MAX-011 forbids a later plan version from opening before an earlier
/// one. So an athlete who accepted the suggested date on the day they installed the app
/// permanently stranded almost everything its first minute had just captured, and nothing
/// on screen said how much.
///
/// The fix is not to let later versions reach backwards. It is to date the *first* plan
/// over the history that is already on the device, and — because the athlete may still
/// move the date — to state in figures what a given date leaves behind.
///
/// ## Days, not workouts
///
/// Plan coverage is day-scoped (`PlanCalendar.plan(on:)`), so the only fact about a stored
/// workout that bears on this question is which civil day it started on. Turning an
/// instant into a day needs a time zone and `MaximizeCore` does not get to pick one, so
/// the conversion happens once, at the edge, through `init(workouts:in:)` — after which
/// everything here is pure arithmetic on `CalendarDay`, testable on every commit.
///
/// ## Privacy
///
/// This carries dates, which are health data by association (CLAUDE.md), and it exists
/// only in memory on the way to a screen. Nothing derived from it is logged; the only
/// value that leaves is a count, and `PlanCopy.excludedWorkoutsNotice(count:)` is the one
/// place it becomes words.
public struct CapturedWorkoutHistory: Hashable, Sendable {

    /// One entry per stored workout, ascending. Repeats are meaningful — two runs on one
    /// day are two workouts a date can exclude — so this is a sorted list rather than a
    /// set of distinct days.
    public let days: [CalendarDay]

    public init(days: [CalendarDay]) {
        self.days = days.sorted()
    }

    /// The history as it stands in a store, resolved in the zone the caller supplies.
    ///
    /// - Parameter timeZone: the zone the workouts' days are resolved in. It should be
    ///   the same one `WorkoutIngestionPipeline` resolves a workout's day in, since a
    ///   disagreement between the two would put a workout on one side of the boundary
    ///   here and the other side there.
    public init(workouts: [Workout], in timeZone: TimeZone) throws {
        self.init(days: try workouts.map { try $0.calendarDay(in: timeZone) })
    }

    /// Nothing captured. Also the honest answer for a caller that has not asked the
    /// store — a session built without a history suggests exactly what it suggested
    /// before this ticket, rather than pretending to know something it does not.
    public static let empty = CapturedWorkoutHistory(days: [])

    public var isEmpty: Bool { days.isEmpty }

    /// How many workouts are captured in total.
    public var count: Int { days.count }

    /// The day of the earliest stored workout, or nil when nothing is stored.
    ///
    /// "Earliest stored", not "earliest run": a workout older than the backfill window
    /// was never fetched, so it is not here and no effective date can reach it. Dating a
    /// plan before this day covers everything the device actually holds, which is all a
    /// plan can do.
    public var earliestDay: CalendarDay? { days.first }

    /// How many captured workouts a plan taking effect on `day` would leave outside every
    /// plan version, permanently.
    ///
    /// **Inclusive of `day` itself**, matching `PlanCalendar.plan(on:)`: a workout on the
    /// day a plan takes effect is governed by it and is therefore not excluded. The
    /// boundary is worth stating because it is wrong exactly once per athlete, and the
    /// number this produces is the one they will make a decision on.
    public func workoutsExcluded(byEffectiveFrom day: CalendarDay) -> Int {
        days.reduce(into: 0) { total, workoutDay in
            if workoutDay < day { total += 1 }
        }
    }
}

/// Where a first plan should be offered to start (A23).
///
/// Separate from `PlanAuthoringSession` because it is one decision with one input pair,
/// and separating it is what lets it be asserted directly rather than through a whole
/// session. `PlanAuthoring.session(revising:today:capturedHistory:)` is its only
/// production caller.
public enum FirstPlanDating {

    /// The day a first plan should be offered to take effect on.
    ///
    /// **The earlier of the earliest captured workout's day and the Monday of the current
    /// training week.** Each half of that carries its own reason:
    ///
    /// - *The earliest captured workout's day* is A23: it is the only date that brings
    ///   the whole of the backfill under a plan, and a first plan is the only version
    ///   ever permitted to reach backwards.
    /// - *The current training week's Monday* was the previous suggestion, and it is kept
    ///   as a ceiling so the arc and the weekly template still line up on a Monday for an
    ///   athlete whose history all falls inside this week — the reason `startOfTrainingWeek`
    ///   was chosen in the first place. Taking the minimum means the suggestion **can
    ///   never be later than what the screen offered before this ticket**, so it can only
    ///   ever exclude fewer workouts, never more.
    ///
    /// With no history at all, that minimum is just the training week's Monday: the
    /// fallback A23 names, unchanged, and the right answer for an athlete whose device has
    /// nothing on it yet — there is nothing to cover, and a plan dated arbitrarily far back
    /// would claim to govern days it has no business claiming.
    ///
    /// ## Is a plan dated before the athlete's real training start harmful?
    ///
    /// No, and the asymmetry is the point. A plan governs *days*; a day before they
    /// trained is a day with no workout on it. It acquires no score, enters no tally that
    /// counts sessions, and produces no obligation anybody sees — `PlanCalendar` will
    /// happily answer "easy 8 km" for a Tuesday in the athlete's past, and nothing asks
    /// it. The cost of dating too early is a hypothetical answer nobody requests; the cost
    /// of dating too late is a workout that can never be measured. Those are not
    /// comparable, and the suggestion should err in the direction that is recoverable.
    public static func suggestedEffectiveFrom(
        covering history: CapturedWorkoutHistory,
        today: CalendarDay
    ) throws -> CalendarDay {
        let trainingWeekStart = try today.startOfTrainingWeek()
        guard let earliest = history.earliestDay else { return trainingWeekStart }
        return min(earliest, trainingWeekStart)
    }
}

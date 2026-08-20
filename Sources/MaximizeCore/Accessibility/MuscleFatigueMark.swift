import Foundation

/// The muscle map's non-colour channel (MAX-180) — for the same reason `ScoreBandMark`
/// (MAX-084) and `ScoreBandHeatmapMark` (MAX-087) exist: a figure distinguished only by
/// hue is invisible to a meaningful fraction of people, and this codebase has already
/// shipped that defect once, at 1.02:1, and found it. `WCAGContrastTests` is where that
/// invariant is enforced for every drawn surface, this one included — see the widened
/// `testNoTwoCalendarCellsAreDistinguishedByHueAlone` there rather than a parallel file.
///
/// ## Five bands, from three reading cases
///
/// `MuscleFatigueReading` carries three cases, and two of them — `.neverLogged` and
/// `.fresh` — are already different facts about the athlete (see `MuscleFatigue`'s own
/// doc comment): `.neverLogged` is a *designed absence*, the app does not know whether
/// this group is trained at all; `.fresh` is a *judgement*, made from a real record,
/// that recovery has run its course. Collapsing either into "no fatigue" would draw a
/// false rest state on top of missing data — precisely the failure MAX-180 was
/// dispatched to avoid, and precisely the failure a cold/rested colour would repeat
/// silently. So they stay two separate bands here, never one.
///
/// `.fatigued`'s continuous `0...1` fraction is additionally split into three tiers —
/// `light`, `moderate`, `high` — purely so six regions can be compared at a glance;
/// `MuscleFatigue.fraction` still carries the exact number for anything that wants it,
/// starting with the per-group detail sentence `MuscleFatigueCopy.detail(for:)` already
/// writes. Splitting into thirds rather than reaching for a named physiological
/// threshold is deliberate: `MuscleFatigueModel`'s own documentation is explicit that
/// this figure is "a recency signal, not a physiological one" and "has roughly one bit
/// of real information" — three equal tiers claim no more precision than that.
///
/// ## Why fill fraction, and not hue, carries the level
///
/// Every mark below is drawn in one neutral ink regardless of band —
/// `App/Workouts/MuscleMapView.swift` uses `Color.chartSeriesPrimary` on
/// `Color.surfaceInset`, tokens already measured against each other in
/// `WCAGContrastTests`'s chart hierarchy. The three saturated score-band hues are
/// reserved for the calendar and verdict header by FR-4.3 (`ScoreBandColors.swift`
/// says so directly: "not a general-purpose status palette"), and reaching for the
/// accent would collide with *its* reserved meaning too — "on-plan / effective", which
/// six-days-fatigued is neither. So this channel carries the level on its own: how much
/// of a region's shape is filled, plus whether its outline is solid or dashed. A test
/// can hold two marks at 1.0:1 (literally the same ink) and still require them to be
/// told apart, which is a stronger guarantee than any hue difference could give —
/// nothing here relies on a viewer's colour vision at all.
///
/// This also satisfies MAX-070's Reduce Transparency / Increase Contrast rule for
/// free: `fillFraction` and `outlineIsDashed` are geometry, not opacity or lightness,
/// so neither accessibility setting has anything to weaken or override. A channel
/// built from opacity would not survive that test; this one was chosen so the question
/// does not come up.
///
/// `.notLogged` additionally carries a glyph (`hasGlyph`). A dashed outline at zero
/// fill and a solid outline at zero fill (`.fresh`) already read apart on their own,
/// but the glyph is what keeps "never logged" from being misread at a glance as
/// "logged, and empty" — the fill-density channel's own version of the failure this
/// file exists to prevent, closed the same way `ScoreBandMarkView`'s reserved footprint
/// closes it for `.unmarked`.
public enum MuscleFatigueBand: String, Hashable, Sendable, CaseIterable {

    /// No session has ever named this group (MAX-179's `.neverLogged`). Not a fatigue
    /// level — there is no figure to place on a scale. See the type's doc comment.
    case notLogged

    /// Logged, but the curve has run past `MuscleFatigueModel.negligibleDecay`.
    case fresh

    /// The bottom third of `MuscleFatigue.fraction` among fatigued readings.
    case light

    /// The middle third.
    case moderate

    /// The top third.
    case high

    /// MAX-179's continuous banding, done once, here — so no caller compares a
    /// fraction to a literal threshold of its own.
    public static func of(_ reading: MuscleFatigueReading) -> MuscleFatigueBand {
        switch reading {
        case .neverLogged:
            return .notLogged
        case .fresh:
            return .fresh
        case let .fatigued(fatigue):
            switch fatigue.fraction {
            case ..<(1.0 / 3.0):
                return .light
            case ..<(2.0 / 3.0):
                return .moderate
            default:
                return .high
            }
        }
    }
}

/// One band's complete presentation — the bundle `MuscleMapView` reads instead of
/// branching on `MuscleFatigueBand` itself, matching the division of labour
/// `ScoreBandMarkView` already draws on `ScoreBand.mark`: everything about *which* mark
/// a band gets is decided here, in `MaximizeCore`, where CI can see it; the view only
/// knows how to draw a fraction of a shape, a dash pattern, and a glyph.
public struct MuscleFatigueMark: Hashable, Sendable {

    public let band: MuscleFatigueBand

    /// The word drawn under the region and read by VoiceOver alongside the group name.
    public let label: String

    /// `true` only for `.notLogged` — the first half of the "you don't know this / you
    /// do" distinction the type's doc comment argues for.
    public let outlineIsDashed: Bool

    /// `0...1`. How much of the region's own shape is filled — the channel that
    /// actually carries the band, independent of any colour. `.notLogged` and `.fresh`
    /// both draw `0`; see `hasGlyph` for how they still stay apart.
    public let fillFraction: Double

    /// `true` only for `.notLogged`. A mark inside the outline that no logged reading
    /// ever draws, so an empty *known* group cannot be misread as an empty *unknown*
    /// one — see the type's doc comment.
    public let hasGlyph: Bool

    public init(
        band: MuscleFatigueBand,
        label: String,
        outlineIsDashed: Bool,
        fillFraction: Double,
        hasGlyph: Bool
    ) {
        self.band = band
        self.label = label
        self.outlineIsDashed = outlineIsDashed
        self.fillFraction = fillFraction
        self.hasGlyph = hasGlyph
    }

    /// The whole mapping, in one call: a reading in, everything a surface needs to
    /// draw it out. `MuscleMapView` calls this once per group and never branches on
    /// `MuscleFatigueReading` itself.
    public static func mark(for reading: MuscleFatigueReading) -> MuscleFatigueMark {
        let band = MuscleFatigueBand.of(reading)
        return MuscleFatigueMark(
            band: band,
            label: labelText(for: band),
            outlineIsDashed: band == .notLogged,
            fillFraction: fillAmount(for: band),
            hasGlyph: band == .notLogged
        )
    }

    private static func labelText(for band: MuscleFatigueBand) -> String {
        switch band {
        case .notLogged: return "Not logged"
        case .fresh: return "Fresh"
        case .light: return "Light"
        case .moderate: return "Moderate"
        case .high: return "High"
        }
    }

    /// Equal thirds, mirroring `MuscleFatigueBand.of(_:)`'s own thresholds — the two
    /// are pinned against each other in `MuscleFatigueMarkTests` so they cannot drift.
    private static func fillAmount(for band: MuscleFatigueBand) -> Double {
        switch band {
        case .notLogged, .fresh: return 0
        case .light: return 1.0 / 3.0
        case .moderate: return 2.0 / 3.0
        case .high: return 1.0
        }
    }
}

/// The "last worked" caption `MuscleMapView` draws beside a logged region — the
/// calendar-correct replacement for `MuscleFatigue.elapsedDays`, which #173 removed.
///
/// ## Why this exists, and why it is not interval arithmetic
///
/// `elapsedDays` counted fixed 86,400-second blocks from `now`, so a session ending
/// Sunday at 22:00 read as "0 days ago" at Monday 08:00 — ten hours after it ended, but
/// also the next calendar day, which is the fact an athlete actually means by "since
/// yesterday". Whole days are a *calendar* question, not an interval one, and answering
/// it needs the athlete's time zone, which `MuscleFatigue` deliberately does not carry
/// (see its own doc comment on `elapsedDays`'s removal). `ChatThreadListPresentation
/// .compactTimestamp` already solved the identical problem for a chat thread's
/// timestamp, by turning both instants into a `CalendarDay` in the athlete's zone and
/// calling `CalendarDay.days(until:)`; this is the same pattern, applied here rather
/// than invented twice.
///
/// ## Which instant it reads
///
/// `MuscleFatigue.mostRecentlyWorkedAt`, never `sessionEndedAt`. The two differ exactly
/// when a lighter, later session is outweighed by an earlier heavier one governing the
/// figure (`MuscleFatigueCalculator`'s "whichever reads highest" rule) — and a caption
/// built from `sessionEndedAt` in that case would name the wrong day: the athlete
/// *did* work the group more recently than the session the figure came from, and a
/// screen saying otherwise would be a false sentence, which is exactly what
/// `MuscleFatigue`'s own doc comment warns against.
public enum MuscleFatigueLastWorkedCaption {

    /// `compact` is the short on-screen fragment ("3d ago"); `sentence` is the fuller
    /// form the region's accessibility label reads. Built from the same whole-day
    /// count, computed once, so the two can never disagree about how long ago
    /// something was — the same reason `MuscleFatigueMark` bundles a band's label and
    /// its non-hue channel into one value rather than two call sites recomputing each.
    public struct Caption: Hashable, Sendable {
        public let compact: String
        public let sentence: String
    }

    /// - Parameters:
    ///   - mostRecentlyWorkedAt: `MuscleFatigue.mostRecentlyWorkedAt` — see the type's
    ///     doc comment on why this and not `sessionEndedAt`.
    ///   - now: the instant to caption *from*. Pass `MuscleFatigueMap.computedAt`
    ///     rather than a freshly read clock, so the caption's notion of "today" agrees
    ///     with the fatigue figure drawn beside it — two clock reads a render pass
    ///     apart could disagree right at midnight.
    ///   - timeZone: the athlete's zone. A session that ended at 22:00 Sunday is
    ///     "yesterday" by 08:00 Monday only in the zone the athlete was living in;
    ///     `.current` is the honest default for a single-device app (A1).
    ///
    /// `nil` only if `CalendarDay` cannot resolve one of the two instants — a
    /// pre-Gregorian or post-9999 date, unreachable for a real workout record. A
    /// caller that gets `nil` has nothing false to say and should draw nothing rather
    /// than guess.
    public static func text(
        mostRecentlyWorkedAt: Date,
        now: Date,
        timeZone: TimeZone
    ) -> Caption? {
        guard
            let today = try? CalendarDay(now, in: timeZone),
            let workedDay = try? CalendarDay(mostRecentlyWorkedAt, in: timeZone),
            let elapsed = try? workedDay.days(until: today)
        else {
            return nil
        }
        // A future-dated stamp — clock or zone skew — reads as "today" rather than a
        // negative day count, the same clamp-the-arithmetic-not-the-record discipline
        // `MuscleFatigueCalculator.elapsedSeconds(since:now:)` already applies to the
        // instant this is built from.
        let days = max(0, elapsed)
        switch days {
        case 0:
            return Caption(compact: "today", sentence: "Last worked today.")
        case 1:
            return Caption(compact: "yesterday", sentence: "Last worked yesterday.")
        default:
            return Caption(compact: "\(days)d ago", sentence: "Last worked \(days) days ago.")
        }
    }
}

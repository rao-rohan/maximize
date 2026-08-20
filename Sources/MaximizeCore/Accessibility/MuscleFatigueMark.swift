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

    /// Logged, but the curve has run past `MuscleFatigueModel.negligibleFraction`.
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

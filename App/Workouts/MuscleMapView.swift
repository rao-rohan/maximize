import SwiftUI
import MaximizeCore

/// The six-region muscle map (MAX-180) — draws `MuscleFatigueMap`, MAX-179's per-group
/// decay model over the entries A22 already collects.
///
/// ## What this view decides: nothing
///
/// Every fact drawn here — which band a group is in, its label, and its non-colour
/// channel — is `MaximizeCore.MuscleFatigueMark`'s decision, which is where MAX-180's
/// real content lives. This file only turns one `MuscleFatigueMark` into a shape: a
/// fraction of a region filled bottom-up, a dashed or solid outline, a glyph. It never
/// compares a fraction to a threshold of its own, and every group flows through
/// `MuscleFatigueMark.mark(for:)` before this view touches it — there is no second
/// place in the app that decides what "moderately fatigued" means.
///
/// ## No glass over data (FR-4.2)
///
/// `.contentSurface(.card)` — flat and opaque, the same surface every other section on
/// this screen uses. Liquid Glass belongs on chrome — bars, sheets, floating controls
/// (MAX-040) — and a muscle map is data, not chrome.
///
/// ## Two absences, not one
///
/// `MuscleFatigueMap.hasNoLoggedSessions` is the map's own state: nothing has ever been
/// logged, and the screen says one sentence rather than drawing six regions that would
/// all say the same "not logged" thing (`MuscleFatigueCopy.noSessionsHeadline` /
/// `.noSessionsDetail` — MAX-179's own precedent for collapsing six identical absences
/// into one). A single group with no session, among others that do have one, is a
/// *different* absence: it still draws, dashed and glyphed rather than filled, because
/// the reader is looking at a map of six groups and a region that silently disappeared
/// would read as "nothing to say" rather than "unknown" — the same failure a cold/
/// rested fill would be. See `MuscleFatigueMark`'s own doc comment.
///
/// ## The caption
///
/// `MuscleFatigueCopy.modelCaption` is drawn every time the figure is, in the same
/// voice as every other absence string on this screen: A20's tripwire means there is no
/// set, rep or load behind any of these six numbers, and A22 means the map only knows
/// what the athlete typed. The caption says both, plainly, rather than letting a
/// confident-looking diagram imply a precision the record does not have.
///
/// ## "Last worked", calendar-correct
///
/// Each logged region also draws when it was last worked (`MuscleFatigueLastWorked-
/// Caption`, MAX-180 adapting to #173's removal of `MuscleFatigue.elapsedDays`): a
/// whole-day count built from `CalendarDay.days(until:)` in the athlete's zone, the
/// same pattern `ChatThreadListPresentation.compactTimestamp` already uses for a chat
/// thread's timestamp — never a fixed 86,400-second block, which misreports a session
/// that ended late one night as "today" the next morning. This view supplies the two
/// inputs the core function needs (`map.computedAt` for "now", `timeZone` for which
/// calendar the days are counted in) and draws what it returns; it does no date
/// arithmetic of its own.
struct MuscleMapView: View {
    let map: MuscleFatigueMap

    /// The athlete's zone, for the "last worked" caption's day count
    /// (`MuscleFatigueLastWorkedCaption`). `.current` is the honest default for a
    /// single-device app (A1) — the same default `WorkoutDetailModel.timeZone` already
    /// uses for every other calendar-day computation on this screen.
    var timeZone: TimeZone = .current

    @ScaledMetric(relativeTo: .body) private var regionSize: CGFloat = LayoutMetrics.muscleMapRegionSize

    /// Three regions share the middle row at the type sizes most people read at; at
    /// an accessibility size `@ScaledMetric` can grow `regionSize` past what three of
    /// them fit side by side on the narrowest supported phone, so that row switches to
    /// stacking vertically instead — `ChatComposerView` reads this same environment
    /// value for the equivalent reason.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.compact) {
            Text(MuscleFatigueCopy.sectionTitle)
                .font(.sectionHeading)
                .foregroundStyle(Color.textPrimary)

            if map.hasNoLoggedSessions {
                noSessions
            } else {
                figure
                Text(MuscleFatigueCopy.modelCaption)
                    .font(.metricLabel)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .contentSurface(.card)
    }

    // MARK: - The map's own absence (MAX-179's `hasNoLoggedSessions`)

    private var noSessions: some View {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            Text(MuscleFatigueCopy.noSessionsHeadline)
                .font(.metricSecondary)
                .foregroundStyle(Color.textPrimary)
            Text(MuscleFatigueCopy.noSessionsDetail)
                .font(.metricLabel)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - The figure

    /// A schematic layout, not an anatomical illustration: shoulders across the top,
    /// arms flanking the chest and back in the row below, core and legs stacked under
    /// that. Six labelled regions positioned the way a training split is usually
    /// talked about, laid out with ordinary stacks so nothing overlaps or clips as
    /// Dynamic Type grows — a freeform body outline would have to be redrawn by hand
    /// at every text size to make the same promise.
    private var figure: some View {
        VStack(spacing: Spacing.compact) {
            region(.shoulders)
            middleRow
            region(.core)
            region(.legs)
        }
    }

    /// Three regions wide at ordinary Dynamic Type sizes; stacked at an accessibility
    /// size, where `regionSize` alone can exceed a phone's width three times over. See
    /// the property comment on `dynamicTypeSize` above.
    @ViewBuilder
    private var middleRow: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: Spacing.compact) {
                region(.arms)
                region(.chest)
                region(.back)
            }
        } else {
            HStack(spacing: Spacing.compact) {
                region(.arms)
                region(.chest)
                region(.back)
            }
        }
    }

    private func region(_ group: MuscleGroup) -> some View {
        let reading = map[group]
        let mark = MuscleFatigueMark.mark(for: reading)
        let lastWorked = lastWorkedCaption(for: reading)
        return VStack(spacing: Spacing.tight) {
            MuscleFatigueRegionMarkView(mark: mark, diameter: regionSize)
            Text(group.displayName)
                .font(.metricLabel)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(mark.label)
                .font(.microLabel)
                .foregroundStyle(Color.textSecondary)
            // The numeral CLAUDE.md's UI standard asks for, on the two bands that
            // have one — `reading.fatigue` is nil only for `.neverLogged`, and
            // `mark.label` already carries the whole story for that one on its own.
            if let lastWorked {
                Text(lastWorked.compact)
                    .font(.microLabel)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(group: group, reading: reading, mark: mark, lastWorked: lastWorked))
    }

    /// `MuscleFatigueLastWorkedCaption` reads `mostRecentlyWorkedAt`, never
    /// `sessionEndedAt` — see that type's doc comment on why naming the governing
    /// session instead would be a false sentence on a session #173 outweighed but did
    /// not erase. `map.computedAt` stands in for "now" so this caption's notion of
    /// today can never disagree with the fatigue figure drawn beside it.
    private func lastWorkedCaption(for reading: MuscleFatigueReading) -> MuscleFatigueLastWorkedCaption.Caption? {
        guard let fatigue = reading.fatigue else { return nil }
        return MuscleFatigueLastWorkedCaption.text(
            mostRecentlyWorkedAt: fatigue.mostRecentlyWorkedAt,
            now: map.computedAt,
            timeZone: timeZone
        )
    }

    private func accessibilityLabel(
        group: MuscleGroup,
        reading: MuscleFatigueReading,
        mark: MuscleFatigueMark,
        lastWorked: MuscleFatigueLastWorkedCaption.Caption?
    ) -> String {
        var label = "\(group.displayName): \(mark.label). \(MuscleFatigueCopy.detail(for: reading))"
        if let lastWorked {
            label += " \(lastWorked.sentence)"
        }
        return label
    }
}

/// Draws one `MuscleFatigueMark` — the region's shape, its fill fraction, and its
/// outline. Everything about *which* mark a band gets is decided in `MaximizeCore`;
/// this view only knows how to fill a rounded rectangle from the bottom and stroke it
/// solid or dashed, the same division of labour `ScoreBandMarkView` draws on
/// `ScoreBand.mark`.
///
/// ## The two channels
///
/// - **Fill fraction** — geometry, not opacity or lightness, so Reduce Transparency
///   and Increase Contrast have nothing to weaken or strengthen here: there is no
///   translucency in this view to degrade in the first place (MAX-070). The fill and
///   the track are both fully opaque tokens; only the *area* changes.
/// - **Outline style** — solid for every logged reading, dashed only for
///   `.notLogged`, doubled by a glyph so an empty *known* group cannot be misread as
///   an empty *unknown* one.
///
/// Both survive greyscale and every kind of colour vision, because neither is a
/// colour value: `WCAGContrastTests` holds `.light`/`.moderate`/`.high` at the same
/// ink (`chartSeriesPrimary`) and `.notLogged`/`.fresh` at the same ink
/// (`surfaceInset`), and still requires every band to read apart.
private struct MuscleFatigueRegionMarkView: View {
    let mark: MuscleFatigueMark
    let diameter: CGFloat

    @ScaledMetric(relativeTo: .body) private var outlineWidth: CGFloat = LayoutMetrics.muscleMapOutlineWidth

    var body: some View {
        ZStack {
            Color.surfaceInset
            if mark.fillFraction > 0 {
                Color.chartSeriesPrimary
                    .frame(height: diameter * mark.fillFraction)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            if mark.hasGlyph {
                Image(systemName: "questionmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.tile, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.tile, style: .continuous)
                .strokeBorder(Color.surfaceBorder, style: outlineStyle)
        )
        // The region's meaning is spoken in full by the parent's combined
        // accessibility label (group, band, and detail sentence) — this is the
        // channel for people who are looking, not listening, the same split
        // `ScoreBandMarkView` draws.
        .accessibilityHidden(true)
    }

    private var outlineStyle: StrokeStyle {
        guard mark.outlineIsDashed else {
            return StrokeStyle(lineWidth: outlineWidth)
        }
        return StrokeStyle(
            lineWidth: outlineWidth,
            dash: [
                outlineWidth * LayoutMetrics.muscleMapDashLengthMultiplier,
                outlineWidth * LayoutMetrics.muscleMapDashGapMultiplier,
            ]
        )
    }
}

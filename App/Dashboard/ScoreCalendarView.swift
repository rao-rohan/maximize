import SwiftUI
import MaximizeCore

/// FR-3.2 / D4 / D9 / A6: the score-colored calendar for the dashboard's selected
/// interval, in whichever arrangement that span calls for.
///
/// ## What this view does and does not decide
///
/// Every day's state — scored (and which band), awaiting a score, missed, converted
/// to rest, scheduled rest, or ungoverned by any plan — is decided by
/// `MaximizeCore.ScoreCalendar`. *Where each day goes* — grid padding, week columns,
/// which column earns a month tick — is decided by `MaximizeCore.ScoreCalendarLayout`.
/// *Which arrangement a span gets* is decided by
/// `TrendIntervalKind.scoreCalendarRepresentation`. All three are unit tested. This
/// view's only job is turning what it is handed into cells: a fill, a glyph, and an
/// accessibility sentence, all sourced from `ScoreCalendarFormatting` or the design
/// system's own tokens (`Color.scoreBand(_:)`, `ScoreBandColors.swift`) — never a
/// literal.
///
/// ## Two arrangements (MAX-083)
///
/// - **Week and month** draw the day grid MAX-061 shipped: seven columns of dated cells,
///   each carrying its date and its state glyph.
/// - **A year** draws a heatmap: seven weekday rows by ~53 training-week columns, one
///   small mark per day. A year in the day grid would be 53 rows tall — several screens
///   of scrolling for a surface §7.4 wants taken in at a glance.
///
/// See `ScoreCalendarRepresentation` for the full argument, including why the rows are
/// weekdays rather than months and what the density costs.
///
/// ## Channels other than hue
///
/// Three channels carry state independently of hue in the day grid, so a colour-blind
/// athlete reads the same calendar a sighted one does:
///
/// 1. **A `.missed` day and a `.scored(.ineffective, _)` day share the same red
///    fill** (D9 says a miss "shows red"; the rubric's own "skipped → 0–15" band
///    lands in the same score range .ineffective already covers), **but never the
///    same glyph** — an activity icon for a bad run, a dedicated "×" for a day
///    nothing happened. Shape alone tells the two apart in grayscale.
/// 2. **A scored day carries `ScoreBand.mark` in its corner** — a dot for effective,
///    a ring for marginal, nothing for ineffective (`ScoreBandMarkView`). This
///    channel exists because the state glyph does *not* cover the bands: it encodes
///    the activity, so an effective run and a marginal run of the same type get the
///    same glyph, and their two fills measure **1.02:1** against each other in dark
///    (1.04:1 in light). Until MAX-084 this view's doc comment claimed a guarantee it
///    did not have, and green-versus-orange is the exact pair colour-blindness
///    collapses. See `ScoreBandMark` for the full measurement.
/// 3. **Every cell carries a full-sentence VoiceOver label**
///    (`ScoreCalendarFormatting.accessibilityLabel`), not just a glyph name — the
///    channel that does not depend on shape recognition at all.
///
/// Channel 2 is MAX-084 closing what MAX-083 recorded here as still open. Before it, the
/// first and third channels covered `.missed` versus `.ineffective` and left `.effective`
/// versus `.marginal` on hue alone, at 1.02:1 — the same square in greyscale, on the exact
/// hue axis deuteranopia collapses.
///
/// **The year heatmap had that same gap, and a corner pip cannot fix it.** A heatmap
/// mark is about six points square with a ~1.5pt gap to its neighbour; there is no corner
/// left to put a pip in once the mark itself is that small — the case MAX-083 predicted
/// would test T6, and it failed it. MAX-087 closes it with a different channel: a
/// scored day's fill draws smaller than the mark's full footprint, centred, with the
/// size set by `ScoreBandHeatmapMark` (`ScoreBand.heatmapMark`) — geometry rather than
/// colour, so it survives greyscale, every kind of colour vision, and Increase Contrast
/// / Reduce Transparency alike, since there is no colour value in it for either setting
/// to touch. A missed day keeps drawing hollow
/// (`ScoreCalendarDayState.isDrawnHollowAtHeatmapDensity`), unrelated and unchanged, and
/// the VoiceOver sentence — dated with its month since nothing on screen says which day
/// it is — still carries the rest. **Needs device verification**: whether a ~2.4pt inset
/// square actually reads as "smaller" rather than as noise is exactly the judgement
/// nobody building this ticket could make; see the MAX-087 PR.
///
/// `.scheduledRest` and `.convertedRest` sit on the same neutral fill as
/// `.awaitingScore` and `.unplanned` (`ScoreBandColors.swift`'s own doc comment: a
/// day with no verdict is not a fourth saturated band) but each still gets its own
/// glyph and its own sentence, so "the plan asked for rest" and "a miss was forgiven"
/// never read as the same fact even though neither is a judgment.
///
/// ## The plan layer (MAX-105)
///
/// Everything above describes what *happened*. The plan is what was *prescribed*, and
/// until this ticket it was visible only where nothing happened — `.missed`,
/// `.convertedRest`, `.scheduledRest` are all plan statements, but a day the athlete
/// actually ran said nothing about whether the run was asked for.
///
/// **The prescription is the ground; the outcome is the figure drawn on it.** A cell the
/// plan asks a session of is ringed at its own edge (`Color.accent`, the token reserved
/// for the on-plan state), and its state fill is inset inside that ring. A cell the plan
/// asks nothing of has no ring. That is the entire channel — one bit, no legend beyond
/// "the plan asked for something here" — and it reads:
///
/// - **ring + band fill** — you trained on a day you were asked to. Agreement.
/// - **ring + red and a ×** — you were asked and did not. Divergence, loudly.
/// - **ring + nothing inside** — `.forthcoming`: asked, not yet due. A slot with your
///   name on it (`ScoreCalendarDayState.isDrawnUnfilledInTheDayGrid`).
/// - **no ring + band fill** — you trained on a rest day or off-plan. Divergence the
///   other way, and the one the athlete would otherwise never see.
///
/// Two properties of that choice are load-bearing:
///
/// 1. **It costs nothing from the band contrast budget.** The ring never distinguishes
///    one band from another and never sits on a band fill — the gutter keeps it on the
///    calendar card, where a single measured pairing (`accent` on `surfaceElevated`,
///    5.89:1 dark / 5.81:1 light) is all it has to survive. MAX-084 closed hue-only
///    band encoding and MAX-087 spent mark *size* closing it at year density; neither is
///    touched here.
/// 2. **Presence, not hue, is the signal.** A reader who cannot see violet still sees a
///    stroke where there was none. Under Increase Contrast the token brightens and the
///    stroke thickens (`LayoutMetrics.planRingWidthIncreasedContrast`); under Reduce
///    Transparency nothing changes, because there is no translucency in it to remove.
///
/// **What the ring deliberately does not encode** is *which* session was prescribed, or
/// whether the session performed was the kind asked for. Both are known — the core
/// resolves `ScoreCalendarDay.prescription` and `.agreement` — and both are spoken in
/// full by VoiceOver. Neither is drawn, because a 42pt cell already carries a fill, a
/// glyph and a band pip, and a fourth visual distinction inside it is the cell that needs
/// a legend. Kind-level divergence has a home with room for it: the workout detail's
/// verdict header, which shows scheduled against actual for the day you tapped.
///
/// The year heatmap has no plan layer at all;
/// `ScoreCalendarRepresentation.drawsThePlanLayer` carries that decision and its
/// argument. `.forthcoming` still applies there — it is drawn as an ordinary neutral
/// mark, never as the hollow outline `.missed` uses.
struct ScoreCalendarView: View {
    let interval: TrendInterval

    @State private var model = ScoreCalendarModel()

    private let weekdaySymbols = ["M", "T", "W", "T", "F", "S", "S"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: Spacing.tight), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.compact) {
            Text("Calendar")
                .font(.sectionHeading)
                .foregroundStyle(Color.textPrimary)

            switch model.state {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.roomy)
            case .failed:
                Text("Couldn't load the calendar.")
                    .font(.metricLabel)
                    .foregroundStyle(Color.textSecondary)
            case .loaded(.dayGrid(let grid)):
                dayGrid(grid)
            case .loaded(.weekColumns(let heatmap)):
                heatmapGrid(heatmap)
            }
        }
        .contentSurface(.card)
        .task(id: interval) {
            await model.load(for: interval)
        }
    }

    // MARK: - Week and month: the dated day grid

    private func dayGrid(_ grid: ScoreCalendarDayGrid) -> some View {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            weekdayHeader
            LazyVGrid(columns: columns, spacing: Spacing.tight) {
                // Leading blanks so the first real day lands under its own weekday
                // column — a month rarely starts on a Monday. The count is
                // `ScoreCalendarDayGrid`'s, computed and tested in the core.
                ForEach(0..<grid.leadingBlankCount, id: \.self) { _ in
                    Color.clear
                }
                ForEach(grid.days) { day in
                    ScoreCalendarDayCell(day: day)
                }
            }
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: Spacing.tight) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.microLabel)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Year: the weekday × week heatmap

    /// One column per training week, seven rows of marks, with month ticks above.
    ///
    /// The columns share the width equally (`maxWidth: .infinity`) and each mark is
    /// squared off its own column width via `aspectRatio` — the same technique
    /// `ScoreCalendarDayCell` uses, and for the same reason: a mark's size must depend on
    /// the space available, never on what is drawn inside it, or a year's rows come out
    /// ragged wherever the athlete's history is.
    private func heatmapGrid(_ heatmap: ScoreCalendarHeatmap) -> some View {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            monthTicks(heatmap)
            HStack(alignment: .top, spacing: LayoutMetrics.heatmapCellSpacing) {
                ForEach(heatmap.columns) { column in
                    VStack(spacing: LayoutMetrics.heatmapCellSpacing) {
                        ForEach(Array(column.days.enumerated()), id: \.offset) { _, day in
                            ScoreCalendarHeatmapCell(day: day)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    /// Month names above the columns that open each month.
    ///
    /// Each tick sits in a zero-width frame inside its own column slot so it can overflow
    /// to the right without widening the column — a three-letter name is wider than the
    /// ~6pt column it labels, and letting it push would misalign every column after it
    /// from the marks below.
    private func monthTicks(_ heatmap: ScoreCalendarHeatmap) -> some View {
        HStack(alignment: .bottom, spacing: LayoutMetrics.heatmapCellSpacing) {
            ForEach(heatmap.columns) { column in
                Group {
                    if let monthStart = column.monthStart {
                        Text(TrendIntervalFormatting.shortMonthName(for: monthStart))
                            .font(.microLabel)
                            .foregroundStyle(Color.textTertiary)
                            .lineLimit(1)
                            .fixedSize()
                            .frame(width: 0, alignment: .leading)
                    } else {
                        Color.clear.frame(height: 0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityHidden(true)
    }
}

/// One calendar cell in the dated day grid. Its fill and glyph are read from
/// `day.state`, its ring from `day.prescribesASession`; nothing here branches on a
/// threshold, a raw score, or a date comparison — `MaximizeCore.ScoreCalendar` decided
/// all three before this view saw the day.
private struct ScoreCalendarDayCell: View {
    let day: ScoreCalendarDay

    /// Scaled rather than fixed: `microLabel` is `caption2`, which grows with Dynamic
    /// Type, so a hard-coded box would be outgrown by its own glyph at accessibility
    /// sizes — the state mark would spill over the date above it. Tied to the same
    /// text style the glyph is rendered in, so the two grow together.
    @ScaledMetric(relativeTo: .caption2) private var glyphSize = LayoutMetrics.calendarGlyphSize

    /// Scaled alongside the glyph for the same reason: a mark that stayed 6pt while the
    /// cell's content grew would shrink out of the design at accessibility sizes,
    /// exactly when the reader needs it most.
    @ScaledMetric(relativeTo: .caption2) private var markSize = LayoutMetrics.scoreBandMarkSize

    /// The plan ring's gutter, scaled with the cell's own text for the same reason the
    /// two marks above are: at accessibility sizes the cell grows and a fixed 3pt gutter
    /// would close up against a fill that had grown around it.
    @ScaledMetric(relativeTo: .caption2) private var ringGutter = LayoutMetrics.planRingGutter

    /// Increase Contrast thickens the ring. `Ink` already brightens the accent itself
    /// (MAX-070); this is the non-colour half design review §8.3 says nothing in this
    /// app currently does.
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private var ringWidth: CGFloat {
        colorSchemeContrast == .increased
            ? LayoutMetrics.planRingWidthIncreasedContrast
            : LayoutMetrics.planRingWidth
    }

    var body: some View {
        // The square is driven by the column's width alone, never by what is drawn
        // inside it. `Color.clear` has no intrinsic size, so `aspectRatio(1, .fit)`
        // resolves against the proposed width and every cell in the grid comes out
        // identical; the content is overlaid and cannot push the frame around.
        //
        // Sizing the *content* instead is what went wrong before: the glyph changes
        // with the day's state, and SF Symbols do not share an intrinsic height —
        // `minus` is a thin dash, `figure.run.square.stack` is a tall stacked mark.
        // A VStack around them is correspondingly different heights, so squaring to
        // "fit the content" made a day's size depend on what the athlete did that
        // day. Rest days came out visibly smaller than runs.
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                VStack(spacing: Spacing.hairspace) {
                    Text("\(day.date.day)")
                        .font(.microLabel)
                        .foregroundStyle(ScoreCalendarPalette.ink(for: day.state))
                    Image(systemName: ScoreCalendarFormatting.systemImageName(for: day.state))
                        .font(.microLabel)
                        .foregroundStyle(ScoreCalendarPalette.ink(for: day.state))
                        // Symbols vary in intrinsic width too, so a fixed square keeps
                        // the glyph optically centred rather than nudging the number
                        // off-axis on wider marks.
                        .frame(width: glyphSize, height: glyphSize)
                }
            }
            // The band's non-colour channel (MAX-084). Only a `.scored` day has a band
            // to mark — `.missed` draws in the same red but was never scored, and
            // `scoredBand` is the core accessor that says so.
            .overlay(alignment: .topTrailing) {
                if let band = day.state.scoredBand {
                    ScoreBandMarkView(band: band, diameter: markSize)
                        // Measured from the *fill's* corner, not the cell's: the fill
                        // moved inward by `ringGutter` when the plan layer landed, and
                        // a pip still padded from the footprint would have sat a point
                        // inside the colour it is drawn on. This keeps MAX-084's
                        // original inset from the corner the reader actually sees.
                        .padding(ringGutter + Spacing.tight)
                }
            }
        // Not `.contentSurface(.tile)`: that fixes the fill to `.surfaceElevated`,
        // and this cell's fill is exactly the thing D4 asks it to carry — the score
        // band. `CornerRadius.tile` is reused anyway, matching `ContentSurface`'s own
        // note that a calendar cell is a tile-scale surface.
        //
        // Inset by the ring's gutter rather than drawn at the footprint (MAX-105), and
        // inset on every cell rather than only the ringed ones, so the grid's fills
        // stay one size. The radius shrinks with the inset so the fill's corners stay
        // concentric with the ring's instead of reading as a rounder shape inside a
        // squarer one.
        .background {
            if !day.state.isDrawnUnfilledInTheDayGrid {
                RoundedRectangle(cornerRadius: insetCornerRadius, style: .continuous)
                    .fill(ScoreCalendarPalette.fill(for: day.state))
                    .padding(ringGutter)
            }
        }
        // The plan layer: the ground the outcome above is drawn on. Last, so it sits at
        // the cell's own edge with the fill inside it — never over a band colour.
        .overlay {
            if day.prescribesASession {
                RoundedRectangle(cornerRadius: CornerRadius.tile, style: .continuous)
                    .strokeBorder(Color.accent, lineWidth: ringWidth)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ScoreCalendarFormatting.accessibilityLabel(for: day))
    }

    /// The fill's corner radius, concentric with the ring's `CornerRadius.tile`.
    /// Floored at zero because `ringGutter` grows with Dynamic Type and would otherwise
    /// go negative at accessibility sizes, which `RoundedRectangle` treats as undefined.
    private var insetCornerRadius: CGFloat {
        max(0, CornerRadius.tile - ringGutter)
    }
}

/// One mark in the year heatmap: a square of the day's band colour and nothing else.
///
/// A nil `day` is a day outside the selected interval — the partial first and last weeks
/// of a calendar year — and is drawn as empty space. Never as a neutral cell: that would
/// extend the year by up to twelve days it does not contain.
private struct ScoreCalendarHeatmapCell: View {
    let day: ScoreCalendarDay?

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .background(background)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHidden(day == nil)
    }

    /// Two non-hue channels, for two different distinctions.
    ///
    /// A missed day is stroked rather than filled — separating "I did not run" from "I
    /// ran badly", which share a fill by design (D9). See
    /// `ScoreCalendarDayState.isDrawnHollowAtHeatmapDensity`. A scored day is filled,
    /// but not always at the mark's full footprint: `ScoreBandHeatmapMarkView` sizes it
    /// by `ScoreBand.heatmapMark` (MAX-087), the channel that separates `.effective`
    /// from `.marginal` from `.ineffective` now that there is no room for a corner pip.
    /// A day with no band at all — rest, awaiting-score, forthcoming, unplanned — draws
    /// a plain full-footprint fill. The three cases never compete for the same cell, so
    /// a reader is never asked to read two channels in the same glance.
    ///
    /// `.forthcoming` (MAX-105) lands in that last group deliberately. Hollow already
    /// means "asked and not delivered" here, and a day that has not arrived is the one
    /// thing that must never read that way; a neutral mark says "nothing here yet",
    /// which is the truth.
    @ViewBuilder
    private var background: some View {
        if let day, day.state.isDrawnHollowAtHeatmapDensity {
            RoundedRectangle(cornerRadius: CornerRadius.heatmapMark, style: .continuous)
                .strokeBorder(
                    ScoreCalendarPalette.fill(for: day.state),
                    lineWidth: LayoutMetrics.heatmapMarkStroke
                )
        } else if let day, let band = day.state.scoredBand {
            ScoreBandHeatmapMarkView(band: band, cornerRadius: CornerRadius.heatmapMark)
        } else if let day {
            RoundedRectangle(cornerRadius: CornerRadius.heatmapMark, style: .continuous)
                .fill(ScoreCalendarPalette.fill(for: day.state))
        }
    }

    private var accessibilityLabel: String {
        guard let day else { return "" }
        return ScoreCalendarFormatting.heatmapAccessibilityLabel(for: day)
    }
}

/// The two colour decisions a calendar cell makes, shared by both arrangements so a day
/// cannot read as one band in the month grid and another in the year heatmap.
private enum ScoreCalendarPalette {
    static func fill(for state: ScoreCalendarDayState) -> Color {
        switch state {
        case .scored(let band, _):
            return Color.scoreBand(band)
        case .missed:
            // Not a fourth band — D9 says a missed scheduled session "shows red",
            // and the rubric's own "skipped" band already lands in `.ineffective`'s
            // range (§10.3). Reusing the token keeps this screen's whole saturated
            // palette to the three colors `ScoreBandColors.swift` reserves for it,
            // which is also what makes a score-band heatmap a legitimate use of them
            // rather than a fourth surface borrowing the product's one signal.
            return Color.scoreIneffective
        case .awaitingScore, .convertedRest, .scheduledRest, .forthcoming, .unplanned:
            // `.forthcoming` is listed here for the year heatmap, where every
            // no-verdict day draws the same neutral mark. In the day grid it is drawn
            // with no fill at all — see `isDrawnUnfilledInTheDayGrid` — so this value
            // is never reached there.
            return Color.surfaceInset
        }
    }

    static func ink(for state: ScoreCalendarDayState) -> Color {
        switch state {
        case .scored, .missed:
            return Color.textOnSaturatedFill
        case .awaitingScore, .convertedRest, .scheduledRest, .forthcoming, .unplanned:
            // `.forthcoming`'s date and glyph sit on the calendar card rather than on
            // `surfaceInset`, since the cell has no fill. `textSecondary` is a text
            // token designed for both — it is the same ink the card's own labels use.
            return Color.textSecondary
        }
    }
}

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
/// **The year heatmap still has that gap, and it is not fixable with a mark.** A heatmap
/// cell is about six points square; there is no corner to put a pip in, which is the case
/// MAX-083 predicted would test T6 and it fails it. The shape channel there stays narrowed
/// to the distinction that survives at that size — a missed day is drawn hollow, a
/// badly-scored day filled (`ScoreCalendarDayState.isDrawnHollowAtHeatmapDensity`) — and
/// the VoiceOver sentence, dated with its month since nothing on screen says which day it
/// is, carries the rest. **So at year density, good and not-quite remain a hue
/// distinction.** Closing it would take a channel that works at six points: separating the
/// two fills on the luminance axis, or drawing marginal inset. Both are judgements about
/// something nobody here can look at, and neither is this ticket's.
///
/// `.scheduledRest` and `.convertedRest` sit on the same neutral fill as
/// `.awaitingScore` and `.unplanned` (`ScoreBandColors.swift`'s own doc comment: a
/// day with no verdict is not a fourth saturated band) but each still gets its own
/// glyph and its own sentence, so "the plan asked for rest" and "a miss was forgiven"
/// never read as the same fact even though neither is a judgment.
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
/// `day.state`; nothing here branches on a threshold or a raw score.
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
                        .padding(Spacing.tight)
                }
            }
        // Not `.contentSurface(.tile)`: that fixes the fill to `.surfaceElevated`,
        // and this cell's fill is exactly the thing D4 asks it to carry — the score
        // band. `CornerRadius.tile` is reused anyway, matching `ContentSurface`'s own
        // note that a calendar cell is a tile-scale surface.
        .background(
            ScoreCalendarPalette.fill(for: day.state),
            in: RoundedRectangle(cornerRadius: CornerRadius.tile, style: .continuous)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ScoreCalendarFormatting.accessibilityLabel(for: day.state, on: day.date))
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

    /// A missed day is stroked rather than filled — the one non-hue channel that
    /// survives at this size, separating "I did not run" from "I ran badly", which share
    /// a fill by design (D9). See `ScoreCalendarDayState.isDrawnHollowAtHeatmapDensity`.
    @ViewBuilder
    private var background: some View {
        if let day, day.state.isDrawnHollowAtHeatmapDensity {
            RoundedRectangle(cornerRadius: CornerRadius.heatmapMark, style: .continuous)
                .strokeBorder(
                    ScoreCalendarPalette.fill(for: day.state),
                    lineWidth: LayoutMetrics.heatmapMarkStroke
                )
        } else if let day {
            RoundedRectangle(cornerRadius: CornerRadius.heatmapMark, style: .continuous)
                .fill(ScoreCalendarPalette.fill(for: day.state))
        }
    }

    private var accessibilityLabel: String {
        guard let day else { return "" }
        return ScoreCalendarFormatting.heatmapAccessibilityLabel(for: day.state, on: day.date)
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
        case .awaitingScore, .convertedRest, .scheduledRest, .unplanned:
            return Color.surfaceInset
        }
    }

    static func ink(for state: ScoreCalendarDayState) -> Color {
        switch state {
        case .scored, .missed:
            return Color.textOnSaturatedFill
        case .awaitingScore, .convertedRest, .scheduledRest, .unplanned:
            return Color.textSecondary
        }
    }
}

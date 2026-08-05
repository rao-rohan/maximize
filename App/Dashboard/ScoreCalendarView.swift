import SwiftUI
import MaximizeCore

/// FR-3.2 / D4 / D9 / A6: the score-colored calendar for the dashboard's selected
/// interval.
///
/// ## What this view does and does not decide
///
/// Every day's state — scored (and which band), awaiting a score, missed, converted
/// to rest, scheduled rest, or ungoverned by any plan — is decided by
/// `MaximizeCore.ScoreCalendar`, unit tested there. This view's only job is turning
/// each `ScoreCalendarDay` into a cell: a fill, a glyph, and an accessibility
/// sentence, all sourced from `ScoreCalendarFormatting` or the design system's own
/// tokens (`Color.scoreBand(_:)`, `ScoreBandColors.swift`) — never a literal.
///
/// ## Colour is never the only channel (constraint #4)
///
/// Two more channels carry every state independently of hue, so a colour-blind
/// athlete reads the same calendar a sighted one does:
///
/// 1. **A `.missed` day and a `.scored(.ineffective, _)` day share the same red
///    fill** (D9 says a miss "shows red"; the rubric's own "skipped → 0–15" band
///    lands in the same score range .ineffective already covers), **but never the
///    same glyph** — an activity icon for a bad run, a dedicated "×" for a day
///    nothing happened. Shape alone tells the two apart in grayscale.
/// 2. **Every cell carries a full-sentence VoiceOver label**
///    (`ScoreCalendarFormatting.accessibilityLabel`), not just a glyph name — the
///    channel that does not depend on shape recognition at all.
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
            case .loaded(let days):
                grid(days)
            }
        }
        .contentSurface(.card)
        .task(id: interval) {
            await model.load(for: interval)
        }
    }

    @ViewBuilder
    private func grid(_ days: [ScoreCalendarDay]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            weekdayHeader
            LazyVGrid(columns: columns, spacing: Spacing.tight) {
                // Leading blanks so the first real day lands under its own weekday
                // column — a month or custom range rarely starts on a Monday.
                ForEach(0..<leadingPadCount(for: days), id: \.self) { _ in
                    Color.clear
                }
                ForEach(days) { day in
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

    private func leadingPadCount(for days: [ScoreCalendarDay]) -> Int {
        guard let first = days.first else { return 0 }
        return first.date.weekday.rawValue - 1
    }
}

/// One calendar cell. Its fill and glyph are read from `day.state`; nothing here
/// branches on a threshold or a raw score.
private struct ScoreCalendarDayCell: View {
    let day: ScoreCalendarDay

    var body: some View {
        VStack(spacing: Spacing.hairspace) {
            Text("\(day.date.day)")
                .font(.microLabel)
                .foregroundStyle(inkColor)
            Image(systemName: ScoreCalendarFormatting.systemImageName(for: day.state))
                .font(.microLabel)
                .foregroundStyle(inkColor)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        // Not `.contentSurface(.tile)`: that fixes the fill to `.surfaceElevated`,
        // and this cell's fill is exactly the thing D4 asks it to carry — the score
        // band. `CornerRadius.tile` is reused anyway, matching `ContentSurface`'s own
        // note that a calendar cell is a tile-scale surface.
        .background(fillColor, in: RoundedRectangle(cornerRadius: CornerRadius.tile, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ScoreCalendarFormatting.accessibilityLabel(for: day.state, on: day.date))
    }

    private var fillColor: Color {
        switch day.state {
        case .scored(let band, _):
            return Color.scoreBand(band)
        case .missed:
            // Not a fourth band — D9 says a missed scheduled session "shows red",
            // and the rubric's own "skipped" band already lands in `.ineffective`'s
            // range (§10.3). Reusing the token keeps this screen's whole saturated
            // palette to the three colors `ScoreBandColors.swift` reserves for it.
            return Color.scoreIneffective
        case .awaitingScore, .convertedRest, .scheduledRest, .unplanned:
            return Color.surfaceInset
        }
    }

    private var inkColor: Color {
        switch day.state {
        case .scored, .missed:
            return Color.textOnSaturatedFill
        case .awaitingScore, .convertedRest, .scheduledRest, .unplanned:
            return Color.textSecondary
        }
    }
}

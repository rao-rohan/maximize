import SwiftUI
import MaximizeCore

/// The content shared by the plan tab's current-version screen (`PlanView`) and a
/// historical version's screen (`PlanVersionDetailView`) — MAX-102, A15.
///
/// Everything here is `PlanDisplayData.VersionDetail`, already resolved: which arc week
/// is "this week" (if any), how the effective range reads, what each row says. This
/// view lays those values out on the app's existing content-surface cards — the same
/// visual grammar `DashboardView` and `WorkoutDetailView` already use for "look at
/// data" screens — rather than a `Form`/`List`, which this app reserves for *editing*
/// (`PlanAuthoringView`, `SettingsView`). Nothing here computes anything: no date
/// arithmetic, no formatting decision beyond `PlanFormatting`'s copy.
struct PlanDetailSections: View {
    let detail: PlanDisplayData.VersionDetail
    let distanceUnit: DistanceUnit

    var body: some View {
        Group {
            headerCard
            numbersCard
            weekCard
            arcCard
            rubricCard
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: Spacing.compact) {
            if !detail.isCurrent {
                Text("Historical version")
                    .font(.metricLabel)
                    .foregroundStyle(Color.textSecondary)
            }

            Text(PlanFormatting.versionTitle(detail.version))
                .font(.sectionHeading)
                .foregroundStyle(Color.textPrimary)

            Text(
                PlanFormatting.effectiveRangeLine(
                    effectiveFrom: detail.effectiveFrom,
                    effectiveThrough: detail.effectiveThrough
                )
            )
            .font(.metricLabel)
            .foregroundStyle(Color.textSecondary)

            if !detail.goalStatements.isEmpty || detail.goalTargetDay != nil {
                VStack(alignment: .leading, spacing: Spacing.tight) {
                    ForEach(detail.goalStatements, id: \.self) { statement in
                        Text(statement)
                            .font(.bodyCopy)
                            .foregroundStyle(Color.textPrimary)
                    }
                    if let targetDay = detail.goalTargetDay {
                        Text(PlanFormatting.targetDay(targetDay))
                            .font(.metricLabel)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                .padding(.top, Spacing.tight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentSurface(.card)
    }

    // MARK: - The two numbers every chart draws

    private var numbersCard: some View {
        VStack(alignment: .leading, spacing: Spacing.compact) {
            Text("Targets")
                .font(.sectionHeading)
                .foregroundStyle(Color.textPrimary)

            HStack(spacing: Spacing.compact) {
                numberTile(value: PlanFormatting.heartRateCap(detail.heartRateCapBPM), caption: "Heart-rate cap")
                numberTile(value: PlanFormatting.cadenceTarget(detail.cadenceTarget), caption: "Cadence target")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentSurface(.card)
    }

    private func numberTile(value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            Text(value)
                .font(.metricPrimary)
                .foregroundStyle(Color.textPrimary)
            Text(caption)
                .font(.metricLabel)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentSurface(.tile)
    }

    // MARK: - Weekly template

    /// Both slots (A17): a week is fourteen asks now, not seven, and this section
    /// already made its density call for seven rows before lifting existed. That call
    /// is kept rather than doubled — one row per weekday, still — because the
    /// alternative (two rows per weekday) makes the section that exists to be read at
    /// a glance the least scannable thing on the screen, and because a fourteen-row
    /// list makes the common case — rest on both slots — cost exactly as much visual
    /// weight as a day carrying two real sessions, which is the thing this ticket's
    /// brief specifically warns against. A day that is busier gets a taller row, via a
    /// second line of value text (`PlanFormatting.weekdayLines`); a rest-on-both day
    /// stays the one short line it always was.
    private var weekCard: some View {
        VStack(alignment: .leading, spacing: Spacing.compact) {
            Text("Weekly template")
                .font(.sectionHeading)
                .foregroundStyle(Color.textPrimary)

            VStack(alignment: .leading, spacing: Spacing.snug) {
                ForEach(detail.week) { day in
                    weekdayRow(day)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentSurface(.card)
    }

    private func weekdayRow(_ day: PlanDisplayData.WeekdayRow) -> some View {
        HStack(alignment: .top) {
            Text(PlanFormatting.weekday(day.weekday))
                .foregroundStyle(Color.textPrimary)
            Spacer()
            VStack(alignment: .trailing, spacing: Spacing.tight) {
                ForEach(PlanFormatting.weekdayLines(day, unit: distanceUnit), id: \.self) { line in
                    Text(line)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .font(.bodyCopy)
        // A two-line day is one fact, not two: "Tuesday, easy run 8 km, lift chest and
        // shoulders" as a single VoiceOver stop rather than fragments that arrive
        // separated from the weekday they belong to.
        .accessibilityElement(children: .combine)
    }

    // MARK: - Long-run arc

    private var arcCard: some View {
        VStack(alignment: .leading, spacing: Spacing.compact) {
            Text("Long-run arc")
                .font(.sectionHeading)
                .foregroundStyle(Color.textPrimary)

            VStack(alignment: .leading, spacing: Spacing.snug) {
                ForEach(detail.arc) { week in
                    HStack {
                        Text("Week \(week.index)")
                        if week.isCurrentWeek {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accent)
                                .accessibilityLabel("This week")
                        }
                        Spacer()
                        Text(PlanFormatting.distance(week.distanceMeters, unit: distanceUnit))
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentSurface(.card)
    }

    // MARK: - Rubric

    private var rubricCard: some View {
        VStack(alignment: .leading, spacing: Spacing.compact) {
            Text("Rubric")
                .font(.sectionHeading)
                .foregroundStyle(Color.textPrimary)

            Text(PlanFormatting.threshold(effective: detail.effectiveThreshold, marginal: detail.marginalThreshold))
                .font(.metricLabel)
                .foregroundStyle(Color.textSecondary)

            VStack(alignment: .leading, spacing: Spacing.regular) {
                ForEach(detail.bands) { band in
                    VStack(alignment: .leading, spacing: Spacing.tight) {
                        HStack {
                            Text(PlanFormatting.scoreRange(band.scoreRange))
                                .font(.metricSecondary)
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                            Text(PlanFormatting.appliesTo(band.appliesTo))
                                .font(.metricLabel)
                                .foregroundStyle(Color.textSecondary)
                        }
                        Text(band.rationale)
                            .font(.bodyCopy)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .padding(.top, Spacing.tight)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentSurface(.card)
    }
}

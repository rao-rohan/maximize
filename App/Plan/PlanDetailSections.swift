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

    private var weekCard: some View {
        VStack(alignment: .leading, spacing: Spacing.compact) {
            Text("Weekly template")
                .font(.sectionHeading)
                .foregroundStyle(Color.textPrimary)

            VStack(alignment: .leading, spacing: Spacing.snug) {
                ForEach(detail.week) { day in
                    row(PlanFormatting.weekday(day.weekday), weekdayValue(day))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentSurface(.card)
    }

    private func weekdayValue(_ day: PlanDisplayData.WeekdayRow) -> String {
        var text = PlanFormatting.sessionKind(day.kind)
        if let meters = day.distanceMeters {
            text += " · " + PlanFormatting.distance(meters, unit: distanceUnit)
        }
        if let note = day.note, !note.isEmpty {
            text += " · " + note
        }
        return text
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

    // MARK: - Shared row

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(Color.textPrimary)
            Spacer()
            Text(value)
                .foregroundStyle(Color.textSecondary)
        }
        .font(.bodyCopy)
    }
}

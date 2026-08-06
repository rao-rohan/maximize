import SwiftUI
import MaximizeCore

/// FR-1.5: the per-split pace breakdown for one workout.
///
/// ## What this view does and does not decide
///
/// Every decision is already made by `MaximizeCore.SplitsListData` (MAX-046): which of
/// the three states this workout is in, which unit the splits are shown in, which rows
/// exist, and every formatted string in them. This view lays them out. It never divides
/// a distance by a time, never reads a route, and has no opinion on what makes a split
/// partial — the splits themselves were computed once at ingestion and stored (D2), and
/// a view that recomputed one would be the second source of truth D2 forbids.
///
/// ## The three states
///
/// - **`.noRoute`** — an indoor run. Renders nothing at all, the same way `RouteMapView`
///   contributes no card for a treadmill run (FR-0.6). There was never a track to cut
///   into splits, and a placeholder would be an apology for a first-class case.
/// - **`.unavailable`** — an outdoor run with no stored breakdown, most often because it
///   was ingested before splits were computed at all. Says so, rather than omitting the
///   section and looking like the run was indoors.
/// - **`.available`** — one row per split. The trailing partial row carries its own
///   distance instead of an ordinal and is captioned, because its pace is extrapolated
///   from a short stretch and is not comparable with the complete splits above it.
struct SplitsView: View {
    let data: SplitsListData

    var body: some View {
        switch data {
        case .noRoute:
            EmptyView()
        case .unavailable:
            VStack(alignment: .leading, spacing: Spacing.compact) {
                header(paceCaption: nil)
                Text(SplitsListData.unavailableExplanation)
                    .font(.bodyCopy)
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentSurface(.inset)
            }
            .contentSurface(.card)
        case let .available(content):
            VStack(alignment: .leading, spacing: Spacing.compact) {
                header(paceCaption: content.paceCaption)
                VStack(spacing: Spacing.tight) {
                    ForEach(Array(content.rows.enumerated()), id: \.offset) { _, row in
                        rowView(row)
                    }
                }
            }
            .contentSurface(.card)
        }
    }

    private func header(paceCaption: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Splits")
                .font(.sectionHeading)
                .foregroundStyle(Color.textPrimary)
            Spacer(minLength: Spacing.snug)
            if let paceCaption {
                Text(paceCaption)
                    .font(.metricLabel)
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }

    private func rowView(_ row: SplitsListData.Content.Row) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.snug) {
            Text(row.label)
                .font(.metricLabel)
                .foregroundStyle(Color.textSecondary)
            if let note = row.note {
                Text(note)
                    .font(.microLabel)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer(minLength: Spacing.compact)
            Text(row.pace)
                .font(.metricSecondary)
                .foregroundStyle(Color.textPrimary)
                .monospacedDigit()
        }
        .contentSurface(.inset)
        .accessibilityElement(children: .combine)
    }
}

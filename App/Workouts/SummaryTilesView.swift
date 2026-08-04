import SwiftUI
import MaximizeCore

/// FR-1.5: the summary tiles — distance, duration, avg/max HR, energy, drift %,
/// grade-adjusted pace — for one workout.
///
/// ## What this view does and does not decide
///
/// Every string here is precomputed by `MaximizeCore.SummaryTileData` (MAX-045): which
/// figures are present, their order (FR-1.5's own: distance, duration, avg/max HR,
/// energy, drift %, grade-adjusted pace), and every formatted value and caption. This
/// view only lays `SummaryTileData.tiles` out in a grid on design-system tokens — no
/// rounding, no unit conversion, no threshold comparison happens here.
///
/// Thin on purpose, per FR-1.5's own description of itself: one tile shape
/// (`.contentSurface(.tile)`, `.metricPrimary` value over `.metricLabel` caption),
/// reused for every figure, laid out in a plain two-column grid. Nothing here is
/// color-coded, judged, or compared against a target — that kind of verdict belongs to
/// `HRCurveView` and `CadenceBandView`, not to a thin summary tile.
///
/// ## Absent figures are omitted, not zeroed
///
/// `SummaryTileData.tiles` already excludes every figure this workout does not have
/// (MAX-010's "absent, not empty") — no distance, no HR series, drift withheld as not
/// meaningful for the session. This view never fills a gap with "0" or "--"; a missing
/// tile is a tile that is not drawn. `duration` is the one figure that is never absent
/// (a workout always has one), so the grid is never completely empty.
struct SummaryTilesView: View {
    let data: SummaryTileData

    private let columns = [
        GridItem(.flexible(), spacing: Spacing.compact),
        GridItem(.flexible(), spacing: Spacing.compact),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.compact) {
            Text("Summary")
                .font(.sectionHeading)
                .foregroundStyle(Color.textPrimary)

            LazyVGrid(columns: columns, alignment: .leading, spacing: Spacing.compact) {
                ForEach(Array(data.tiles.enumerated()), id: \.offset) { _, tile in
                    tileView(tile)
                }
            }
        }
        .contentSurface(.card)
    }

    private func tileView(_ tile: SummaryTileData.Tile) -> some View {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            Text(tile.value)
                .font(.metricPrimary)
                .foregroundStyle(Color.textPrimary)
            Text(tile.caption)
                .font(.metricLabel)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentSurface(.tile)
    }
}

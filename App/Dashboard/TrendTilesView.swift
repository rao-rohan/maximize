import SwiftUI
import MaximizeCore

/// FR-3.4: the interval-scoped summary tiles for the dashboard's selected
/// `TrendInterval`.
///
/// ## What this view does and does not decide
///
/// Every string here is precomputed by `MaximizeCore.TrendTileData` (MAX-063): which
/// figures are present — **including which ones this span measures at all**, which
/// changes between a week, a month and a year (MAX-083, see `TrendTileSet`) — their
/// FR-3.4 order, and every formatted value and caption. This view is unchanged by that:
/// it lays `TrendTileData.tiles` out in a grid on design-system tokens, mirroring
/// `SummaryTilesView`'s (MAX-045) tile shape and layout so the two read as one visual
/// language rather than two competing ones — no rounding, no unit conversion, no
/// threshold comparison happens here.
///
/// ## Absent figures are omitted, not zeroed
///
/// `TrendTileData.tiles` already excludes every figure that does not apply to this
/// interval — no plan governing it, nothing yet scored (see that type's own
/// documentation for the full list). This view never fills a gap with "0" or "--"; a
/// missing tile is a tile that is not drawn. `streak` is the one figure that is never
/// absent, so the grid is never completely empty once loading finishes successfully.
struct TrendTilesView: View {
    let interval: TrendInterval

    @State private var model = TrendTilesModel()

    private let columns = [
        GridItem(.flexible(), spacing: Spacing.compact),
        GridItem(.flexible(), spacing: Spacing.compact),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.compact) {
            Text("Summary")
                .font(.sectionHeading)
                .foregroundStyle(Color.textPrimary)

            content
        }
        .contentSurface(.card)
        .task(id: interval) {
            await model.load(interval: interval)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, alignment: .center)
        case .loaded(let data):
            LazyVGrid(columns: columns, alignment: .leading, spacing: Spacing.compact) {
                ForEach(Array(data.tiles.enumerated()), id: \.offset) { _, tile in
                    tileView(tile)
                }
            }
        case .failed:
            Text("Couldn't load the summary for this interval.")
                .font(.metricLabel)
                .foregroundStyle(Color.textSecondary)
        }
    }

    private func tileView(_ tile: TrendTileData.Tile) -> some View {
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

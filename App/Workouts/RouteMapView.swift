import SwiftUI
import MapKit
import MaximizeCore

/// FR-1.4: the run's route on a map — outdoor runs only, omitted cleanly for
/// treadmill.
///
/// ## What this view does and does not decide
///
/// Every decision that matters here — which of FR-1.4's three states this workout is
/// in, which coordinates to draw, and how to frame the map — is made by
/// `MaximizeCore.RouteMapData` (MAX-044) via `resolve(hasRoute:route:)`. This view only
/// turns the resolved case into a `Map`, or the absence of one. It never reads
/// `Workout.hasRoute`, never asks the store for a route, and has no branch of its own
/// on what "outdoor" or "indoor" means — that decision was already made in
/// `WorkoutDetailModel`, where CI can verify it.
///
/// ## The three states FR-1.4 has to get right
///
/// - **`.noRoute`** — an indoor/treadmill run. FR-0.6's first-class case, not a
///   degraded one: this view renders nothing at all, not a placeholder card, not a
///   "no route" message, not a spinner. FR-1.4's "omitted cleanly" means there is
///   nothing here to see, the same way `RouteMapView` itself contributes no card to
///   the screen for this workout.
/// - **`.unavailable`** — an outdoor run whose route the capture source recorded
///   (`Workout.hasRoute`) but the store does not have. Distinct from `.noRoute` on
///   purpose: this run should have a route, so the section says so honestly rather
///   than silently looking like a treadmill run.
/// - **`.available`** — the stored route, drawn as a line and framed to the region
///   `RouteMapData.Content` already computed. This view does not compute a bounding
///   box, a center, or a span of its own; it hands `region` straight to `MKCoordinateRegion`.
struct RouteMapView: View {
    let data: RouteMapData

    var body: some View {
        switch data {
        case .noRoute:
            EmptyView()
        case .unavailable:
            VStack(alignment: .leading, spacing: Spacing.compact) {
                header
                unavailableMessage
            }
            .contentSurface(.card)
        case let .available(content):
            VStack(alignment: .leading, spacing: Spacing.compact) {
                header
                map(for: content)
            }
            .contentSurface(.card)
        }
    }

    private var header: some View {
        Text("Route")
            .font(.sectionHeading)
            .foregroundStyle(Color.textPrimary)
    }

    // MARK: - Map

    @ViewBuilder
    private func map(for content: RouteMapData.Content) -> some View {
        Map(initialPosition: .region(mapRegion(content.region))) {
            MapPolyline(coordinates: content.coordinates.map(coordinate))
                .stroke(Color.chartSeriesPrimary, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .frame(minHeight: LayoutMetrics.minimumChartHeight)
        .contentSurface(.inset)
    }

    private func coordinate(_ point: RouteMapData.Content.Coordinate) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: point.latitudeDegrees, longitude: point.longitudeDegrees)
    }

    /// The only place this view touches `MKCoordinateRegion` — a direct translation of
    /// `RouteMapData.Content.Region`'s already-decided center and span, never a
    /// recomputation of either.
    private func mapRegion(_ region: RouteMapData.Content.Region) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: region.centerLatitudeDegrees,
                longitude: region.centerLongitudeDegrees
            ),
            span: MKCoordinateSpan(
                latitudeDelta: region.latitudeDeltaDegrees,
                longitudeDelta: region.longitudeDeltaDegrees
            )
        )
    }

    // MARK: - Unavailable

    private var unavailableMessage: some View {
        Text(RouteMapData.unavailableExplanation)
            .font(.bodyCopy)
            .foregroundStyle(Color.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentSurface(.inset)
    }
}

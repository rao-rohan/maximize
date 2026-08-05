import Foundation

/// List-ready presentation of one workout's pace splits (FR-1.5) — the display half of
/// MAX-046, mirroring `SummaryTileData` (MAX-045) and `RouteMapData` (MAX-044).
///
/// ## Nothing here computes a split
///
/// Every figure below is read from `DerivedMetrics.distanceSplits`, which
/// `DistanceSplitCalculator` cut once at ingestion (D2). This type chooses a unit,
/// formats, and decides which of three on-screen states the workout is in. It never
/// touches a route, a duration or a distance — a second place deriving pace-per-kilometre
/// is precisely the drift D2 exists to prevent, and it is why MAX-045 declined to build
/// this section from a view.
///
/// ## The three states, and why "no splits" is not one message
///
/// `resolve(hasRoute:splits:unit:)` is where the branch lives, so CI checks it rather
/// than a `if let` in a view:
///
/// - **`.noRoute`** — an indoor run (FR-0.6). There was never a track to cut up, so the
///   section omits itself the way `RouteMapView` omits the map. Not an apology.
/// - **`.unavailable`** — an outdoor run with no stored breakdown. Three real causes
///   share this state: the route could not be cut up (see `DistanceSplitCalculator`), the
///   route failed to load at ingestion, or **the run was ingested before MAX-046 existed
///   and its splits were never computed**. The last is the common one today and the
///   reason this state says something rather than nothing: "no splits recorded for this
///   run" is true, and silently omitting the section from an outdoor run would read as a
///   bug.
/// - **`.available`** — rows to draw.
public enum SplitsListData: Hashable, Sendable {
    case noRoute
    case unavailable
    case available(Content)

    /// The breakdown in one unit, formatted.
    public struct Content: Hashable, Sendable {
        /// One split, as two or three already-formatted strings. `SplitsView` lays these
        /// out and does nothing else with them.
        public struct Row: Hashable, Sendable {
            /// "1", "2", … for complete splits; the split's own distance ("0.42") for the
            /// trailing incomplete one, because "8" against 420 metres would be a lie
            /// about how far that row covers.
            public let label: String

            /// Pace over this split, as a stopwatch reading: "5:12".
            public let pace: String

            /// "partial" on the trailing incomplete split, nil otherwise.
            ///
            /// The caption exists because the pace beside it is an **extrapolation** from
            /// a short sample: 420 m of a finishing kick converts to a per-kilometre pace
            /// the athlete never held for a kilometre, and unmarked it would read as the
            /// fastest split of the run. The number is shown rather than withheld — it is
            /// a real measurement of a real stretch — and labelled so it is not compared
            /// like-for-like with the rows above it.
            public let note: String?

            public init(label: String, pace: String, note: String?) {
                self.label = label
                self.pace = pace
                self.note = note
            }
        }

        public let rows: [Row]

        /// "/km" or "/mi" — what the pace column is measured in, stated once as a column
        /// heading rather than repeated on every row.
        public let paceCaption: String

        public init(series: DistanceSplitSeries) {
            let unit = series.unit
            self.paceCaption = "/" + Self.abbreviation(of: unit)
            self.rows = series.splits.map { split in
                Row(
                    label: split.isComplete
                        ? String(split.ordinal)
                        : Self.formattedDistance(split.distanceMeters, in: unit),
                    // The same formatter the summary tiles use for grade-adjusted pace
                    // (MAX-045) — one stopwatch format for every pace and duration on the
                    // screen, so two figures in the same unit cannot be rounded
                    // differently in two places.
                    pace: SummaryTileData.formattedDuration(seconds: split.paceSeconds(per: unit)),
                    note: split.isComplete ? nil : "partial"
                )
            }
        }

        /// Two decimals, matching `SummaryTileData`'s distance tile — the same run's
        /// distance must not be rounded to a different precision two sections apart.
        /// Locale pinned to nil (POSIX) for the same reason MAX-045 pins it.
        static func formattedDistance(_ meters: Double, in unit: DistanceUnit) -> String {
            String(format: "%.2f", locale: nil, unit.converted(fromMeters: meters))
        }

        static func abbreviation(of unit: DistanceUnit) -> String {
            switch unit {
            case .kilometers: return "km"
            case .miles: return "mi"
            }
        }
    }

    /// Decides which state this workout is in and formats the rows, if any.
    ///
    /// - Parameters:
    ///   - hasRoute: `Workout.hasRoute`. False for every indoor run by construction —
    ///     the same input `RouteMapData.resolve` branches on, so the two sections cannot
    ///     disagree about whether a run was outdoors.
    ///   - splits: `DerivedMetrics.distanceSplits`, read and never recomputed (D2). Nil
    ///     for a run with no stored breakdown, including every run ingested before
    ///     MAX-046.
    ///   - unit: which of the stored series to show. Passed in rather than defaulted:
    ///     the record carries every unit precisely so this is a display choice, and
    ///     `AppSettings.distanceUnit` is what should make it once **MAX-047** wires that
    ///     setting through the app's display paths. Until then callers pass the same
    ///     kilometres every other distance on the screen is shown in.
    public static func resolve(
        hasRoute: Bool,
        splits: DistanceSplits?,
        unit: DistanceUnit
    ) -> SplitsListData {
        guard hasRoute else { return .noRoute }
        guard let series = splits?.series(in: unit) else { return .unavailable }
        return .available(Content(series: series))
    }
}

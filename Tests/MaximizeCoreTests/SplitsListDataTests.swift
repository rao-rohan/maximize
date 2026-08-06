import XCTest
@testable import MaximizeCore

/// MAX-046's display seam. The branch these tests exercise is the one that would
/// otherwise have lived as an `if let` inside `SplitsView`, where CI could not see it.
final class SplitsListDataTests: XCTestCase {
    private func series(
        unit: DistanceUnit,
        complete: [Double],
        partial: (meters: Double, seconds: Double)? = nil
    ) throws -> DistanceSplitSeries {
        var splits: [DistanceSplit] = []
        for (index, seconds) in complete.enumerated() {
            splits.append(
                try DistanceSplit(
                    ordinal: index + 1,
                    distanceMeters: unit.metersPerUnit,
                    elapsedSeconds: seconds,
                    isComplete: true
                )
            )
        }
        if let partial {
            splits.append(
                try DistanceSplit(
                    ordinal: complete.count + 1,
                    distanceMeters: partial.meters,
                    elapsedSeconds: partial.seconds,
                    isComplete: false
                )
            )
        }
        return try DistanceSplitSeries(unit: unit, splits: splits)
    }

    private func availableContent(_ data: SplitsListData) -> SplitsListData.Content? {
        guard case let .available(content) = data else { return nil }
        return content
    }

    // MARK: - The three states

    /// FR-0.6: an indoor run never had a track to cut up, so the section omits itself
    /// rather than apologising — the same shape `RouteMapData` uses for the map.
    func testIndoorRunResolvesToNoRoute() {
        XCTAssertEqual(
            SplitsListData.resolve(hasRoute: false, splits: nil, unit: .kilometers),
            .noRoute
        )
    }

    /// The state every run ingested before MAX-046 lands in. Distinct from `.noRoute` on
    /// purpose: this run *was* outdoors, so saying nothing would read as a bug rather than
    /// as the truthful "no splits recorded for this run".
    func testOutdoorRunWithNoStoredBreakdownResolvesToUnavailable() {
        XCTAssertEqual(
            SplitsListData.resolve(hasRoute: true, splits: nil, unit: .kilometers),
            .unavailable
        )
    }

    /// A record written by a build that did not know about a unit degrades to "no
    /// breakdown in that unit" — one section of one screen — rather than failing the whole
    /// metrics read.
    func testBreakdownMissingTheRequestedUnitResolvesToUnavailable() throws {
        let splits = try DistanceSplits(series: [series(unit: .kilometers, complete: [300])])
        XCTAssertEqual(
            SplitsListData.resolve(hasRoute: true, splits: splits, unit: .miles),
            .unavailable
        )
    }

    /// MAX-104: moved down from `SplitsView`'s own view literal so the sentence lives
    /// beside the enum case that selects it.
    func testUnavailableExplanationNamesTheRunNotAWorkout() {
        XCTAssertEqual(SplitsListData.unavailableExplanation, "No splits recorded for this run.")
    }

    // MARK: - Rows

    func testCompleteSplitsAreNumberedAndPacedInTheChosenUnit() throws {
        let splits = try DistanceSplits(series: [series(unit: .kilometers, complete: [312, 300, 288])])
        let content = try XCTUnwrap(
            availableContent(SplitsListData.resolve(hasRoute: true, splits: splits, unit: .kilometers))
        )

        XCTAssertEqual(content.paceCaption, "/km")
        XCTAssertEqual(content.rows.map(\.label), ["1", "2", "3"])
        // A complete split covers exactly one unit, so its pace *is* its elapsed time.
        XCTAssertEqual(content.rows.map(\.pace), ["5:12", "5:00", "4:48"])
        XCTAssertEqual(content.rows.map(\.note), [nil, nil, nil])
    }

    /// The partial row carries its own distance instead of an ordinal — "8" against 420
    /// metres would be a lie about how far that row covers — and is captioned, because its
    /// pace is extrapolated from a short stretch.
    func testPartialSplitCarriesItsDistanceAndACaption() throws {
        let splits = try DistanceSplits(
            series: [series(unit: .kilometers, complete: [300], partial: (meters: 420, seconds: 126))]
        )
        let content = try XCTUnwrap(
            availableContent(SplitsListData.resolve(hasRoute: true, splits: splits, unit: .kilometers))
        )

        XCTAssertEqual(content.rows.count, 2)
        XCTAssertEqual(content.rows.last?.label, "0.42")
        XCTAssertEqual(content.rows.last?.note, "partial")
        // 126 s over 420 m extrapolates to 300 s/km — the same pace as the complete split
        // above it, which is what makes the number worth showing at all.
        XCTAssertEqual(content.rows.last?.pace, "5:00")
    }

    /// The same stored record, read in the other unit. Nothing is recomputed to do this:
    /// both series were cut at ingestion, and this is a lookup (D2).
    func testMilesSeriesIsShownInMilesWhenAsked() throws {
        let splits = try DistanceSplits(
            series: [
                series(unit: .kilometers, complete: [300, 300]),
                series(unit: .miles, complete: [483]),
            ]
        )
        let content = try XCTUnwrap(
            availableContent(SplitsListData.resolve(hasRoute: true, splits: splits, unit: .miles))
        )

        XCTAssertEqual(content.paceCaption, "/mi")
        XCTAssertEqual(content.rows.map(\.pace), ["8:03"])
    }
}

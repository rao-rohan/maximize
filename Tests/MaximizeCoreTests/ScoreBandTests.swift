import XCTest
@testable import MaximizeCore

/// `ScoreBand` has no logic to test — that is the point of it. What these tests pin
/// down instead is its *contract*: the set of cases, and the raw values, which become
/// part of the persisted representation once scores are stored (D8 — the auto-score is
/// immutable, so its stored band must stay readable forever).
final class ScoreBandTests: XCTestCase {
    func testCasesAreExactlyTheThreeBands() {
        XCTAssertEqual(ScoreBand.allCases, [.effective, .marginal, .ineffective])
    }

    /// Raw values are a storage format, not a display string. Changing one silently
    /// re-labels every historical score, so a change here should have to break a test.
    func testRawValuesAreStable() {
        XCTAssertEqual(ScoreBand.effective.rawValue, "effective")
        XCTAssertEqual(ScoreBand.marginal.rawValue, "marginal")
        XCTAssertEqual(ScoreBand.ineffective.rawValue, "ineffective")
    }

    func testRoundTripsThroughCoding() throws {
        for band in ScoreBand.allCases {
            let data = try JSONEncoder().encode(band)
            let decoded = try JSONDecoder().decode(ScoreBand.self, from: data)
            XCTAssertEqual(decoded, band)
        }
    }
}

/// MAX-084's non-colour channel. The mapping itself is asserted here; that the three
/// values are *distinct*, and that they are what keeps the bands separable at all, is
/// asserted in `WCAGContrastTests` alongside the arithmetic that motivates it.
final class ScoreBandMarkTests: XCTestCase {
    func testMarkMapping() {
        XCTAssertEqual(ScoreBand.effective.mark, .filledPip)
        XCTAssertEqual(ScoreBand.marginal.mark, .hollowPip)
        XCTAssertEqual(ScoreBand.ineffective.mark, .unmarked)
    }

    /// The calendar's accessor. `.scored` is the only state that was ever handed a
    /// band; everything else — including `.missed`, which draws in the same red — has
    /// none to report, and reporting one would invent a verdict the scorer never gave.
    func testOnlyAScoredDayReportsABand() {
        XCTAssertEqual(
            ScoreCalendarDayState.scored(band: .marginal, activityType: .running).scoredBand,
            .marginal
        )
        XCTAssertNil(ScoreCalendarDayState.missed(scheduledKind: .easy).scoredBand)
        XCTAssertNil(ScoreCalendarDayState.awaitingScore(activityType: .running).scoredBand)
        // MAX-126. The one state whose whole meaning is "no band was reached and none
        // will be" — so if any state could tempt an accessor into inventing one, it is
        // this one, and it must not.
        XCTAssertNil(
            ScoreCalendarDayState.noVerdict(activityType: .traditionalStrengthTraining).scoredBand
        )
        XCTAssertNil(ScoreCalendarDayState.convertedRest(scheduledKind: .long).scoredBand)
        XCTAssertNil(ScoreCalendarDayState.scheduledRest.scoredBand)
        XCTAssertNil(ScoreCalendarDayState.unplanned.scoredBand)
        // MAX-135. The state that *does* hold a band and still must not report one: the
        // mixed day carries the band its met half earned, and draws on the miss red. A pip
        // there would put MAX-084's "which band is this fill" vocabulary on a fill that is
        // not a band, and describe the half of the day the cell is not about.
        XCTAssertNil(
            ScoreCalendarDayState.partiallyMet(
                met: ScoreCalendarDayState.MetObligation(discipline: .run, kind: .easy, band: .effective),
                unmet: ScoreCalendarDayState.UnmetObligation(discipline: .lift, kind: .lift, judgedBand: nil)
            ).scoredBand
        )
    }
}

/// MAX-087's non-colour channel for the year heatmap, where there is no room for
/// `ScoreBandMark`'s corner pip. The mapping itself is asserted here, mirroring
/// `ScoreBandMarkTests` above; that the three values are *distinct*, which is what
/// keeps the bands separable at heatmap density at all, is asserted in
/// `WCAGContrastTests` alongside `ScoreBandMark`'s own distinctness check.
final class ScoreBandHeatmapMarkTests: XCTestCase {
    func testHeatmapMarkMapping() {
        XCTAssertEqual(ScoreBand.effective.heatmapMark, .fullBleed)
        XCTAssertEqual(ScoreBand.marginal.heatmapMark, .majorInset)
        XCTAssertEqual(ScoreBand.ineffective.heatmapMark, .minorInset)
    }
}

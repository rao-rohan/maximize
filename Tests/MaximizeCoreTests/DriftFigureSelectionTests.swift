import Foundation
import XCTest
@testable import MaximizeCore

/// MAX-083 — the year span's drift section: a trendline over every run carrying a stored
/// drift figure, with no curve stack and no stored heart-rate curve read.
///
/// The fit itself is `HeartRateDriftTrendlineDataTests`' territory and is not re-tested
/// here. These are about the eligibility rules, and about the fact that they differ from
/// the overlay's on purpose.
final class DriftFigureSelectionTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01T00:00:00Z

    private func candidate(
        dayOffset: Int,
        classification: WorkoutClassification? = .easy,
        driftFraction: Double? = 0.03,
        id: UUID = UUID()
    ) -> DriftFigureSelection.Candidate {
        DriftFigureSelection.Candidate(
            workoutID: id,
            start: epoch.addingTimeInterval(Double(dayOffset) * 86_400),
            classification: classification,
            driftFraction: driftFraction
        )
    }

    // MARK: - Which span uses this

    func testOnlyTheYearSpanUsesTheTrendlineOnlyRepresentation() {
        XCTAssertEqual(TrendIntervalKind.week.driftSectionRepresentation, .curveOverlayLed)
        XCTAssertEqual(TrendIntervalKind.month.driftSectionRepresentation, .curveOverlayLed)
        XCTAssertEqual(TrendIntervalKind.year.driftSectionRepresentation, .trendlineOnly)
    }

    /// The performance half of the decision, stated as a value so the loader and the view
    /// cannot disagree about it. This is the assertion that would fail if someone
    /// "simplified" the year path back into reading every stored curve.
    func testOnlyTheCurveLedRepresentationReadsStoredHeartRateCurves() {
        XCTAssertTrue(DriftSectionRepresentation.curveOverlayLed.loadsStoredHeartRateCurves)
        XCTAssertFalse(DriftSectionRepresentation.trendlineOnly.loadsStoredHeartRateCurves)
    }

    func testEachRepresentationCarriesItsOwnHeading() {
        XCTAssertNotEqual(
            DriftSectionRepresentation.curveOverlayLed.title,
            DriftSectionRepresentation.trendlineOnly.title
        )
    }

    // MARK: - Eligibility

    func testAnEasyOrLongRunWithAStoredFigureIsPlotted() {
        let selection = DriftFigureSelection(candidates: [
            candidate(dayOffset: 0, classification: .easy, driftFraction: 0.02),
            candidate(dayOffset: 7, classification: .long, driftFraction: 0.04),
        ])

        XCTAssertEqual(selection.trendline.points.count, 2)
        XCTAssertEqual(selection.candidateCount, 2)
        XCTAssertFalse(selection.isEmpty)
    }

    /// Nothing has classified an unscored run, and classifying it here would be a second
    /// classifier free to disagree with the one the score is eventually computed under.
    func testAnUnscoredRunIsExcludedRatherThanClassifiedHere() {
        let selection = DriftFigureSelection(candidates: [
            candidate(dayOffset: 0, classification: nil, driftFraction: 0.02),
        ])

        XCTAssertTrue(selection.isEmpty)
        XCTAssertEqual(selection.count(of: .notYetScored), 1)
    }

    /// §9's rule, reached through `WorkoutClassification.driftIsMeaningful` rather than a
    /// second list of cases here.
    func testHardAndOtherSessionsAreExcluded() {
        let selection = DriftFigureSelection(candidates: [
            candidate(dayOffset: 0, classification: .hard),
            candidate(dayOffset: 1, classification: .other),
        ])

        XCTAssertTrue(selection.isEmpty)
        XCTAssertEqual(selection.count(of: .driftNotMeaningfulForThisSession), 2)
    }

    /// Absent is not zero: a run with no stored figure contributes no point rather than a
    /// point at 0%, which would pull the fit toward a number nobody measured.
    func testARunWithNoStoredDriftFigureContributesNoPoint() {
        let selection = DriftFigureSelection(candidates: [
            candidate(dayOffset: 0, driftFraction: nil),
            candidate(dayOffset: 1, driftFraction: 0.05),
        ])

        XCTAssertEqual(selection.trendline.points.count, 1)
        XCTAssertEqual(selection.trendline.points.first?.driftFraction, 0.05)
        XCTAssertEqual(selection.count(of: .noStoredDriftFigure), 1)
    }

    /// The figure is `DerivedMetrics.heartRateDriftFraction` passed straight through
    /// (D2) — a negative drift stays negative, and nothing rounds or clamps it.
    func testTheStoredFigureIsPassedThroughVerbatim() {
        let selection = DriftFigureSelection(candidates: [candidate(dayOffset: 0, driftFraction: -0.0234)])

        XCTAssertEqual(selection.trendline.points.first?.driftFraction, -0.0234)
    }

    // MARK: - Where it deliberately differs from the overlay

    /// The overlay excludes a curve covering less than `bucketCount × 5s` because a
    /// six-minute jog stretched to full width is noise magnified into apparent shape.
    /// That rule is about *drawing a shape* and does not apply to a stored scalar — this
    /// type never sees a curve, so a short run's figure is plotted like any other.
    ///
    /// Pinned as a property of the type: `Candidate` carries no series at all, so there
    /// is no length to filter on even if someone wanted to.
    func testAShortRunsStoredFigureIsStillPlotted() {
        // A three-minute run — far under `HeartRateDriftOverlayData.minimumCoveredSeconds`
        // at the default resolution — with a perfectly good stored figure.
        let selection = DriftFigureSelection(candidates: [candidate(dayOffset: 0, driftFraction: 0.018)])

        XCTAssertEqual(selection.trendline.points.count, 1)
    }

    /// No stack limit: the trendline is the chart that improves with a year of points, so
    /// there is nothing here corresponding to `defaultStackLimit`.
    func testEveryQualifyingRunIsPlottedRegardlessOfCount() {
        let candidates = (0..<200).map { candidate(dayOffset: $0, driftFraction: 0.02) }
        let selection = DriftFigureSelection(candidates: candidates)

        XCTAssertEqual(selection.trendline.points.count, 200)
        XCTAssertGreaterThan(HeartRateDriftOverlayData.defaultStackLimit, 0)
        XCTAssertGreaterThan(selection.trendline.points.count, HeartRateDriftOverlayData.defaultStackLimit)
    }

    // MARK: - Ordering

    /// Ascending by date regardless of input order, so a chart drawing the fit between
    /// `points.first` and `points.last` spans the whole interval rather than an arbitrary
    /// pair.
    func testPointsAreSortedAscendingByDateWhateverOrderTheyArriveIn() {
        let selection = DriftFigureSelection(candidates: [
            candidate(dayOffset: 90),
            candidate(dayOffset: 5),
            candidate(dayOffset: 250),
        ])

        let dates = selection.trendline.points.map(\.date)
        XCTAssertEqual(dates, dates.sorted())
    }

    // MARK: - Saying what is missing

    func testSummaryCountsPlottedRunsAgainstEveryRunInTheInterval() {
        let selection = DriftFigureSelection(candidates: [
            candidate(dayOffset: 0),
            candidate(dayOffset: 1, classification: .hard),
            candidate(dayOffset: 2, driftFraction: nil),
        ])

        XCTAssertEqual(selection.summary, "1 of 3 runs plotted")
    }

    func testSummarySingularisesASingleRun() {
        XCTAssertEqual(DriftFigureSelection(candidates: [candidate(dayOffset: 0)]).summary, "1 of 1 run plotted")
    }

    func testAnEmptyIntervalIsEmptyRatherThanZeroed() {
        let selection = DriftFigureSelection(candidates: [])

        XCTAssertTrue(selection.isEmpty)
        XCTAssertEqual(selection.candidateCount, 0)
        XCTAssertTrue(selection.exclusionNotes.isEmpty)
        XCTAssertNil(selection.trendline.fit)
    }

    /// One sentence per kind of omission, in check order, and none at all when nothing
    /// was omitted.
    func testExclusionNotesNameEachKindOfOmissionOnce() {
        let selection = DriftFigureSelection(candidates: [
            candidate(dayOffset: 0, classification: nil),
            candidate(dayOffset: 1, classification: nil),
            candidate(dayOffset: 2, classification: .hard),
            candidate(dayOffset: 3, driftFraction: nil),
        ])

        let notes = selection.exclusionNotes
        XCTAssertEqual(notes.count, 3)
        XCTAssertTrue(notes[0].hasPrefix("2 runs aren't scored yet"), notes[0])
        XCTAssertTrue(notes[1].hasPrefix("1 hard or other session"), notes[1])
        XCTAssertTrue(notes[2].hasPrefix("1 run carries no stored drift figure"), notes[2])
    }

    func testThereAreNoNotesWhenEveryRunQualifies() {
        let selection = DriftFigureSelection(candidates: [
            candidate(dayOffset: 0),
            candidate(dayOffset: 1),
        ])

        XCTAssertTrue(selection.exclusionNotes.isEmpty)
    }

    // MARK: - The fit is the shared one

    /// Built through `HeartRateDriftTrendlineData`, not a second least-squares
    /// implementation — so the year span and the shorter spans mean the same thing by "a
    /// drift trend". A rising series must fit a rising line.
    func testTheTrendlineIsTheSharedFitAndFollowsTheData() throws {
        let selection = DriftFigureSelection(candidates: [
            candidate(dayOffset: 0, driftFraction: 0.01),
            candidate(dayOffset: 10, driftFraction: 0.02),
            candidate(dayOffset: 20, driftFraction: 0.03),
        ])

        let fit = try XCTUnwrap(selection.trendline.fit)
        let first = try XCTUnwrap(selection.trendline.points.first?.date)
        let last = try XCTUnwrap(selection.trendline.points.last?.date)
        XCTAssertEqual(fit.value(at: first), 0.01, accuracy: 1e-9)
        XCTAssertEqual(fit.value(at: last), 0.03, accuracy: 1e-9)
    }

    /// Fewer than two points is not a trend — an absence a view states in a sentence
    /// rather than drawing a flat line through one dot.
    func testASingleRunProducesNoFit() {
        let selection = DriftFigureSelection(candidates: [candidate(dayOffset: 0)])

        XCTAssertEqual(selection.trendline.points.count, 1)
        XCTAssertNil(selection.trendline.fit)
    }
}

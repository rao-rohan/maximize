import Foundation
import XCTest
@testable import MaximizeCore

/// The mechanical check CHAT-FIRST-SPEC.md §3.2 (and PRD-AMENDMENTS.md A12 rule 3) asks
/// for: every fact-sheet renderer in `Context/` must format the same measurement
/// identically, because "one context module" is worthless as a guarantee if two
/// renderers are free to spell the same number two different ways. `+4.2%` against
/// `4.2 %` is exactly the divergence D3 exists to prevent, even with everything living
/// in one module — so it has to be checked, not just believed.
///
/// `WorkoutFactSheet` is, as of MAX-094, the only renderer that exists, so this test
/// pins its rendering against `FactSheetFormatting` called directly — the shared floor
/// every renderer now sits on. Passing today proves the extraction did not silently
/// reformat anything; it also fails the moment `WorkoutFactSheet` stops delegating to
/// `FactSheetFormatting` and starts formatting a figure itself again.
///
/// **This is written for MAX-095 to extend, not replace.** `TrainingFactSheet` (the
/// roll-up over many runs) is the second renderer CHAT-FIRST-SPEC.md §3.2 asks to be
/// checked against this one. To add it: build a `TrainingContext` whose per-run line
/// carries the same measurement as `figureContext()` below, add its rendered string
/// as a second entry to `renderers()`, and every `testAgreesOn…` case here starts
/// checking agreement between the two renderers for free — no new test bodies needed.
final class FactSheetFormattingAgreementTests: XCTestCase {

    // MARK: - A context carrying one fixed, known value per measurement kind

    private func day(_ text: String) throws -> CalendarDay {
        try CalendarDay(iso8601: text)
    }

    private func planCalendar() throws -> PlanCalendar {
        try PlanCalendar([Fixture.plan()])
    }

    /// One deliberately-picked value per formatter this test checks. Kept in one place
    /// so `figureContext()` and every `expected…` helper below read from the same
    /// numbers rather than each hard-coding its own.
    private enum Figure {
        static let averageHeartRateBPM = 142.0
        static let distanceMeters = 10_000.0
        static let durationSeconds = 3_600.0
        static let heartRateDriftFraction = 0.032
        static let cadenceStepsPerMinute = 167.0
        static let gradeAdjustedPaceSecondsPerKilometer = 308.0
    }

    private func metrics(distanceSplits: DistanceSplits? = nil) throws -> DerivedMetrics {
        try DerivedMetrics(
            workoutID: Fixture.workoutID,
            averageHeartRateBPM: Figure.averageHeartRateBPM,
            maximumHeartRateBPM: 161,
            timeAboveCapSeconds: 250,
            heartRateDriftFraction: Figure.heartRateDriftFraction,
            averageCadenceStepsPerMinute: Figure.cadenceStepsPerMinute,
            gradeAdjustedPaceSecondsPerKilometer: Figure.gradeAdjustedPaceSecondsPerKilometer,
            zoneSplits: ZoneSplits(splits: [ZoneSplits.Split(zone: .two, seconds: 3_000)]),
            distanceSplits: distanceSplits,
            planVersion: PlanVersion(1)
        )
    }

    /// The context every `testAgreesOn…` case renders. `TrainingContext`'s per-run line
    /// (MAX-095) should quote the same `Figure` values, so its rendering can be added as
    /// a second entry in `renderers()` and checked against the same `expected…` strings.
    private func figureContext(
        distanceSplits: DistanceSplits? = nil,
        heartRateSeries: HeartRateSeries? = nil,
        audience: WorkoutContext.Audience = .chat
    ) throws -> WorkoutContext {
        try WorkoutContextBuilder.build(
            workout: Fixture.workout(
                durationSeconds: Figure.durationSeconds,
                distanceMeters: Figure.distanceMeters
            ),
            on: day("2026-01-06"),
            metrics: metrics(distanceSplits: distanceSplits),
            classification: .easy,
            planCalendar: planCalendar(),
            audience: audience,
            heartRateSeries: heartRateSeries,
            existingScore: nil
        )
    }

    /// Every renderer's rendition of `figureContext()`, keyed by renderer name.
    /// MAX-095: append `("training", try trainingFactSheet())` here.
    private func renderers() throws -> [(name: String, sheet: String)] {
        [("workout", try figureContext().factSheet())]
    }

    private func assertEveryRendererContains(
        _ expected: String,
        because reason: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        for (name, sheet) in try renderers() {
            XCTAssertTrue(
                sheet.contains(expected),
                "\(name) renderer disagreed with FactSheetFormatting on \(reason): expected to find \"\(expected)\"",
                file: file,
                line: line
            )
        }
    }

    // MARK: - One case per shared formatter

    func testAgreesOnBPM() throws {
        try assertEveryRendererContains(
            "Average heart rate: \(FactSheetFormatting.bpm(Figure.averageHeartRateBPM))",
            because: "bpm"
        )
    }

    func testAgreesOnDistance() throws {
        try assertEveryRendererContains(
            "Distance: \(FactSheetFormatting.distance(Figure.distanceMeters))",
            because: "distance"
        )
    }

    func testAgreesOnDuration() throws {
        try assertEveryRendererContains(
            "Duration: \(FactSheetFormatting.duration(Figure.durationSeconds))",
            because: "duration"
        )
    }

    func testAgreesOnSignedPercent() throws {
        try assertEveryRendererContains(
            "Heart-rate drift: \(FactSheetFormatting.signedPercent(Figure.heartRateDriftFraction))",
            because: "signedPercent"
        )
    }

    func testAgreesOnNumber() throws {
        // Cadence is the site `number` renders at without extra decoration besides a
        // unit suffix, so it pins `number` on its own.
        try assertEveryRendererContains(
            "\(FactSheetFormatting.number(Figure.cadenceStepsPerMinute)) spm",
            because: "number"
        )
    }

    func testAgreesOnPace() throws {
        try assertEveryRendererContains(
            "\(FactSheetFormatting.pace(Figure.gradeAdjustedPaceSecondsPerKilometer)) per km",
            because: "pace"
        )
    }

    func testAgreesOnPercent() throws {
        // `percent` (unsigned) only appears on the heart-rate shape's bucket axis, so it
        // needs its own context carrying a real heart-rate series.
        let samples = try (0..<40).map { index in
            try HeartRateSample(offsetSeconds: Double(index) * 30, beatsPerMinute: 130 + Double(index) * 0.5)
        }
        let series = try HeartRateSeries(workoutID: Fixture.workoutID, samples: samples)
        let context = try figureContext(heartRateSeries: series)
        let shape = try XCTUnwrap(context.heartRateShape)
        let sheet = context.factSheet()

        for bucket in shape.buckets {
            let expected = "\(FactSheetFormatting.percent(bucket.startFraction)) "
                + "\(FactSheetFormatting.number(bucket.averageBeatsPerMinute))"
            XCTAssertTrue(
                sheet.contains(expected),
                "workout renderer disagreed with FactSheetFormatting on percent: expected \"\(expected)\" in \(sheet)"
            )
        }
    }

    /// `distance` and `pace` both appear a second time, at the pace-breakdown site
    /// (MAX-068), formatting numbers the plan/measured sections never touch — a
    /// trailing, incomplete split's own distance and pace. Worth its own case: a
    /// renderer could agree on the sections above and still diverge here.
    func testAgreesOnPaceAndDistanceForATrailingSplit() throws {
        let trailing = try DistanceSplit(ordinal: 1, distanceMeters: 420, elapsedSeconds: 150, isComplete: false)
        let distanceSplits = try DistanceSplits(series: [
            DistanceSplitSeries(unit: .kilometers, splits: [trailing]),
        ])
        let sheet = try figureContext(distanceSplits: distanceSplits, audience: .chat).factSheet()

        let expected = "final \(FactSheetFormatting.distance(trailing.distanceMeters)) "
            + "\(FactSheetFormatting.pace(trailing.paceSeconds(per: .kilometers)))"
        XCTAssertTrue(sheet.contains(expected), sheet)
    }
}

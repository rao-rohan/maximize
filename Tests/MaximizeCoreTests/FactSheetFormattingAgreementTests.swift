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
/// Each renderer pins its rendering against `FactSheetFormatting` called directly — the
/// shared floor every renderer sits on. That the workout sheet passes proves MAX-094's
/// extraction did not silently reformat anything, and it fails the moment any renderer
/// stops delegating and starts formatting a figure itself again.
///
/// **MAX-095 added the second renderer**, `TrainingFactSheet`, exactly as MAX-094 left room
/// for: one more entry in `renderers()`, and every `testAgreesOn…` case below started
/// checking both for free.
///
/// ## Why a renderer declares which sites it carries
///
/// A renderer cannot spell a figure it never prints, and §3.3 excludes four of them from
/// the training roll-up outright — measured cadence, grade-adjusted pace, the heart-rate
/// shape and the splits. So each entry names the `Site`s it renders, and each case checks
/// only the renderers that carry its site. That is a statement about the *privacy
/// boundary*, not a loophole: a renderer that quietly started carrying an excluded site
/// would still not be checked here, which is why `ContextBuilderTests` asserts the
/// exclusions directly.
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

        // The plan block's figures, which both renderers carry. `Fixture.plan()`'s own
        // values, restated here so a change to the fixture fails this test rather than
        // silently weakening it.
        static let heartRateCapBPM = 150.0
        static let cadenceBandLow = 165.0
        static let cadenceBandHigh = 170.0
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

    /// The workout renderer's subject. `trainingFigureContext()` below describes the *same*
    /// stored run through the other renderer, so every `testAgreesOn…` case compares two
    /// renderings of one set of figures rather than two separately-chosen ones.
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

    /// The training roll-up over a window containing exactly the run `figureContext()`
    /// describes, so both renderers are formatting the *same* stored figures.
    ///
    /// `Fixture.workout` starts at `Fixture.epoch` — Thursday 2026-01-01 — so the window is
    /// the Monday-first week containing it, which satisfies C1 by construction.
    private func trainingFigureContext() throws -> TrainingContext {
        let record = try ContextInputs.WorkoutRecord(
            workout: try Fixture.workout(
                durationSeconds: Figure.durationSeconds,
                distanceMeters: Figure.distanceMeters
            ),
            metrics: try metrics(),
            ledger: try ScoreLedger(automatic: try Fixture.score(points: 82))
        )
        let inputs = try ContextInputs(
            timeZone: .gmt,
            today: try day("2026-06-01"),
            planCalendar: try planCalendar(),
            restDayBudget: .standard,
            records: [record]
        )
        let scope = try TrainingScope(from: try day("2025-12-29"), through: try day("2026-01-04"))
        switch try ContextBuilder.build(for: .training(scope), from: inputs) {
        case let .training(context): return context
        case .workout: throw DomainError.inconsistent(reason: "expected a training context")
        }
    }

    /// A measurement site a fact sheet might print. Which sites a renderer carries is a
    /// product decision recorded in `Renderer.carries` below, not a convenience.
    private enum Site {
        case bpm
        case distance
        case duration
        case signedPercent
        case heartRateCap
        case cadenceBand
        /// The run's *measured* cadence — §3.3 excludes it from the roll-up.
        case measuredCadence
        /// Grade-adjusted pace — §3.3 excludes it from the roll-up.
        case gradeAdjustedPace
    }

    private struct Renderer {
        let name: String
        let sheet: String
        let carries: Set<Site>
    }

    /// Every renderer's rendition of the same stored figures. **A new renderer is one more
    /// entry here**, and every `testAgreesOn…` case starts checking it.
    private func renderers() throws -> [Renderer] {
        [
            Renderer(
                name: "workout",
                sheet: try figureContext().factSheet(),
                carries: [
                    .bpm, .distance, .duration, .signedPercent, .heartRateCap, .cadenceBand,
                    .measuredCadence, .gradeAdjustedPace,
                ]
            ),
            Renderer(
                name: "training",
                sheet: try trainingFigureContext().factSheet(),
                // No measured cadence and no grade-adjusted pace: §3.3's per-session line
                // is date, weekday, discipline, classification, the plan's ask, distance,
                // duration, average heart rate, drift, score and band — and nothing else.
                carries: [.bpm, .distance, .duration, .signedPercent, .heartRateCap, .cadenceBand]
            ),
        ]
    }

    private func assertEveryRendererContains(
        _ expected: String,
        because reason: String,
        at site: Site,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        var checked = 0
        for renderer in try renderers() where renderer.carries.contains(site) {
            checked += 1
            XCTAssertTrue(
                renderer.sheet.contains(expected),
                "\(renderer.name) renderer disagreed with FactSheetFormatting on \(reason): "
                    + "expected to find \"\(expected)\"",
                file: file,
                line: line
            )
        }
        XCTAssertGreaterThan(checked, 0, "no renderer claims to carry \(reason)", file: file, line: line)
    }

    // MARK: - One case per shared formatter

    func testAgreesOnBPM() throws {
        try assertEveryRendererContains(
            "Average heart rate: \(FactSheetFormatting.bpm(Figure.averageHeartRateBPM))",
            because: "bpm",
            at: .bpm
        )
    }

    func testAgreesOnDistance() throws {
        try assertEveryRendererContains(
            "Distance: \(FactSheetFormatting.distance(Figure.distanceMeters))",
            because: "distance",
            at: .distance
        )
    }

    func testAgreesOnDuration() throws {
        try assertEveryRendererContains(
            "Duration: \(FactSheetFormatting.duration(Figure.durationSeconds))",
            because: "duration",
            at: .duration
        )
    }

    func testAgreesOnSignedPercent() throws {
        try assertEveryRendererContains(
            "Heart-rate drift: \(FactSheetFormatting.signedPercent(Figure.heartRateDriftFraction))",
            because: "signedPercent",
            at: .signedPercent
        )
    }

    /// The plan block, which both renderers carry: an easy-run answer turns on the cap, and
    /// two spellings of it would be A12 rule 3 failing on the one number that matters most.
    func testAgreesOnTheHeartRateCap() throws {
        try assertEveryRendererContains(
            "Heart-rate cap: \(FactSheetFormatting.bpm(Figure.heartRateCapBPM))",
            because: "bpm at the plan's cap",
            at: .heartRateCap
        )
    }

    func testAgreesOnTheCadenceBand() throws {
        try assertEveryRendererContains(
            "Cadence target: \(FactSheetFormatting.number(Figure.cadenceBandLow))–"
                + "\(FactSheetFormatting.number(Figure.cadenceBandHigh)) spm",
            because: "number at the plan's cadence band",
            at: .cadenceBand
        )
    }

    /// The run's *measured* cadence — the site `number` renders at with nothing but a unit
    /// suffix. Workout-only: §3.3 keeps cadence out of the roll-up entirely.
    func testAgreesOnNumber() throws {
        try assertEveryRendererContains(
            "\(FactSheetFormatting.number(Figure.cadenceStepsPerMinute)) spm",
            because: "number",
            at: .measuredCadence
        )
    }

    func testAgreesOnPace() throws {
        try assertEveryRendererContains(
            "\(FactSheetFormatting.pace(Figure.gradeAdjustedPaceSecondsPerKilometer)) per km",
            because: "pace",
            at: .gradeAdjustedPace
        )
    }

    /// The scheduled-session formatter moved to `FactSheetFormatting` in MAX-095 because
    /// the roll-up prints a prescription on every line. Both renderers must spell the
    /// plan's ask for a day the same way.
    func testAgreesOnTheScheduledSession() throws {
        let template = try Fixture.weeklyTemplate()

        // The labels differ because the sentences differ — the workout sheet says
        // "Scheduled for this day:", the roll-up says "Planned:" on a line of its own —
        // but the formatted ask itself must not. Each is checked for the day it actually
        // describes: Tuesday 2026-01-06 for the workout, Thursday 2026-01-01 for the run
        // the roll-up's window contains.
        let workoutSheet = try figureContext().factSheet()
        let trainingSheet = try trainingFigureContext().factSheet()

        XCTAssertTrue(
            workoutSheet.contains(
                "Scheduled for this day: "
                    + FactSheetFormatting.scheduledSession(template.session(on: .tuesday, for: .run))
            ),
            workoutSheet
        )
        XCTAssertTrue(
            trainingSheet.contains(
                "Planned: " + FactSheetFormatting.scheduledSession(template.session(on: .thursday, for: .run))
            ),
            trainingSheet
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

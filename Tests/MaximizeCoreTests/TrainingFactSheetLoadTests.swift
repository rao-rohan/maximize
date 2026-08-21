import Foundation
import XCTest
@testable import MaximizeCore

/// MAX-192 — the training roll-up carries strain and load balance.
///
/// Strain (MAX-176/177) and the acute:chronic balance (MAX-178) were computed, stored and
/// drawn on a tile, and reached no prompt on the training side: a thread asked "am I
/// ramping too fast" refused, correctly under `trainingTask`'s never-invent rule, to
/// answer a question the app had already answered one tap away.
///
/// **Every assertion here pins a whole rendered line**, in `TrainingFactSheetPlanBlockTests`'
/// style and for its reason: this repository has twice had a fact-sheet field stop
/// rendering while loose `contains` probes kept passing, and a figure that silently
/// vanishes from a prompt is invisible until an answer is wrong. Negative assertions are
/// scoped to the lines they are about, because the prose that explains a figure
/// legitimately contains the words a naive whole-sheet `XCTAssertFalse` would trip on —
/// the cautionary example that file records against itself.
final class TrainingFactSheetLoadTests: XCTestCase {

    private func day(_ text: String) throws -> CalendarDay {
        try CalendarDay(iso8601: text)
    }

    private static let today = "2026-06-01"

    // MARK: - Building a window

    private func metrics(workoutID: UUID, strainPoints: Double?) throws -> DerivedMetrics {
        var strain: WorkoutStrain?
        if let strainPoints {
            strain = try WorkoutStrain(points: strainPoints)
        }
        return try DerivedMetrics(
            workoutID: workoutID,
            averageHeartRateBPM: 142,
            maximumHeartRateBPM: 160,
            timeAboveCapSeconds: 250,
            heartRateDriftFraction: 0.032,
            strain: strain,
            planVersion: PlanVersion(1)
        )
    }

    private func workout(id: UUID, on dayText: String) throws -> Workout {
        let start = try day(dayText).civilAnchor().addingTimeInterval(8 * 3_600)
        return try Workout(
            id: id,
            activityType: .running,
            start: start,
            end: start.addingTimeInterval(3_600),
            durationSeconds: 3_600,
            distanceMeters: 8_000,
            activeEnergyKilocalories: 500,
            hasRoute: true,
            source: .appleWatch,
            ingestedAt: start.addingTimeInterval(3_660)
        )
    }

    /// - Parameter sessions: `(day, strainPoints)`. A nil strain is a session with no
    ///   heart-rate curve, or one whose metrics predate MAX-176 — the two the roll-up
    ///   deliberately does not tell apart.
    private func context(
        sessions: [(day: String, strainPoints: Double?)] = [],
        loadBalance: LoadBalanceReading? = nil,
        from: String = "2026-01-05",
        through: String = "2026-01-11"
    ) throws -> TrainingContext {
        var records: [ContextInputs.WorkoutRecord] = []
        for (index, session) in sessions.enumerated() {
            // Deterministic ids so the builder's tie-break cannot reorder two sessions
            // recorded on the same day between runs of this test.
            let id = try XCTUnwrap(
                UUID(uuidString: "0000000\(index)-0000-0000-0000-00000000000\(index)")
            )
            records.append(
                try ContextInputs.WorkoutRecord(
                    workout: try workout(id: id, on: session.day),
                    metrics: try metrics(workoutID: id, strainPoints: session.strainPoints),
                    ledger: nil
                )
            )
        }
        let inputs = try ContextInputs(
            timeZone: .gmt,
            today: try day(Self.today),
            planCalendar: try PlanCalendar([Fixture.plan()]),
            restDayBudget: .standard,
            records: records,
            loadBalance: loadBalance
        )
        switch try ContextBuilder.build(
            for: .training(try TrainingScope(from: try day(from), through: try day(through))),
            from: inputs
        ) {
        case let .training(context): return context
        case .workout: throw DomainError.inconsistent(reason: "expected a training context")
        }
    }

    private func balance(
        acute: Double,
        chronic: Double,
        acuteWithoutStrain: Int = 0,
        chronicWithoutStrain: Int = 0
    ) throws -> LoadBalanceReading {
        let weekly = chronic / Double(LoadBalanceCalculator.chronicWindowDays)
            * Double(LoadBalanceCalculator.acuteWindowDays)
        return .available(
            try LoadBalance(
                anchor: try day(Self.today),
                acuteStrainPoints: acute,
                chronicStrainPoints: chronic,
                chronicWeeklyAveragePoints: weekly,
                ratio: weekly > 0 ? acute / weekly : nil,
                acuteWorkoutsWithoutStrain: acuteWithoutStrain,
                chronicWorkoutsWithoutStrain: chronicWithoutStrain
            )
        )
    }

    /// The lines of the sheet that are about load balance — everything from the figures
    /// line to the end of the tallies block. Negative assertions run against these rather
    /// than against the whole sheet.
    private func loadLines(_ sheet: String) -> [String] {
        sheet.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { $0.hasPrefix("Acute:chronic load balance") || $0.hasPrefix("Coverage:") }
    }

    /// Every rendered session line — the only lines that open with a date.
    private static func sessionLines(_ sheet: String) -> [String] {
        sheet.split(separator: "\n").map(String.init).filter { $0.hasPrefix("2026-01-") }
    }

    // MARK: - The ordinary case: a ratio

    /// 420 zone-weighted minutes this week against a 1,680-minute month, so a typical week
    /// is 420 and the ratio is exactly 1.00 — steady training, which is the reading
    /// `LoadBalanceCalculator` chose its denominator to produce.
    func testAWindowWithALoadBalanceRendersBothSumsAndTheRatio() throws {
        let sheet = try context(loadBalance: try balance(acute: 420, chronic: 1_680)).factSheet()

        XCTAssertTrue(
            sheet.contains(
                "Acute:chronic load balance as of 2026-06-01: 7-day strain 420, typical week "
                    + "over the last 28 days 420, 28-day total 1680, ratio 1.00\n"
            ),
            sheet
        )
        XCTAssertTrue(
            sheet.contains(
                "Those strain sums are in zone-weighted minutes — the unit each session "
                    + "line's strain figure below carries — and the 7-day and 28-day windows "
                    + "both end on the day named above and roll back from it. They are not "
                    + "this conversation's window: they can include sessions no line below "
                    + "describes and leave out sessions that are listed. Name that day "
                    + "whenever you quote one of these figures. The unit is unbounded, not a "
                    + "score out of 100.\n"
            ),
            sheet
        )
        XCTAssertTrue(
            sheet.contains(
                "The ratio's denominator is the 28-day total scaled to one week, not the raw "
                    + "28-day sum, so 1.00 is a week matching the athlete's recent normal, "
                    + "above it a heavier week and below it a lighter one. The app attaches no "
                    + "threshold, no band and no verdict to this figure — state it and say "
                    + "what it measures; do not call a number high, low, safe or risky.\n"
            ),
            sheet
        )
    }

    /// §3.6(c): the ratio is a figure that appears in both a tile and this sheet, so it is
    /// rendered by the tile's own formatter rather than by a second `%.2f` that could
    /// drift. 1.0842… reads "1.08" in both places or the property is a claim, not a fact.
    func testTheRatioIsRenderedAtTheTilesPrecision() throws {
        let reading = try balance(acute: 455, chronic: 1_680)
        guard case let .available(value) = reading, let ratio = value.ratio else {
            return XCTFail("the fixture is an available reading with a ratio")
        }
        let tile = try TrendTileData(
            kind: .week,
            tallies: try TalliesCalculator.compute(
                TalliesInput(
                    from: try day("2026-01-05"),
                    through: try day("2026-01-11"),
                    timeZone: .gmt,
                    today: try day(Self.today),
                    workouts: [],
                    scoreLedgers: [:],
                    planCalendar: try PlanCalendar([Fixture.plan()]),
                    restDayBudget: .standard
                )
            ),
            workouts: [],
            timeZone: .gmt,
            planCalendar: try PlanCalendar([Fixture.plan()]),
            distanceUnit: .kilometers,
            loadBalance: reading
        )

        XCTAssertEqual(tile.loadBalance.value, "1.08")
        XCTAssertEqual(TrendTileData.formattedLoadBalanceRatio(ratio), "1.08")
        XCTAssertTrue(
            try context(loadBalance: reading).factSheet().contains(", ratio 1.08\n"),
            "the sheet must quote the tile's own string"
        )
    }

    // MARK: - Coverage, when sessions carried no strain

    /// MAX-176's instruction: a 7-day sum missing two strapless runs is not the same fact
    /// as a 7-day sum of everything that happened. Both counts, and the statement that the
    /// smaller is inside the larger.
    func testSessionsWithoutStrainAreCountedRatherThanFoldedIntoTheSums() throws {
        let sheet = try context(
            loadBalance: try balance(
                acute: 420, chronic: 1_680, acuteWithoutStrain: 1, chronicWithoutStrain: 3
            )
        ).factSheet()

        XCTAssertTrue(
            sheet.contains(
                "Coverage: 1 session in the 7-day window and 3 sessions in the 28-day window "
                    + "carried no strain figure, the first count being part of the second. "
                    + "They are in neither sum — skipped, not counted as zero — so both sums "
                    + "describe less training than actually happened, and the ratio is a "
                    + "comparison of two incomplete figures.\n"
            ),
            sheet
        )
    }

    /// Silent when nothing is missing — the same "say nothing was excluded by saying
    /// nothing" rule the average-score line already keeps.
    func testAFullyCoveredWindowSaysNothingAboutCoverage() throws {
        let sheet = try context(loadBalance: try balance(acute: 420, chronic: 1_680)).factSheet()

        XCTAssertFalse(loadLines(sheet).contains { $0.hasPrefix("Coverage:") }, sheet)
    }

    // MARK: - The three absences, which are three different facts

    /// Under 28 days of history there is no ratio and no fabricated zero — the designed
    /// state `LoadBalanceReading.buildingHistory` exists to be, in the tile's own words.
    func testAShortHistoryIsBuildingLoadHistoryRatherThanARatio() throws {
        let sheet = try context(
            loadBalance: .buildingHistory(daysRecorded: 6, daysNeeded: 28)
        ).factSheet()

        XCTAssertTrue(
            sheet.contains(
                "Acute:chronic load balance: building load history — 6/28 days of the "
                    + "four-week baseline are on record. No ratio is reported until the whole "
                    + "28-day window sits inside the app's own history, because a ratio over "
                    + "days nothing observed would be a confident number about a period the "
                    + "app cannot vouch for. That is an absence of a baseline, not a light "
                    + "month.\n"
            ),
            sheet
        )
        // Scoped to the load-balance lines: the ratio-shaped words appear nowhere in them.
        XCTAssertFalse(loadLines(sheet).contains { $0.contains("ratio 0") }, sheet)
        XCTAssertFalse(loadLines(sheet).contains { $0.contains("7-day strain") }, sheet)
    }

    /// A full chronic window that carried no strain at all. **Not the same fact as a short
    /// history**: the days exist, and what is missing is a baseline to divide by.
    func testAChronicWindowWithNoStrainReportsTheAcuteSumAndWithholdsTheRatio() throws {
        let reading = LoadBalanceReading.available(
            try LoadBalance(
                anchor: try day(Self.today),
                acuteStrainPoints: 0,
                chronicStrainPoints: 0,
                chronicWeeklyAveragePoints: 0,
                ratio: nil,
                acuteWorkoutsWithoutStrain: 2,
                chronicWorkoutsWithoutStrain: 2
            )
        )
        let sheet = try context(loadBalance: reading).factSheet()

        XCTAssertTrue(
            sheet.contains(
                "Acute:chronic load balance as of 2026-06-01: 7-day strain 0 zone-weighted "
                    + "minutes. There is no four-week baseline to compare it against — nothing "
                    + "in the 28 days ending that day carried a strain figure, either because "
                    + "no session did or because none happened — so no ratio is reported. "
                    + "Dividing by that baseline would be dividing by zero, which is why it is "
                    + "withheld rather than shown as a large number.\n"
            ),
            sheet
        )
        // The denominator sentence is about a ratio, and there is no ratio here.
        XCTAssertFalse(sheet.contains("The ratio's denominator"), sheet)
        // …and this is emphatically not the short-history state.
        XCTAssertFalse(sheet.contains("building load history"), sheet)
    }

    /// A caller that supplied no reading. A fact about this record, not about the
    /// athlete's history — so it must not borrow `.buildingHistory`'s sentence.
    func testAnUnsuppliedReadingSaysSoRatherThanClaimingAShortHistory() throws {
        let sheet = try context(loadBalance: nil).factSheet()

        XCTAssertTrue(
            sheet.contains(
                "Acute:chronic load balance: not carried in this summary. The app measures "
                    + "one, and it is not in this record — say so rather than estimating one "
                    + "from the sessions below.\n"
            ),
            sheet
        )
        XCTAssertFalse(sheet.contains("building load history"), sheet)
        XCTAssertFalse(loadLines(sheet).contains { $0.contains("ratio") }, sheet)
    }

    /// The three absences are three sentences, and no two of them are the same sentence.
    func testTheThreeLoadAbsencesAreWordedApart() throws {
        let unsupplied = loadLines(try context(loadBalance: nil).factSheet())
        let short = loadLines(
            try context(loadBalance: .buildingHistory(daysRecorded: 6, daysNeeded: 28)).factSheet()
        )
        let noBaseline = loadLines(
            try context(
                loadBalance: .available(
                    try LoadBalance(
                        anchor: try day(Self.today),
                        acuteStrainPoints: 0,
                        chronicStrainPoints: 0,
                        chronicWeeklyAveragePoints: 0,
                        ratio: nil,
                        acuteWorkoutsWithoutStrain: 0,
                        chronicWorkoutsWithoutStrain: 0
                    )
                )
            ).factSheet()
        )

        XCTAssertNotEqual(unsupplied, short)
        XCTAssertNotEqual(unsupplied, noBaseline)
        XCTAssertNotEqual(short, noBaseline)
    }

    // MARK: - MAX-178's no-verdict rule, held at the prompt boundary

    /// `LoadBalanceCalculator` grades nothing and `TrendTileData` honours that
    /// (`testLoadBalanceTilesNeverEditorialise`). The same rule reaches here — but the
    /// scan is **scoped to the lines that carry the figures**, because the sentence
    /// beside them contains "high", "low", "safe" and "risky" precisely in order to
    /// forbid them. A whole-block scan would fail the sentence that enforces the rule,
    /// which is the shape of mistake `TrainingFactSheetPlanBlockTests` records against
    /// itself.
    ///
    /// Whole words, not substrings: "below" is not a verdict, and a substring scan for
    /// "low" would say it was.
    func testTheLinesCarryingTheFiguresNeverEditorialise() throws {
        let readings: [LoadBalanceReading?] = [
            nil,
            .buildingHistory(daysRecorded: 6, daysNeeded: 28),
            try balance(acute: 900, chronic: 1_200, acuteWithoutStrain: 2, chronicWithoutStrain: 3),
        ]
        let verdicts = [
            "high", "low", "risk", "risky", "dangerous", "overtraining", "overtrained",
            "safe", "excessive", "healthy", "concerning",
        ]

        for reading in readings {
            let sheet = try context(loadBalance: reading).factSheet()
            for line in loadLines(sheet) {
                let words = Set(
                    line.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
                )
                for verdict in verdicts {
                    XCTAssertFalse(words.contains(verdict), "\"\(verdict)\" grades the figure: \(line)")
                }
            }
        }
    }

    // MARK: - The window sentence no longer over-claims

    /// The opening sentence said every figure below was measured over exactly the window's
    /// days. That became false the moment a rolling figure was carried, and a prompt whose
    /// framing contradicts a figure four lines down is worse than either alone.
    func testTheWindowSentenceNamesTheRollingException() throws {
        let sheet = try context(loadBalance: try balance(acute: 420, chronic: 1_680)).factSheet()

        XCTAssertTrue(
            sheet.contains(
                "Every figure below is measured over exactly these days, except the "
                    + "acute:chronic load balance, which is measured over its own rolling "
                    + "windows and says so where it appears."
            ),
            sheet
        )
    }

    // MARK: - Per-muscle fatigue: excluded, and the exclusion stated

    /// MAX-192 decided against carrying MAX-179's six figures and says so in the prompt.
    /// Silence would not have been neutral: the plan block names the muscle groups the
    /// plan *prescribes*, so a model with a list of lifts and no sentence like this one
    /// can assemble a recovery narrative out of an ask and a duration.
    func testPerMuscleRecoveryIsExcludedAndTheExclusionIsStated() throws {
        let sheet = try context(
            sessions: [(day: "2026-01-06", strainPoints: 120)],
            loadBalance: try balance(acute: 420, chronic: 1_680)
        ).factSheet()

        XCTAssertTrue(
            sheet.contains(
                "Per-muscle recovery is not in this summary. The app estimates one from the "
                    + "strength sessions the athlete has tagged with muscle groups, and it is "
                    + "read on the muscle map rather than here — so say it is not in front of "
                    + "you rather than inferring which muscles are recovered from the sessions "
                    + "below. It would not settle the question anyway: nothing in this app "
                    + "records sets, reps or weight.\n"
            ),
            sheet
        )
        // No group carries a figure, and none carries a zero either — a never-logged group
        // has no reading, and rendering one as 0 would be the lie MAX-175 forbids.
        for group in MuscleGroup.allCases {
            XCTAssertFalse(
                sheet.contains("\(group.rawValue): 0"),
                "\(group.rawValue) has a fatigue figure in the sheet — \(sheet)"
            )
        }
    }

    // MARK: - Strain, per session line

    /// A window mixing sessions that carry strain with sessions that do not. The figure is
    /// on the line where it exists, the field is **absent** where it does not, and nowhere
    /// does a zero stand in for a missing measurement.
    func testAMixedWindowCarriesStrainOnlyOnTheLinesThatHaveIt() throws {
        let sheet = try context(
            sessions: [
                (day: "2026-01-06", strainPoints: 138),
                (day: "2026-01-07", strainPoints: nil),
            ],
            loadBalance: try balance(acute: 420, chronic: 1_680)
        ).factSheet()

        // Pinned whole, and pinned as the *complete* set of session lines: a field that
        // stops rendering fails here rather than slipping past a `contains` probe aimed
        // at the half of the line that still works.
        XCTAssertEqual(
            Self.sessionLines(sheet),
            [
                "2026-01-06 (Tuesday) · Running, not yet classified · Planned: easy, 8.0 km · "
                    + "Distance: 8.00 km · Duration: 1h 0m 0s · Average heart rate: 142 bpm · "
                    + "Heart-rate drift: +3.2% · Strain: 138 · Score: no verdict yet — this "
                    + "session has not been scored",
                "2026-01-07 (Wednesday) · Running, not yet classified · Planned: hard, "
                    + "(6 × 800m) · Distance: 8.00 km · Duration: 1h 0m 0s · Average heart "
                    + "rate: 142 bpm · Heart-rate drift: +3.2% · Score: no verdict yet — this "
                    + "session has not been scored",
            ],
            sheet
        )
        // Scoped to the session lines: "Strain" appears in the preamble that explains the
        // unit, so a whole-sheet negative would be the mistake this file's header warns
        // about. What must not exist is a *line* claiming a session cost nothing.
        XCTAssertFalse(Self.sessionLines(sheet).contains { $0.contains("Strain: 0") }, sheet)
    }

    /// The preamble carries the unit and both of the figure's limits once, rather than
    /// each of up to 200 lines carrying them — this file's inverted absence convention,
    /// applied to the one field where a missing value would read as a real zero.
    func testTheSessionPreambleStatesTheUnitTheLimitsAndTheAbsence() throws {
        let sheet = try context(
            sessions: [(day: "2026-01-06", strainPoints: 138)],
            loadBalance: try balance(acute: 420, chronic: 1_680)
        ).factSheet()

        XCTAssertTrue(
            sheet.contains(
                "Strain, where a line carries one, is that session's stored figure in "
                    + "zone-weighted minutes: unbounded, not a score out of 100. A bigger "
                    + "number can mean a longer session, a harder one, or both, and it does "
                    + "not distinguish them. It is measured from heart rate alone, so on a "
                    + "lift it says nothing about sets, reps or weight — nothing in this app "
                    + "records those. A line with no strain figure has none stored, either "
                    + "because the session has no heart-rate curve or because its metrics "
                    + "predate the figure; that is not a session that cost nothing.\n"
            ),
            sheet
        )
    }

    /// A window whose sessions all lack strain renders no strain field at all, and the
    /// preamble still explains what that means. The absence is the record's, not the
    /// athlete's — the app cannot tell whether those sessions were easy or brutal.
    func testAWindowWithNoStrainAtAllRendersNoStrainField() throws {
        let sheet = try context(
            sessions: [(day: "2026-01-06", strainPoints: nil)],
            loadBalance: try balance(acute: 420, chronic: 1_680)
        ).factSheet()

        XCTAssertEqual(Self.sessionLines(sheet).count, 1, sheet)
        XCTAssertFalse(Self.sessionLines(sheet).contains { $0.contains("Strain:") }, sheet)
        XCTAssertTrue(sheet.contains("Strain, where a line carries one,"), sheet)
    }

    // MARK: - The anchor is checked, not assumed

    /// The sheet prints the reading's anchor as the day the load figures describe, so a
    /// reading anchored to some other day would put a true number under a false heading.
    /// `ContextInputs` refuses it at assembly, where it cannot yet have reached a prompt.
    func testAReadingAnchoredToAnotherDayIsRefused() throws {
        XCTAssertThrowsError(
            try ContextInputs(
                timeZone: .gmt,
                today: try day(Self.today),
                planCalendar: try PlanCalendar([Fixture.plan()]),
                restDayBudget: .standard,
                records: [],
                loadBalance: .available(
                    try LoadBalance(
                        anchor: try day("2026-05-30"),
                        acuteStrainPoints: 420,
                        chronicStrainPoints: 1_680,
                        chronicWeeklyAveragePoints: 420,
                        ratio: 1,
                        acuteWorkoutsWithoutStrain: 0,
                        chronicWorkoutsWithoutStrain: 0
                    )
                )
            )
        )
    }

    /// `.buildingHistory` carries no anchor to check, and must still be accepted.
    func testAShortHistoryReadingNeedsNoAnchorCheck() throws {
        XCTAssertNoThrow(
            try ContextInputs(
                timeZone: .gmt,
                today: try day(Self.today),
                planCalendar: try PlanCalendar([Fixture.plan()]),
                restDayBudget: .standard,
                records: [],
                loadBalance: .buildingHistory(daysRecorded: 3, daysNeeded: 28)
            )
        )
    }
}

import Foundation
import XCTest
@testable import MaximizeCore

/// CHAT-FIRST-SPEC.md §4.6, MAX-101: the proposal card's contents.
///
/// The diff is the affordance that makes an unrequested change visible — §4.6's own
/// worked example is a model asked to drop Thursday to 6 km that *also* moves the cap to
/// 148, and the whole argument is that the second edit must be one highlighted row rather
/// than one line among fourteen. So the tests that matter here are: the requested change
/// shows, the unrequested one shows, and the fields nobody touched do not.
final class PlanProposalReviewTests: XCTestCase {

    // MARK: - Fixtures

    /// The stored plan every revision test diffs against: cap 152, Thursday 8 km easy,
    /// Sunday 18 km long, a three-week arc, and two lift days.
    private func storedPlan() throws -> Plan {
        try Plan(
            version: PlanVersion(3),
            effectiveFrom: Fixture.day(2026, 6, 1),
            weeklyTemplate: Fixture.weeklyTemplate(lift: [
                .tuesday: ScheduledSession(kind: .lift, muscleGroups: [.legs]),
                .friday: ScheduledSession(kind: .lift, muscleGroups: [.chest, .back]),
            ]),
            longRunArc: LongRunArc(weeks: [
                LongRunArc.Week(index: 1, distanceMeters: 16_000),
                LongRunArc.Week(index: 2, distanceMeters: 18_000),
                LongRunArc.Week(index: 3, distanceMeters: 20_000),
            ]),
            heartRateCapBPM: 152,
            cadenceTarget: CadenceBand(lowStepsPerMinute: 165, highStepsPerMinute: 170),
            rubric: Fixture.rubric(),
            goals: PlanGoals(statements: ["Run a sub-4:00 marathon"], targetDay: Fixture.day(2026, 4, 20))
        )
    }

    private func revisionSession() throws -> PlanAuthoringSession {
        try PlanAuthoring.session(
            revising: try PlanCalendar([try storedPlan()]),
            today: try Fixture.day(2026, 8, 5)
        )
    }

    private func firstPlanSession() throws -> PlanAuthoringSession {
        try PlanAuthoring.session(revising: nil, today: try Fixture.day(2026, 8, 5))
    }

    /// The stored plan's arc, as the JSON a proposal restating it would carry.
    private static let storedArc =
        #"[{"index": 1, "distanceMeters": 16000}, {"index": 2, "distanceMeters": 18000}, {"index": 3, "distanceMeters": 20000}]"#

    /// A proposal that restates the stored plan exactly, lift days included — Tuesday's
    /// and Friday's default to `storedPlan()`'s own asks, so the "nothing changes"
    /// baseline tests stay true once the lift slot is diffable too (MAX-141). Every diff
    /// test below is this, with one thing changed, so a failing assertion names the
    /// difference.
    private func reply(
        heartRateCapBPM: String = "152",
        cadenceLow: String = "165",
        cadenceHigh: String = "170",
        effective: String = "70",
        marginal: String = "45",
        thursday: String = #"{"weekday": "thursday", "kind": "easy", "distanceMeters": 8000, "liftKind": "rest"}"#,
        tuesday: String =
            #"{"weekday": "tuesday", "kind": "easy", "distanceMeters": 8000, "liftKind": "lift", "liftMuscleGroups": ["legs"]}"#,
        friday: String =
            #"{"weekday": "friday", "kind": "rest", "liftKind": "lift", "liftMuscleGroups": ["chest", "back"]}"#,
        longRunArc: String = PlanProposalReviewTests.storedArc,
        goalStatements: String = #"["Run a sub-4:00 marathon"]"#,
        goalTargetDay: String = #""2026-04-20""#
    ) -> String {
        let week = [
            #"{"weekday": "monday", "kind": "rest", "liftKind": "rest"}"#,
            tuesday,
            #"{"weekday": "wednesday", "kind": "hard", "note": "6 × 800m", "liftKind": "rest"}"#,
            thursday,
            friday,
            #"{"weekday": "saturday", "kind": "easy", "distanceMeters": 6000, "liftKind": "rest"}"#,
            #"{"weekday": "sunday", "kind": "long", "distanceMeters": 18000, "liftKind": "rest"}"#,
        ]
        return """
        {
          "heartRateCapBPM": \(heartRateCapBPM),
          "cadenceLowStepsPerMinute": \(cadenceLow),
          "cadenceHighStepsPerMinute": \(cadenceHigh),
          "effectiveThresholdPoints": \(effective),
          "marginalThresholdPoints": \(marginal),
          "week": [\(week.joined(separator: ", "))],
          "longRunArc": \(longRunArc),
          "goalStatements": \(goalStatements),
          "goalTargetDay": \(goalTargetDay)
        }
        """
    }

    private func card(
        _ raw: String,
        session: PlanAuthoringSession? = nil,
        unit: DistanceUnit = .kilometers
    ) throws -> PlanProposalReview {
        try PlanProposalReview.build(
            applying: try PlanProposal.parse(raw),
            to: session ?? (try revisionSession()),
            distanceUnit: unit
        )
    }

    private func field(_ id: String, in review: PlanProposalReview) throws -> PlanProposalReview.Row {
        let match = review.sections.flatMap(\.rows).first { $0.id == id }
        return try XCTUnwrap(match, "no row with id \(id)")
    }

    // MARK: - A first plan states, it does not diff

    /// §4.6: "For a first plan there is nothing to diff against, so the card renders the
    /// plan itself." Notably it is **not** diffed against `StandardPlanSeed` — the
    /// athlete has never seen those numbers, so "changed from 150 bpm" would compare
    /// against a value they never chose.
    func testAFirstPlanCardStatesEveryRowAndFlagsNoChanges() throws {
        let review = try card(reply(), session: try firstPlanSession())

        XCTAssertEqual(review.standing, .firstPlan)
        XCTAssertFalse(review.isRevision)
        XCTAssertEqual(review.changedRowCount, 0)
        XCTAssertEqual(review.headline, "Proposed plan")
        XCTAssertEqual(review.summary, "No plan is in force yet, so this is the whole of it.")

        for row in review.sections.flatMap(\.rows) {
            XCTAssertEqual(row.change, .stated, "\(row.id) should state rather than diff")
            XCTAssertNil(row.change.marker)
            XCTAssertFalse(row.value.isEmpty)
        }
    }

    // MARK: - The revision case, which is the interesting one

    /// A proposal restating the plan already in force changes nothing, and the card says
    /// so rather than highlighting fourteen rows because the strings were rebuilt.
    func testARestatementOfThePlanInForceShowsNoChanges() throws {
        let review = try card(reply())

        XCTAssertTrue(review.isRevision)
        XCTAssertEqual(review.changedRowCount, 0)
        XCTAssertEqual(
            review.summary,
            "Nothing changes against plan v3, in effect since 1 Jun 2026."
        )
        XCTAssertEqual(review.headline, "Proposed revision of plan v3")
    }

    /// §4.6's worked example, whole: "drop Thursday to 6 km" is what was asked for, and
    /// the cap moving to 148 is what was not. Both are rows; nothing else is.
    func testTheAskedForChangeAndTheUnrequestedOneAreBothOneRowEach() throws {
        let review = try card(reply(
            heartRateCapBPM: "148",
            thursday: #"{"weekday": "thursday", "kind": "easy", "distanceMeters": 6000, "liftKind": "rest"}"#
        ))

        XCTAssertEqual(review.changedRowCount, 2)
        XCTAssertEqual(
            Set(review.changedRows.map(\.id)),
            ["heartRateCap", "week.thursday"]
        )
        XCTAssertEqual(review.summary, "2 changes against plan v3, in effect since 1 Jun 2026.")

        let cap = try field("heartRateCap", in: review)
        XCTAssertEqual(cap.value, "148 bpm")
        XCTAssertEqual(cap.change, .changed(from: "152 bpm"))
        XCTAssertEqual(cap.change.marker, "Changed")
        XCTAssertEqual(cap.spokenDescription, "Heart-rate cap: changed from 152 bpm to 148 bpm")

        let thursday = try field("week.thursday", in: review)
        XCTAssertEqual(thursday.label, "Thursday")
        XCTAssertEqual(thursday.value, "Easy run · 6.0 km")
        XCTAssertEqual(thursday.change, .changed(from: "Easy run · 8.0 km"))
    }

    /// The count is singular when there is one change — the summary is read at a glance
    /// and "1 changes" reads as a bug in the app.
    func testOneChangeReadsAsOneChange() throws {
        let review = try card(reply(cadenceLow: "170", cadenceHigh: "178"))

        XCTAssertEqual(review.changedRowCount, 1)
        XCTAssertEqual(review.summary, "One change against plan v3, in effect since 1 Jun 2026.")
        XCTAssertEqual(
            try field("cadence", in: review).change,
            .changed(from: "165–170 spm")
        )
    }

    func testThresholdChangesAreTheirOwnRows() throws {
        let review = try card(reply(effective: "75", marginal: "50"))

        XCTAssertEqual(review.changedRowCount, 2)
        XCTAssertEqual(try field("effectiveThreshold", in: review).change, .changed(from: "70"))
        XCTAssertEqual(try field("marginalThreshold", in: review).change, .changed(from: "45"))
    }

    /// The week is seven rows, Monday-first, always — a day nobody changed still appears,
    /// because the card states the plan as well as its diff (§4.6).
    func testTheWeekIsSevenRowsMondayFirst() throws {
        let review = try card(reply())
        let week = try XCTUnwrap(review.sections.first { $0.id == "week" })

        XCTAssertEqual(week.title, "The week")
        XCTAssertEqual(
            week.rows.map(\.label),
            ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        )
        XCTAssertEqual(week.rows.first?.value, "Rest")
        XCTAssertEqual(week.rows.last?.value, "Long run · 18.0 km")
    }

    // MARK: - The arc

    /// A lengthened arc: the new week is `.added`, not `.changed(from:)`, because there
    /// was nothing there to change.
    func testAnArcWeekThePlanDidNotHaveIsMarkedNew() throws {
        let lengthened =
            #"[{"index": 1, "distanceMeters": 16000}, {"index": 2, "distanceMeters": 18000}, {"index": 3, "distanceMeters": 20000}, {"index": 4, "distanceMeters": 22000}]"#
        let review = try card(reply(longRunArc: lengthened))

        let week4 = try field("arc.4", in: review)
        XCTAssertEqual(week4.change, .added)
        XCTAssertEqual(week4.change.marker, "New")
        XCTAssertEqual(week4.value, "22.0 km")
        XCTAssertEqual(week4.spokenDescription, "Week 4: new, 22.0 km")
        XCTAssertEqual(try field("arc.length", in: review).change, .changed(from: "3 weeks"))
    }

    /// A shortened arc does not silently lose its last weeks: a sixteen-week block
    /// quietly becoming twelve is exactly the edit the diff exists to surface.
    func testAnArcWeekTheProposalDropsIsStillShown() throws {
        let shortened = #"[{"index": 1, "distanceMeters": 16000}, {"index": 2, "distanceMeters": 18000}]"#
        let review = try card(reply(longRunArc: shortened))

        let week3 = try field("arc.3", in: review)
        XCTAssertEqual(week3.value, "No longer in the arc")
        XCTAssertEqual(week3.change, .changed(from: "20.0 km"))
        XCTAssertEqual(try field("arc.length", in: review).change, .changed(from: "3 weeks"))
    }

    // MARK: - Goals

    func testGoalsAndTargetDayAreRowsWithDesignedAbsenceStrings() throws {
        let review = try card(reply(goalStatements: "[]", goalTargetDay: "null"))

        XCTAssertEqual(try field("goals.statements", in: review).value, "None stated")
        XCTAssertEqual(
            try field("goals.statements", in: review).change,
            .changed(from: "Run a sub-4:00 marathon")
        )
        XCTAssertEqual(try field("goals.targetDay", in: review).value, "None stated")
        XCTAssertEqual(
            try field("goals.targetDay", in: review).change,
            .changed(from: "20 Apr 2026")
        )
    }

    // MARK: - Lifts are a diffable section now (MAX-141)

    /// The ticket's own requirement, met a different way than before: *"someone who says
    /// 'and lift on Tuesdays' must not be told yes by omission."* A proposal can now
    /// prescribe a lift, so a lift change shows up exactly the way a run change does — a
    /// `.changed` row in its own section — rather than a fixed sentence the athlete has
    /// to trust separately from what the card shows.
    func testALiftChangeIsAChangedRowInTheLiftSection() throws {
        let review = try card(reply(
            tuesday: #"{"weekday": "tuesday", "kind": "easy", "distanceMeters": 8000, "liftKind": "lift", "liftMuscleGroups": ["legs", "core"]}"#
        ))

        let tuesday = try field("lift.tuesday", in: review)
        XCTAssertEqual(tuesday.label, "Tuesday")
        XCTAssertEqual(tuesday.value, "Lift · Legs, Core")
        XCTAssertEqual(tuesday.change, .changed(from: "Lift · Legs"))
        XCTAssertEqual(review.changedRowCount, 1)
    }

    /// Dropping a lift day the athlete has — the model silently not restating it — is
    /// exactly as visible as any other unrequested edit: a `.changed` row from what the
    /// lift was to "Rest". This is the property `PlanDraft.applying(_:)`'s own doc
    /// points at: the athlete's proof that nothing changed is the diff, not a sentence.
    func testDroppingAnExistingLiftDayIsAVisibleChange() throws {
        let review = try card(reply(
            tuesday: #"{"weekday": "tuesday", "kind": "easy", "distanceMeters": 8000, "liftKind": "rest"}"#
        ))

        let tuesday = try field("lift.tuesday", in: review)
        XCTAssertEqual(tuesday.value, "Rest")
        XCTAssertEqual(tuesday.change, .changed(from: "Lift · Legs"))
        XCTAssertEqual(tuesday.change.marker, "Changed")
    }

    /// The lift section reads the same way the week section does: seven rows, Monday
    /// first, stating every weekday's ask rather than only the ones with a lift on them.
    func testTheLiftSectionIsSevenRowsMondayFirst() throws {
        let review = try card(reply())
        let lifts = try XCTUnwrap(review.sections.first { $0.id == "lift" })

        XCTAssertEqual(lifts.title, "Lifts")
        XCTAssertEqual(
            lifts.rows.map(\.label),
            ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        )
        XCTAssertEqual(lifts.rows.first?.value, "Rest")
        XCTAssertEqual(try field("lift.tuesday", in: review).value, "Lift · Legs")
        XCTAssertEqual(try field("lift.friday", in: review).value, "Lift · Chest, Back")
    }

    /// A first plan states the lift section the same way it states every other one —
    /// there is nothing to diff against, so every row is `.stated`.
    func testALiftSectionOnAFirstPlanStatesRatherThanDiffs() throws {
        let review = try card(reply(), session: try firstPlanSession())
        let lifts = try XCTUnwrap(review.sections.first { $0.id == "lift" })

        for row in lifts.rows {
            XCTAssertEqual(row.change, .stated)
        }
    }

    // MARK: - Units

    /// Distances read in the athlete's own unit (MAX-047); storage stays metric, and the
    /// diff compares what is displayed — see `PlanProposalReview.row(id:label:...)`.
    func testDistancesRenderInTheAthletesUnit() throws {
        let review = try card(reply(), unit: .miles)

        XCTAssertEqual(try field("arc.1", in: review).value, "9.9 mi")
        XCTAssertEqual(try field("week.sunday", in: review).value, "Long run · 11.2 mi")
        // Unit is a display preference, so it does not by itself make anything a change.
        XCTAssertEqual(review.changedRowCount, 0)
    }

    // MARK: - What the card promises before it is tapped

    /// The boundary, stated on the card rather than only in the code: accepting opens a
    /// form, and discarding leaves the plan in force alone (§4.10, A13).
    func testTheCardSaysNothingIsSavedUntilTheAthleteSavesIt() {
        XCTAssertTrue(PlanProposalReview.acceptExplanation.contains("Nothing is saved"))
        XCTAssertTrue(PlanProposalReview.acceptExplanation.contains("plan editor"))
        XCTAssertTrue(PlanProposalReview.discardExplanation.contains("exactly as it is"))
    }

    /// Row identity is stable across two builds of the same card, so a `ForEach` does not
    /// re-identify every row when one value moves.
    func testRowIdentityIsStableAcrossBuilds() throws {
        let first = try card(reply())
        let second = try card(reply(heartRateCapBPM: "148"))

        XCTAssertEqual(
            first.sections.flatMap(\.rows).map(\.id),
            second.sections.flatMap(\.rows).map(\.id)
        )
    }
}

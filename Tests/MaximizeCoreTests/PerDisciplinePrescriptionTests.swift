import XCTest
@testable import MaximizeCore

/// MAX-129 / A17: the prescription is indexed by discipline, in one plan record under
/// one version.
///
/// The acceptance criterion LIFTING-SPEC §2.3 asks for by name is here — **a plan
/// payload written before this change decodes to a plan whose every lift slot is rest
/// and whose run slots are unchanged**, with no migration and no historical score
/// becoming irreproducible.
final class PerDisciplinePrescriptionTests: XCTestCase {

    // MARK: - The no-op decode

    /// A `WeeklyTemplate` payload exactly as a pre-MAX-129 build wrote it: seven
    /// entries, each with a `weekday` and a `session`, and no lift slot anywhere.
    ///
    /// Written out by hand rather than derived from today's encoder, because deriving it
    /// would let a bug in the encoder cancel out a matching bug in the decoder and the
    /// test would still pass. These are the bytes on the device.
    private static let preLiftingWeeklyTemplateJSON = """
        {"entries":[\
        {"session":{"kind":"rest"},"weekday":1},\
        {"session":{"distanceMeters":8000,"kind":"easy"},"weekday":2},\
        {"session":{"kind":"hard","note":"6 × 800m"},"weekday":3},\
        {"session":{"distanceMeters":8000,"kind":"easy"},"weekday":4},\
        {"session":{"kind":"rest"},"weekday":5},\
        {"session":{"distanceMeters":6000,"kind":"easy"},"weekday":6},\
        {"session":{"distanceMeters":18000,"kind":"long"},"weekday":7}\
        ]}
        """

    func testPreLiftingTemplatePayloadDecodesToRestOnEveryLiftSlot() throws {
        let data = try XCTUnwrap(Self.preLiftingWeeklyTemplateJSON.data(using: .utf8))
        let decoded = try PersistencePayload.decode(
            WeeklyTemplate.self,
            from: data,
            field: "test.weeklyTemplate"
        )

        // The run half, unchanged — every weekday, not a spot check.
        XCTAssertEqual(decoded, try Fixture.weeklyTemplate())

        // The lift half: rest everywhere, which is what "this plan prescribed no
        // lifting" always meant. Totality is preserved rather than restored.
        for weekday in Weekday.allCases {
            XCTAssertEqual(
                decoded.session(on: weekday, for: .lift),
                .rest,
                "\(weekday)'s lift slot must decode to rest, not to a missing key"
            )
        }
        XCTAssertEqual(decoded.scheduledLiftCount, 0)

        // And the encode direction: a template that prescribes no lifting writes no key
        // this ticket added, so what goes back to disk is what was already there.
        //
        // Asserted as key absence rather than as a byte-for-byte match against the
        // literal above, because CI is Linux and swift-corelibs-foundation is entitled
        // to render a `Double` differently from Darwin. Pinning that would be pinning
        // the JSON writer, which is not what this ticket changed.
        let reEncoded = try XCTUnwrap(
            String(
                data: try PersistencePayload.encode(decoded, field: "test.weeklyTemplate"),
                encoding: .utf8
            )
        )
        XCTAssertFalse(reEncoded.contains("liftSession"))
        XCTAssertFalse(reEncoded.contains("muscleGroups"))
        XCTAssertTrue(reEncoded.contains("\"session\""), "the run slot keeps its key")
    }

    /// The whole plan record, not just the template: version, effective date, arc, HR
    /// cap, cadence band, rubric and goals all survive the round trip untouched, and the
    /// only thing the missing keys cost is the lifting the old payload never carried.
    ///
    /// Built by taking a plan that *does* prescribe lifts and deleting the keys MAX-129
    /// added, which is precisely the shape of a payload written before it — rather than
    /// starting from a lift-free plan, where the deletion would be a no-op and the test
    /// would prove nothing.
    func testPreLiftingPlanPayloadRoundTripsToAnIdenticalPlan() throws {
        let withLifts = try Self.plan(lift: [
            .tuesday: try ScheduledSession(kind: .lift, note: "Upper", muscleGroups: [.chest, .back]),
            .friday: try ScheduledSession(kind: .lift, muscleGroups: [.legs, .core]),
        ])
        let asWrittenBefore = try Self.stripLiftingKeys(
            from: PersistencePayload.encode(withLifts, field: "test.plan")
        )

        let decoded = try PersistencePayload.decode(
            Plan.self,
            from: asWrittenBefore,
            field: "test.plan"
        )
        XCTAssertEqual(decoded, try Self.plan(), "everything but the lifting, unchanged")
        XCTAssertEqual(decoded.weeklyTemplate.scheduledLiftCount, 0)
        XCTAssertEqual(decoded.weeklyTemplate.scheduledRunCount, 5)
    }

    /// The claim stated as a property of the encoder rather than of one fixture: for a
    /// plan that prescribes no lifting, **this build writes the bytes the previous build
    /// wrote**. Rest and absent are the same statement (A17), so the shorter form is the
    /// one that goes to disk. `liftSession` and `muscleGroups` are the only keys this
    /// ticket adds anywhere on the wire, so their absence *is* byte-identity — and it
    /// keeps `PersistencePayload`'s "an unchanged value re-encodes to identical bytes".
    func testALiftFreePlanEncodesToExactlyThePreLiftingBytes() throws {
        let encoded = try PersistencePayload.encode(try Fixture.plan(), field: "test.plan")
        let text = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertFalse(text.contains("liftSession"))
        XCTAssertFalse(text.contains("muscleGroups"))

        // And a `Score`'s stored prescription, which is a `ScheduledSession` of its own
        // and is immutable under D8, is untouched for the same reason: a session with no
        // muscle groups writes no key for them, so no stored score's bytes move.
        let session = try PersistencePayload.encode(
            try ScheduledSession(kind: .easy, distanceMeters: 8_000),
            field: "test.session"
        )
        XCTAssertFalse(
            try XCTUnwrap(String(data: session, encoding: .utf8)).contains("muscleGroups")
        )
    }

    /// D1, restated as a test: the same workout under a pre-change plan and under the
    /// same plan decoded by this build matches the same rubric band. LIFTING-SPEC §2.3
    /// names this as MAX-129's second acceptance criterion.
    func testTheSameWorkoutMatchesTheSameBandUnderAPreLiftingPlan() throws {
        let plan = try ScoringFixture.plan()
        let asWrittenBefore = try Self.stripLiftingKeys(
            from: PersistencePayload.encode(plan, field: "test.plan")
        )
        let reloaded = try PersistencePayload.decode(
            Plan.self,
            from: asWrittenBefore,
            field: "test.plan"
        )

        let workout = try Fixture.workout()
        let day = try CalendarDay(iso8601: ScoringFixture.easyDay)
        func evaluation(under plan: Plan) throws -> RubricEvaluation {
            try RubricEvaluator.evaluate(
                WorkoutContextBuilder.build(
                    workout: workout,
                    on: day,
                    metrics: try ScoringFixture.metrics(),
                    classification: .easy,
                    planCalendar: try PlanCalendar([plan]),
                    audience: .scoring,
                    existingScore: nil
                )
            )
        }

        let before = try evaluation(under: reloaded)
        let after = try evaluation(under: plan)
        XCTAssertEqual(before.band.identifier, after.band.identifier)
        XCTAssertEqual(before.scheduledSession, after.scheduledSession)
        XCTAssertEqual(before.permittedScores, after.permittedScores)
    }

    /// Resolution, not just decoding. Four weeks of days resolved from a pre-change
    /// payload against the same four weeks resolved from a plan this build authored:
    /// same run ask on every day, arc substitution included, since that is the one place
    /// the resolver rewrites the template. This is the sentence "no behaviour changes
    /// for a run", made checkable.
    func testResolvedRunAsksAreUnchangedAcrossTheChange() throws {
        let withLifts = try Self.plan(lift: [
            .tuesday: try ScheduledSession(kind: .lift, muscleGroups: [.chest]),
        ])
        let reloaded = try PersistencePayload.decode(
            Plan.self,
            from: try Self.stripLiftingKeys(
                from: PersistencePayload.encode(withLifts, field: "test.plan")
            ),
            field: "test.plan"
        )

        let before = try PlanCalendar([reloaded])
        let after = try PlanCalendar([try Self.plan()])
        let from = try Fixture.day(2026, 1, 1)
        let through = try Fixture.day(2026, 1, 28)

        let beforeDays = try before.planDays(from: from, through: through)
        let afterDays = try after.planDays(from: from, through: through)
        XCTAssertEqual(beforeDays.count, 28)
        XCTAssertEqual(beforeDays.map(\.scheduledSession), afterDays.map(\.scheduledSession))
        XCTAssertEqual(beforeDays.map(\.canBeMissed), afterDays.map(\.canBeMissed))
        XCTAssertTrue(beforeDays.allSatisfy { $0.liftSession == .rest })
    }

    /// `Fixture.plan()`'s week and arc, with the lift slot under the caller's control.
    private static func plan(lift: [Weekday: ScheduledSession] = [:]) throws -> Plan {
        try Plan(
            version: PlanVersion(1),
            effectiveFrom: Fixture.day(2026, 1, 1),
            weeklyTemplate: Fixture.weeklyTemplate(lift: lift),
            longRunArc: LongRunArc(weeks: [
                LongRunArc.Week(index: 1, distanceMeters: 16_000),
                LongRunArc.Week(index: 2, distanceMeters: 18_000),
                LongRunArc.Week(index: 3, distanceMeters: 20_000),
            ]),
            heartRateCapBPM: 150,
            cadenceTarget: CadenceBand(lowStepsPerMinute: 165, highStepsPerMinute: 170),
            rubric: Fixture.rubric(),
            goals: PlanGoals(
                statements: ["Run a sub-4:00 marathon"],
                targetDay: Fixture.day(2026, 4, 20)
            )
        )
    }

    /// Removes every key MAX-129 adds to the wire, turning a payload this build wrote
    /// into the payload the previous build would have written for the same plan.
    ///
    /// Recursive and key-name-based rather than a string edit, so it cannot half-remove
    /// a nested object.
    private static func stripLiftingKeys(from data: Data) throws -> Data {
        func strip(_ value: Any) -> Any {
            if let object = value as? [String: Any] {
                var stripped: [String: Any] = [:]
                for (key, nested) in object where key != "liftSession" && key != "muscleGroups" {
                    stripped[key] = strip(nested)
                }
                return stripped
            }
            if let array = value as? [Any] {
                return array.map(strip)
            }
            return value
        }
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return try JSONSerialization.data(
            withJSONObject: strip(object),
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
    }

    // MARK: - Two slots, and totality in both arguments

    func testPlanDayCarriesBothAsksAndResolvesThemByDiscipline() throws {
        let plan = try Plan(
            version: PlanVersion(1),
            effectiveFrom: try Fixture.day(2026, 1, 1),
            weeklyTemplate: try Fixture.weeklyTemplate(lift: [
                .tuesday: try ScheduledSession(
                    kind: .lift,
                    note: "45 minutes",
                    muscleGroups: [.chest, .shoulders]
                ),
            ]),
            longRunArc: try LongRunArc(weeks: [LongRunArc.Week(index: 1, distanceMeters: 16_000)]),
            heartRateCapBPM: 150,
            cadenceTarget: try CadenceBand(lowStepsPerMinute: 165, highStepsPerMinute: 170),
            rubric: try Fixture.rubric()
        )
        let calendar = try PlanCalendar([plan])

        // 2026-01-06 is a Tuesday: an easy 8 km *and* a lift. The normal case.
        let tuesday = try XCTUnwrap(try calendar.planDay(on: try Fixture.day(2026, 1, 6)))
        XCTAssertEqual(tuesday.scheduledSession(for: .run).kind, .easy)
        XCTAssertEqual(tuesday.scheduledSession(for: .run).distanceMeters, 8_000)
        XCTAssertEqual(tuesday.scheduledSession(for: .lift).kind, .lift)
        XCTAssertEqual(tuesday.scheduledSession(for: .lift).muscleGroups, [.chest, .shoulders])

        // The unqualified property is the run ask, and agrees with the accessor.
        XCTAssertEqual(tuesday.scheduledSession, tuesday.scheduledSession(for: .run))

        // Total in both arguments across the whole week: never nil, never a throw.
        for day in try CalendarDay.days(from: try Fixture.day(2026, 1, 5), through: try Fixture.day(2026, 1, 11)) {
            let planDay = try XCTUnwrap(try calendar.planDay(on: day))
            for discipline in Discipline.allCases {
                _ = planDay.scheduledSession(for: discipline)
            }
        }

        // Monday prescribes neither. Rest is an answer on both slots, not a gap.
        let monday = try XCTUnwrap(try calendar.planDay(on: try Fixture.day(2026, 1, 5)))
        XCTAssertTrue(monday.scheduledSession(for: .run).isRest)
        XCTAssertTrue(monday.scheduledSession(for: .lift).isRest)
    }

    /// There is no lifting arc (A17, LIFTING-SPEC §4.2), so nothing substitutes a
    /// distance into a lift slot even when the slot says `.long` — which only a
    /// hand-built template can say, and is exactly why the resolver guards on the
    /// discipline rather than trusting that it never will.
    func testTheLongRunArcNeverReachesTheLiftSlot() throws {
        let plan = try Plan(
            version: PlanVersion(1),
            effectiveFrom: try Fixture.day(2026, 1, 1),
            weeklyTemplate: try Fixture.weeklyTemplate(lift: [
                .sunday: try ScheduledSession(kind: .long, distanceMeters: 1_000),
            ]),
            longRunArc: try LongRunArc(weeks: [LongRunArc.Week(index: 1, distanceMeters: 16_000)]),
            heartRateCapBPM: 150,
            cadenceTarget: try CadenceBand(lowStepsPerMinute: 165, highStepsPerMinute: 170),
            rubric: try Fixture.rubric()
        )
        let sunday = try XCTUnwrap(
            try PlanCalendar([plan]).planDay(on: try Fixture.day(2026, 1, 4))
        )
        XCTAssertEqual(sunday.scheduledSession.distanceMeters, 16_000, "the run slot takes the arc")
        XCTAssertEqual(sunday.liftSession.distanceMeters, 1_000, "the lift slot keeps its own ask")
    }

    // MARK: - One plan, one version (D1)

    /// A17's second property: a day resolves to exactly one plan version, whichever
    /// discipline you ask about. There is no second calendar and no version pair.
    func testBothAsksComeFromOneVersion() throws {
        let first = try Fixture.plan(version: 1)
        let second = try Plan(
            version: PlanVersion(2),
            effectiveFrom: try Fixture.day(2026, 2, 1),
            weeklyTemplate: try Fixture.weeklyTemplate(lift: [
                .tuesday: try ScheduledSession(kind: .lift, muscleGroups: [.legs]),
            ]),
            longRunArc: try LongRunArc(weeks: [LongRunArc.Week(index: 1, distanceMeters: 16_000)]),
            heartRateCapBPM: 150,
            cadenceTarget: try CadenceBand(lowStepsPerMinute: 165, highStepsPerMinute: 170),
            rubric: try Fixture.rubric()
        )
        let calendar = try PlanCalendar([first, second])

        let january = try XCTUnwrap(try calendar.planDay(on: try Fixture.day(2026, 1, 6)))
        XCTAssertEqual(january.planVersion, try PlanVersion(1))
        XCTAssertTrue(january.liftSession.isRest, "version 1 prescribed no lifting")

        let february = try XCTUnwrap(try calendar.planDay(on: try Fixture.day(2026, 2, 3)))
        XCTAssertEqual(february.planVersion, try PlanVersion(2))
        XCTAssertEqual(february.liftSession.muscleGroups, [.legs])
    }

    // MARK: - Storage

    func testAStoredPlanRoundTripsBothSlots() throws {
        let template = try Fixture.weeklyTemplate(lift: [
            .monday: try ScheduledSession(kind: .lift, note: "Push", muscleGroups: [.chest, .shoulders, .arms]),
            .thursday: try ScheduledSession(kind: .lift, note: "Pull", muscleGroups: [.back, .arms]),
            .saturday: try ScheduledSession(kind: .lift, muscleGroups: [.legs, .core]),
        ])
        let plan = try Plan(
            version: PlanVersion(3),
            effectiveFrom: try Fixture.day(2026, 3, 2),
            weeklyTemplate: template,
            longRunArc: try LongRunArc(weeks: [LongRunArc.Week(index: 1, distanceMeters: 16_000)]),
            heartRateCapBPM: 150,
            cadenceTarget: try CadenceBand(lowStepsPerMinute: 165, highStepsPerMinute: 170),
            rubric: try Fixture.rubric()
        )

        let restored = try StoredPlan(plan).toDomain()
        XCTAssertEqual(restored, plan)
        XCTAssertEqual(restored.weeklyTemplate.scheduledLiftCount, 3)
        XCTAssertEqual(
            restored.weeklyTemplate.session(on: .monday, for: .lift).muscleGroups,
            [.chest, .shoulders, .arms]
        )
    }

    /// A `Set` has no order, and the bytes must not inherit that. Two plans that
    /// prescribe the same groups in different source order must encode identically,
    /// or an unchanged prescription would look changed on every write.
    func testMuscleGroupsEncodeInACanonicalOrder() throws {
        func encoded(_ groups: Set<MuscleGroup>) throws -> Data {
            try PersistencePayload.encode(
                try ScheduledSession(kind: .lift, muscleGroups: groups),
                field: "test.session"
            )
        }
        let one = try encoded([.shoulders, .chest, .arms])
        let other = try encoded([.arms, .chest, .shoulders])
        XCTAssertEqual(one, other)

        let text = try XCTUnwrap(String(data: one, encoding: .utf8))
        XCTAssertTrue(
            text.contains("[\"chest\",\"shoulders\",\"arms\"]"),
            "expected MuscleGroup.allCases order, got \(text)"
        )
    }

    // MARK: - Authoring carries the lift slot forward

    /// `PlanDraft.init(_:)` is documented as lossless, and the lift slot is the first
    /// field that could have made that untrue. A revision that dropped it would delete
    /// a lifting prescription the next time the athlete changed their HR cap — and A17
    /// leans on this carry-forward when it argues for one plan record rather than two.
    func testARevisionCarriesTheLiftSlotForwardVerbatim() throws {
        let stored = try Plan(
            version: PlanVersion(1),
            effectiveFrom: try Fixture.day(2026, 1, 1),
            weeklyTemplate: try Fixture.weeklyTemplate(lift: [
                .tuesday: try ScheduledSession(kind: .lift, note: "Upper", muscleGroups: [.chest, .back]),
                .friday: try ScheduledSession(kind: .lift, muscleGroups: [.legs]),
            ]),
            longRunArc: try LongRunArc(weeks: [LongRunArc.Week(index: 1, distanceMeters: 16_000)]),
            heartRateCapBPM: 150,
            cadenceTarget: try CadenceBand(lowStepsPerMinute: 165, highStepsPerMinute: 170),
            rubric: try Fixture.rubric()
        )
        let session = try PlanAuthoring.session(
            revising: try PlanCalendar([stored]),
            today: try Fixture.day(2026, 2, 1)
        )

        // The athlete changes one unrelated number and saves.
        var draft = session.draft
        draft.heartRateCapBPM = 148
        let revised = try session.plan(from: draft, effectiveFrom: try Fixture.day(2026, 2, 2))

        XCTAssertEqual(revised.heartRateCapBPM, 148)
        XCTAssertEqual(revised.weeklyTemplate, stored.weeklyTemplate, "both slots, verbatim")
    }
}

/// The vocabulary a lift prescription is written in (owner's scope addition to
/// MAX-129). Nothing here reaches scoring — see `MuscleGroup`'s note on verification.
final class MuscleGroupTests: XCTestCase {

    /// The list's stated test: a week's worth of lifts, written the ways lifting weeks
    /// are actually written, with no reach for a residual case.
    func testCommonWeeklySplitsAreExpressible() throws {
        let pushPullLegs: [Set<MuscleGroup>] = [
            [.chest, .shoulders, .arms],
            [.back, .arms],
            [.legs, .core],
        ]
        let upperLower: [Set<MuscleGroup>] = [
            [.chest, .back, .shoulders, .arms],
            [.legs, .core],
        ]
        for split in pushPullLegs + upperLower {
            XCTAssertFalse(split.isEmpty)
            XCTAssertNoThrow(try ScheduledSession(kind: .lift, muscleGroups: split))
        }
        XCTAssertEqual(MuscleGroup.fullBody.count, MuscleGroup.allCases.count)
    }

    /// **Rest and "a lift with no groups named" are different statements**, and the
    /// type keeps them different. Collapsing them would make "no lifting on Tuesday"
    /// and "lift on Tuesday, groups unstated" the same day.
    func testNoLiftPrescribedIsDistinctFromALiftWithNoGroupsNamed() throws {
        let noLift = ScheduledSession.rest
        let unstated = try ScheduledSession(kind: .lift)

        XCTAssertTrue(noLift.isRest)
        XCTAssertFalse(unstated.isRest)
        XCTAssertNotEqual(noLift, unstated)
        XCTAssertTrue(unstated.muscleGroups.isEmpty)
    }

    /// A value that cannot mean anything for a kind is not storable on it — the same
    /// rule, and the same reason, as a rest day being unable to carry a distance.
    func testOnlyALiftCanPrescribeMuscleGroups() {
        for kind in ScheduledSessionKind.allCases where kind != .lift {
            assertThrows(
                .inconsistent,
                try ScheduledSession(kind: kind, muscleGroups: [.chest]),
                "\(kind) must not be able to prescribe a muscle group"
            )
        }
        XCTAssertNoThrow(try ScheduledSession(kind: .lift, muscleGroups: [.chest]))
    }

    func testOrderingIsCaseIterableOrderAndDropsNothing() {
        XCTAssertEqual(MuscleGroup.fullBody.ordered, MuscleGroup.allCases)
        XCTAssertEqual(Set<MuscleGroup>().ordered, [])
        XCTAssertEqual(Set<MuscleGroup>([.legs, .chest]).ordered, [.chest, .legs])
    }

    /// Raw values are wire format. Renaming one silently reinterprets every stored
    /// prescription, so they are pinned here rather than left to a refactor.
    func testRawValuesArePinned() {
        XCTAssertEqual(
            MuscleGroup.allCases.map(\.rawValue),
            ["chest", "back", "shoulders", "arms", "legs", "core"]
        )
    }
}

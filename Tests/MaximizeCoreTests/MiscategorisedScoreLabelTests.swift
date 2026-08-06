import Foundation
import XCTest
import MaximizeCoreTestSupport
@testable import MaximizeCore

/// MAX-143 / A21: an auto-score written against the wrong discipline's rubric is
/// **labelled**, not corrected.
///
/// The owner's decision was to label. That splits into three claims this file has to
/// prove, and one it has to prove did *not* happen:
///
/// 1. **Additive.** The stored auto-score is not modified, deleted or rescored — asserted
///    on the encoded bytes, not on a value comparison, because "byte-identical" is what
///    D8 actually promises.
/// 2. **Excluded from the scorer-quality metric.** `ScoreLedger.divergence` is where PRD
///    §2's correction-rate signal is computed, and a labelled score is not evidence about
///    the scorer. An unlabelled one still is.
/// 3. **Still visible in history.** Nothing here removes a score, changes its value, its
///    band or its rationale, and `wasCorrected` still reports the athlete's correction.
///
/// And the no-op: a payload written before this ticket decodes to exactly what it meant,
/// with no labels, and re-encodes without the key this ticket added — the property
/// MAX-129, MAX-131 and MAX-133 each established for their own wire change.
final class MiscategorisedScoreLabelTests: XCTestCase {

    // MARK: - Fixtures

    private static let labelID = UUID(uuidString: "A1A1A1A1-A1A1-A1A1-A1A1-A1A1A1A1A1A1") ?? UUID()
    private static let secondLabelID = UUID(uuidString: "B2B2B2B2-B2B2-B2B2-B2B2-B2B2B2B2B2B2") ?? UUID()

    /// A lift as the pre-lifting build scored it: judged against the day's **easy-run**
    /// ask, matched `easy.wellOverCap`, and permanently recorded at 32 (A21's 20–45 case).
    private static func liftScoredAsARun(
        workoutID: UUID = Fixture.workoutID
    ) throws -> Score {
        try Score(
            workoutID: workoutID,
            planVersion: PlanVersion(1),
            scheduledSession: ScheduledSession(kind: .easy, distanceMeters: 8_000),
            actualClassification: .other,
            value: ScoreValue(32),
            effectiveThreshold: ScoreValue(70),
            band: .ineffective,
            rubricBandIdentifier: "easy.wellOverCap",
            rationale: "Well above the easy cap for the whole run.",
            scoredAt: Fixture.epoch
        )
    }

    /// The same session judged against the day's **lift** ask, as MAX-133 routes it now.
    private static func liftScoredAsALift(
        workoutID: UUID = Fixture.workoutID
    ) throws -> Score {
        try Score(
            workoutID: workoutID,
            planVersion: PlanVersion(1),
            scheduledSession: ScheduledSession(kind: .lift, durationSeconds: 2_700),
            actualClassification: .lift,
            value: ScoreValue(88),
            effectiveThreshold: ScoreValue(70),
            band: .effective,
            rubricBandIdentifier: "lift.metTheAsk",
            rationale: "Lifted the full prescribed session.",
            scoredAt: Fixture.epoch
        )
    }

    private static func label(
        for score: Score,
        id: UUID = MiscategorisedScoreLabelTests.labelID,
        at offsetSeconds: Double = 3_600
    ) throws -> MiscategorisedScoreLabel {
        try MiscategorisedScoreLabel(
            id: id,
            workoutID: score.workoutID,
            judgedAgainst: score.scheduledSession.kind,
            actualDiscipline: .lift,
            recordedAt: Fixture.at(offsetSeconds)
        )
    }

    // MARK: - The rule

    /// The detection, in all four directions. A lift shown a run ask is the case that
    /// actually exists on devices; the others are what stop the rule from over-reaching.
    func testAScoreIsMiscategorisedOnlyWhenItsAskBelongsToAnotherDiscipline() throws {
        let liftAsRun = try Self.liftScoredAsARun()
        XCTAssertTrue(
            MiscategorisedScoreLabel.isMiscategorised(liftAsRun, workoutDiscipline: .lift),
            "a lift judged against the easy-run ask is the case A21 is about"
        )

        let liftAsLift = try Self.liftScoredAsALift()
        XCTAssertFalse(
            MiscategorisedScoreLabel.isMiscategorised(liftAsLift, workoutDiscipline: .lift),
            "a lift judged against the lift ask was asked the right question"
        )

        XCTAssertFalse(
            MiscategorisedScoreLabel.isMiscategorised(liftAsRun, workoutDiscipline: .run),
            "a run judged against a run ask is every score this app has ever written for a run"
        )
        XCTAssertTrue(
            MiscategorisedScoreLabel.isMiscategorised(liftAsLift, workoutDiscipline: .run),
            "the rule is symmetric even though nothing has ever written a lift ask into the run slot"
        )
    }

    /// `.rest` names no discipline, so a score judged against one cannot be labelled — and
    /// nothing is lost by that, because the old evaluator and the new one resolve such a
    /// day to the same ask. See `MiscategorisedScoreLabel`'s note.
    func testAScoreJudgedAgainstRestIsNeverMiscategorised() throws {
        let onARestDay = try Score(
            workoutID: Fixture.workoutID,
            planVersion: PlanVersion(1),
            scheduledSession: .rest,
            actualClassification: .other,
            value: ScoreValue(55),
            effectiveThreshold: ScoreValue(70),
            band: .marginal,
            rubricBandIdentifier: "fallback.recorded",
            rationale: "Recorded, on a day the plan asked for nothing.",
            scoredAt: Fixture.epoch
        )

        XCTAssertFalse(
            MiscategorisedScoreLabel.isMiscategorised(onARestDay, workoutDiscipline: .lift)
        )
        XCTAssertNil(
            MiscategorisedScoreLabel.labelling(
                onARestDay,
                workoutDiscipline: .lift,
                id: Self.labelID,
                recordedAt: Fixture.at(3_600)
            )
        )
        XCTAssertNil(ScheduledSessionKind.rest.slotDiscipline)
    }

    /// A label is a claim with grounds. One whose two disciplines agree would quietly pull
    /// a score out of the scorer-quality metric, which is the one thing this mechanism
    /// must never become a way to do.
    func testALabelWhoseDisciplinesAgreeIsRejected() {
        assertThrows(
            .inconsistent,
            try MiscategorisedScoreLabel(
                id: Self.labelID,
                workoutID: Fixture.workoutID,
                judgedAgainst: .lift,
                actualDiscipline: .lift,
                recordedAt: Fixture.at(3_600)
            )
        )
        assertThrows(
            .inconsistent,
            try MiscategorisedScoreLabel(
                id: Self.labelID,
                workoutID: Fixture.workoutID,
                judgedAgainst: .rest,
                actualDiscipline: .lift,
                recordedAt: Fixture.at(3_600)
            )
        )
    }

    /// `labelling` is the only mint, and it never produces a record the throwing
    /// initializer would have refused.
    func testLabellingCopiesTheAskTheScoreRecords() throws {
        let score = try Self.liftScoredAsARun()
        let label = try XCTUnwrap(
            MiscategorisedScoreLabel.labelling(
                score,
                workoutDiscipline: .lift,
                id: Self.labelID,
                recordedAt: Fixture.at(3_600)
            )
        )

        XCTAssertEqual(label.id, Self.labelID)
        XCTAssertEqual(label.workoutID, score.workoutID)
        XCTAssertEqual(label.judgedAgainst, .easy)
        XCTAssertEqual(label.actualDiscipline, .lift)
        XCTAssertEqual(label.recordedAt, Fixture.at(3_600))
    }

    // MARK: - The exclusion (PRD §2)

    /// **The point of the ticket.** The scorer-quality metric is computed in
    /// `ScoreLedger.divergence`, and a labelled score does not contribute to it. An
    /// otherwise identical unlabelled score does.
    func testALabelledScoreIsExcludedFromTheScorerQualityMetricAndAnUnlabelledOneIsNot() throws {
        let score = try Self.liftScoredAsARun()
        let correction = try Fixture.annotation(points: 85, at: 7_200)

        let unlabelled = try ScoreLedger(automatic: score, annotations: [correction])
        XCTAssertEqual(unlabelled.divergence, 53, "85 − 32: a real disagreement with the scorer")
        XCTAssertTrue(unlabelled.countsTowardScorerQuality)
        XCTAssertFalse(unlabelled.isMiscategorised)

        let labelled = try unlabelled.labelled(with: Self.label(for: score))
        XCTAssertNil(
            labelled.divergence,
            "the model was handed a category error; the gap measures the question, not the scorer"
        )
        XCTAssertFalse(labelled.countsTowardScorerQuality)
        XCTAssertTrue(labelled.isMiscategorised)
    }

    /// The athlete's record is not rewritten. The correction still happened, still drives
    /// the tallies' `effectiveValue`, and is still reported — only its use as *evidence
    /// about the scorer* is withdrawn.
    func testLabellingWithdrawsTheEvidenceWithoutErasingTheCorrection() throws {
        let score = try Self.liftScoredAsARun()
        let labelled = try ScoreLedger(
            automatic: score,
            annotations: [try Fixture.annotation(points: 85, at: 7_200)],
            labels: [try Self.label(for: score)]
        )

        XCTAssertTrue(labelled.wasCorrected)
        XCTAssertEqual(labelled.effectiveValue, try ScoreValue(85))
        XCTAssertTrue(labelled.isEffective)
        XCTAssertEqual(labelled.currentAnnotation?.manualScore, try ScoreValue(85))
    }

    /// Still visible in history: nothing about the score itself moves. The value, the
    /// band, the rationale, the matched rubric band and the prescription it was judged
    /// against all read exactly as before.
    func testALabelledScoreKeepsEverythingItSaid() throws {
        let score = try Self.liftScoredAsARun()
        let labelled = try ScoreLedger(automatic: score).labelled(with: Self.label(for: score))

        XCTAssertEqual(labelled.automatic, score)
        XCTAssertEqual(labelled.automatic.value, try ScoreValue(32))
        XCTAssertEqual(labelled.automatic.band, .ineffective)
        XCTAssertEqual(labelled.automatic.rationale, "Well above the easy cap for the whole run.")
        XCTAssertEqual(labelled.automatic.rubricBandIdentifier, "easy.wellOverCap")
        XCTAssertEqual(labelled.automatic.scheduledSession.kind, .easy)
        XCTAssertEqual(labelled.effectiveValue, try ScoreValue(32))
        XCTAssertEqual(labelled.miscategorisationLabel?.id, Self.labelID)
    }

    /// A second label says nothing new, and costs nothing: labelling is a property of the
    /// set, not a count. The duplicate case is real — two devices running the pass before
    /// either has synced — and `ScoreLedger` resolves it the way `WorkoutRepository`
    /// resolves a duplicate workout, deterministically rather than by refusing.
    func testAScoreLabelledTwiceDoesNotDoubleCount() throws {
        let score = try Self.liftScoredAsARun()
        let once = try ScoreLedger(automatic: score).labelled(with: Self.label(for: score))
        let twice = try once.labelled(
            with: Self.label(for: score, id: Self.secondLabelID, at: 10_800)
        )

        XCTAssertEqual(twice.labels.count, 2)
        XCTAssertTrue(twice.isMiscategorised)
        XCTAssertFalse(twice.countsTowardScorerQuality)
        XCTAssertNil(twice.divergence)
        XCTAssertEqual(
            twice.miscategorisationLabel?.id,
            Self.labelID,
            "the earliest label is the one in force; a later duplicate does not supersede it"
        )
        XCTAssertEqual(twice.automatic, once.automatic)
    }

    /// A label states the ask the score was judged against. If the two disagree, one of
    /// them is describing a different score, and trusting either would drop a real
    /// divergence out of PRD §2's signal.
    func testALedgerRejectsALabelThatContradictsTheScore() throws {
        let score = try Self.liftScoredAsARun()
        assertThrows(
            .inconsistent,
            try ScoreLedger(
                automatic: score,
                labels: [
                    try MiscategorisedScoreLabel(
                        id: Self.labelID,
                        workoutID: score.workoutID,
                        judgedAgainst: .long,
                        actualDiscipline: .lift,
                        recordedAt: Fixture.at(3_600)
                    )
                ]
            )
        )
    }

    func testALedgerRejectsALabelForAnotherWorkout() throws {
        let score = try Self.liftScoredAsARun()
        assertThrows(
            .inconsistent,
            try ScoreLedger(
                automatic: score,
                labels: [
                    try MiscategorisedScoreLabel(
                        id: Self.labelID,
                        workoutID: Fixture.otherWorkoutID,
                        judgedAgainst: .easy,
                        actualDiscipline: .lift,
                        recordedAt: Fixture.at(3_600)
                    )
                ]
            )
        )
    }

    func testALedgerRejectsLabelsOutOfOrder() throws {
        let score = try Self.liftScoredAsARun()
        assertThrows(
            .outOfOrder,
            try ScoreLedger(
                automatic: score,
                labels: [
                    try Self.label(for: score, id: Self.labelID, at: 10_800),
                    try Self.label(for: score, id: Self.secondLabelID, at: 3_600),
                ]
            )
        )
    }

    // MARK: - D8: nothing stored moves

    /// **Byte-identical, asserted on the bytes.** The stored auto-score is what D8
    /// protects, and `StoredScore` is the shape it is stored in — every column, and the
    /// `ScheduledSession` blob inside it, before and after labelling.
    func testTheStoredAutoScoreIsByteIdenticalBeforeAndAfterLabelling() throws {
        let score = try Self.liftScoredAsARun()
        let before = try StoredScore(score)

        let ledger = try ScoreLedger(automatic: score).labelled(with: Self.label(for: score))
        let after = try StoredScore(ledger.automatic)

        XCTAssertEqual(before, after)
        XCTAssertEqual(
            before.scheduledSessionJSON,
            after.scheduledSessionJSON,
            "the prescription the score was judged against is the blob D8 makes permanent"
        )
        XCTAssertEqual(
            try PersistencePayload.encode(score, field: "test.score"),
            try PersistencePayload.encode(ledger.automatic, field: "test.score")
        )
    }

    /// A `ScoreLedger` payload exactly as a pre-MAX-143 build wrote it: `automatic` and
    /// `annotations`, and no `labels` key anywhere.
    ///
    /// Written out by hand rather than derived from today's encoder, for MAX-129's reason:
    /// deriving it would let a bug in the encoder cancel a matching bug in the decoder and
    /// the test would still pass. These are the bytes on the device.
    private static let preLabellingLedgerJSON = """
        {"annotations":[],"automatic":{\
        "actualClassification":"other",\
        "band":"ineffective",\
        "effectiveThreshold":70,\
        "planVersion":1,\
        "rationale":"Well above the easy cap for the whole run.",\
        "rubricBandIdentifier":"easy.wellOverCap",\
        "scheduledSession":{"distanceMeters":8000,"kind":"easy"},\
        "scoredAt":788918400,\
        "value":32,\
        "workoutID":"11111111-1111-1111-1111-111111111111"\
        }}
        """

    func testAPreLabellingLedgerPayloadDecodesUnchanged() throws {
        let data = try XCTUnwrap(Self.preLabellingLedgerJSON.data(using: .utf8))
        let decoded = try PersistencePayload.decode(
            ScoreLedger.self,
            from: data,
            field: "test.scoreLedger"
        )

        XCTAssertEqual(decoded.automatic, try Self.liftScoredAsARun(), "the score, untouched")
        XCTAssertTrue(decoded.annotations.isEmpty)
        XCTAssertTrue(decoded.labels.isEmpty, "absent means unlabelled, which is what it meant")
        XCTAssertFalse(decoded.isMiscategorised)
        XCTAssertTrue(
            decoded.countsTowardScorerQuality,
            "an unlabelled score is still evidence about the scorer; nothing is excluded by default"
        )
    }

    /// The encode direction: an unlabelled ledger writes **no key this ticket added**, so
    /// what goes back to disk is what was already there.
    ///
    /// Asserted as key absence rather than a byte-for-byte match against the literal
    /// above, for MAX-129's reason: CI is Linux and swift-corelibs-foundation is entitled
    /// to render a `Double` differently from Darwin, and pinning that would be pinning the
    /// JSON writer rather than this ticket's change.
    func testAnUnlabelledLedgerEncodesToExactlyThePreLabellingBytes() throws {
        let ledger = try ScoreLedger(
            automatic: try Self.liftScoredAsARun(),
            annotations: [try Fixture.annotation(points: 85, at: 7_200)]
        )
        let text = try XCTUnwrap(
            String(
                data: try PersistencePayload.encode(ledger, field: "test.scoreLedger"),
                encoding: .utf8
            )
        )

        XCTAssertFalse(text.contains("labels"))
        XCTAssertTrue(text.contains("\"annotations\""), "the annotations keep their key")
        XCTAssertTrue(text.contains("\"automatic\""))
    }

    /// And a labelled ledger round-trips whole, so the exclusion survives storage.
    func testALabelledLedgerRoundTrips() throws {
        let score = try Self.liftScoredAsARun()
        let ledger = try ScoreLedger(
            automatic: score,
            annotations: [try Fixture.annotation(points: 85, at: 7_200)],
            labels: [try Self.label(for: score)]
        )

        let data = try PersistencePayload.encode(ledger, field: "test.scoreLedger")
        let decoded = try PersistencePayload.decode(
            ScoreLedger.self,
            from: data,
            field: "test.scoreLedger"
        )

        XCTAssertEqual(decoded, ledger)
        XCTAssertNil(decoded.divergence)
        XCTAssertTrue(decoded.wasCorrected)
    }

    // MARK: - Storage

    func testStoredLabelRoundTripsUnchanged() throws {
        let score = try Self.liftScoredAsARun()
        let label = try Self.label(for: score)
        XCTAssertEqual(try StoredMiscategorisedScoreLabel(label).toDomain(), label)
    }

    /// Both enums are closed, so an unrecognised raw value is a corrupted record. Failing
    /// loudly matters more here than usual: a label that decoded to nothing would silently
    /// return its score to the scorer-quality metric.
    func testStoredLabelWithUnknownRawValuesIsRejected() throws {
        var stored = StoredMiscategorisedScoreLabel(try Self.label(for: try Self.liftScoredAsARun()))
        stored.judgedAgainstRawValue = "sprints"
        assertThrows(.malformed, try stored.toDomain())

        var other = StoredMiscategorisedScoreLabel(try Self.label(for: try Self.liftScoredAsARun()))
        other.actualDisciplineRawValue = "swim"
        assertThrows(.malformed, try other.toDomain())
    }

    /// Storage must not be a way around the domain's rule that a label states grounds.
    func testStoredLabelWhoseDisciplinesAgreeFailsToDecode() throws {
        let stored = StoredMiscategorisedScoreLabel(
            labelUUID: Self.labelID,
            workoutUUID: Fixture.workoutID,
            judgedAgainstRawValue: ScheduledSessionKind.lift.rawValue,
            actualDisciplineRawValue: Discipline.lift.rawValue,
            recordedAt: Fixture.at(3_600)
        )
        assertThrows(.inconsistent, try stored.toDomain())
    }

    // MARK: - How it presents

    /// The presentation decision, pinned: **the score is shown, and a sentence explains
    /// it.** Nothing is hidden, no number moves, and the wording never promises the
    /// correction D8 forbids or calls the label a correction — which is the distinction
    /// the whole ticket rests on.
    ///
    /// Pinned here for `ChatConversationCopy`'s reason: two surfaces will render this (the
    /// verdict header and the calendar's VoiceOver sentence), and a string edited in one
    /// of them is two voices on one app.
    func testTheLabelExplainsItselfWithoutPromisingACorrection() {
        for line in [
            MiscategorisedScoreCopy.labelledDetail,
            MiscategorisedScoreCopy.labelledAccessibilitySuffix,
        ] {
            XCTAssertFalse(line.isEmpty)
            XCTAssertFalse(line.contains("\n"), "one line — the verdict header's layout contract")
            XCTAssertTrue(
                line.lowercased().contains("distinguished lifting"),
                "the label says *why* the score is wrong, which is the only thing it can offer"
            )
            XCTAssertFalse(
                line.lowercased().contains("correct"),
                "a correction is the athlete's record and a different thing entirely"
            )
        }
    }

    // MARK: - MAX-160: the average's own copy

    func testAverageExclusionNoteIsNilWhenNothingWasExcluded() {
        XCTAssertNil(MiscategorisedScoreCopy.averageExclusionNote(excludedCount: 0))
    }

    func testAverageExclusionNoteNamesTheCountAndPluralisesCorrectly() {
        XCTAssertEqual(
            MiscategorisedScoreCopy.averageExclusionNote(excludedCount: 1),
            "excludes 1 score from before the plan distinguished lifting"
        )
        XCTAssertEqual(
            MiscategorisedScoreCopy.averageExclusionNote(excludedCount: 2),
            "excludes 2 scores from before the plan distinguished lifting"
        )
    }

    /// Same voice discipline as `labelledDetail`: says what happened, not what the
    /// athlete did wrong, and never promises the correction D8 forbids.
    func testTheOnlyExcludedScoresLineExplainsItselfWithoutPromisingACorrection() {
        for count in [1, 2] {
            let line = MiscategorisedScoreCopy.onlyExcludedScoresAverageLine(excludedCount: count)
            XCTAssertFalse(line.isEmpty)
            XCTAssertFalse(line.contains("\n"))
            XCTAssertTrue(line.hasPrefix("Average score:"))
            XCTAssertTrue(line.lowercased().contains("distinguished lifting"))
            XCTAssertFalse(
                line.lowercased().contains("nothing in this window has been scored"),
                "this is a different absence from the ordinary unscored one"
            )
        }
    }

    // MARK: - The pass

    private static func lift(
        id: UUID,
        startingAt offsetSeconds: Double = 0
    ) throws -> Workout {
        try Workout(
            id: id,
            activityType: .traditionalStrengthTraining,
            start: Fixture.at(offsetSeconds),
            end: Fixture.at(offsetSeconds + 2_700),
            durationSeconds: 2_700,
            distanceMeters: nil,
            activeEnergyKilocalories: 300,
            hasRoute: false,
            source: .appleWatch,
            ingestedAt: Fixture.at(offsetSeconds + 2_820)
        )
    }

    private static func labeller(
        over store: InMemoryWorkoutStore,
        ids: [UUID]
    ) -> MiscategorisedScoreLabeller {
        let remaining = IDSequence(ids)
        return MiscategorisedScoreLabeller(
            workouts: store,
            scores: store,
            now: { Fixture.at(100_000) },
            newLabelID: { remaining.next() }
        )
    }

    /// One pass over a history holding one miscategorised lift, one correctly judged lift
    /// and one run. Exactly one label is written, and the two scores that were asked the
    /// right question are untouched.
    func testThePassLabelsOnlyTheScoresJudgedAgainstTheWrongAsk() async throws {
        let store = InMemoryWorkoutStore()
        let runID = Fixture.otherWorkoutID
        let correctlyJudgedID = UUID(uuidString: "33333333-3333-3333-3333-333333333333") ?? UUID()

        try await store.store(try Self.lift(id: Fixture.workoutID))
        try await store.store(try Self.lift(id: correctlyJudgedID, startingAt: 86_400))
        try await store.store(try Fixture.workout(id: runID))

        try await store.recordAutomaticScore(try Self.liftScoredAsARun())
        try await store.recordAutomaticScore(try Self.liftScoredAsALift(workoutID: correctlyJudgedID))
        try await store.recordAutomaticScore(try Fixture.score(points: 74, workoutID: runID))

        let outcome = try await Self.labeller(over: store, ids: [Self.labelID]).run()

        XCTAssertEqual(outcome.scoresLabelled, 1)
        XCTAssertEqual(outcome.scoresAlreadyLabelled, 0)
        XCTAssertEqual(store.allMiscategorisationLabels.count, 1)

        // `XCTUnwrap` takes a non-async autoclosure, so each `await` is hoisted out of
        // it — see the note at the top of `ChatThreadRepositoryTests`.
        let labelledLedger = try await store.ledger(forWorkout: Fixture.workoutID)
        let labelled = try XCTUnwrap(labelledLedger)
        XCTAssertTrue(labelled.isMiscategorised)
        XCTAssertEqual(labelled.miscategorisationLabel?.judgedAgainst, .easy)
        XCTAssertEqual(labelled.miscategorisationLabel?.actualDiscipline, .lift)
        XCTAssertEqual(labelled.miscategorisationLabel?.recordedAt, Fixture.at(100_000))

        let correctlyJudgedLedger = try await store.ledger(forWorkout: correctlyJudgedID)
        let correctlyJudged = try XCTUnwrap(correctlyJudgedLedger)
        XCTAssertFalse(correctlyJudged.isMiscategorised)

        let runLedger = try await store.ledger(forWorkout: runID)
        let run = try XCTUnwrap(runLedger)
        XCTAssertFalse(run.isMiscategorised)
    }

    /// Idempotent, which is why the pass needs no "has this run" flag: the second pass
    /// finds the score already labelled and writes nothing.
    func testASecondPassWritesNothing() async throws {
        let store = InMemoryWorkoutStore()
        try await store.store(try Self.lift(id: Fixture.workoutID))
        try await store.recordAutomaticScore(try Self.liftScoredAsARun())

        let first = try await Self.labeller(over: store, ids: [Self.labelID]).run()
        XCTAssertEqual(first.scoresLabelled, 1)

        let second = try await Self.labeller(over: store, ids: [Self.secondLabelID]).run()
        XCTAssertEqual(second.scoresLabelled, 0)
        XCTAssertEqual(second.scoresAlreadyLabelled, 1)
        XCTAssertEqual(store.allMiscategorisationLabels.count, 1)
        XCTAssertEqual(store.allMiscategorisationLabels.first?.id, Self.labelID)
    }

    /// **The pass is not a migration.** It adds records; it rewrites nothing. Asserted
    /// against the stored bytes of the score before the pass ran.
    func testThePassLeavesTheStoredScoreByteIdentical() async throws {
        let store = InMemoryWorkoutStore()
        let score = try Self.liftScoredAsARun()
        try await store.store(try Self.lift(id: Fixture.workoutID))
        try await store.recordAutomaticScore(score)

        let before = try PersistencePayload.encode(score, field: "test.score")
        _ = try await Self.labeller(over: store, ids: [Self.labelID]).run()

        let afterLedger = try await store.ledger(forWorkout: Fixture.workoutID)
        let after = try XCTUnwrap(afterLedger)
        XCTAssertEqual(
            try PersistencePayload.encode(after.automatic, field: "test.score"),
            before
        )
        XCTAssertEqual(after.automatic, score)
    }

    /// A lift the app never scored has nothing to label, and the pass says so without
    /// inventing a record.
    func testThePassIgnoresAnUnscoredLift() async throws {
        let store = InMemoryWorkoutStore()
        try await store.store(try Self.lift(id: Fixture.workoutID))

        let outcome = try await Self.labeller(over: store, ids: [Self.labelID]).run()
        XCTAssertEqual(outcome, .nothingToDo)
        XCTAssertTrue(store.allMiscategorisationLabels.isEmpty)
    }
}

/// Hands out pre-agreed identifiers in order, so a pass that mints several is still a
/// pure function of its inputs. Falls back to a fresh `UUID` rather than trapping — a
/// test that asked for more labels than it listed should fail on its assertions, not on
/// an index.
private final class IDSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var remaining: [UUID]

    init(_ ids: [UUID]) { self.remaining = ids }

    func next() -> UUID {
        lock.lock()
        defer { lock.unlock() }
        guard !remaining.isEmpty else { return UUID() }
        return remaining.removeFirst()
    }
}

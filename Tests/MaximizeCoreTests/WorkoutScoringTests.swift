import Foundation
import XCTest
@testable import MaximizeCore

/// The contract with the model: what it is asked to do, and what it is allowed to get
/// back through the door.
///
/// Every rejection here is a rejection of a *permanent* record. D8 makes a stored score
/// immutable, so a wrong one cannot be withdrawn — only annotated, which would corrupt
/// the correction-rate signal that annotations exist to measure. That asymmetry is why
/// this file leans so hard on refusal.
final class WorkoutScoringTests: XCTestCase {

    private func context(
        on day: String = ScoringFixture.easyDay,
        averageHeartRateBPM: Double? = 142,
        drift: Double? = 0.03,
        existingScore: Score? = nil
    ) throws -> WorkoutContext {
        try ScoringFixture.context(
            on: day,
            metrics: ScoringFixture.metrics(
                averageHeartRateBPM: averageHeartRateBPM,
                heartRateDriftFraction: drift
            ),
            existingScore: existingScore
        )
    }

    private func score(
        _ proposal: ScoreProposal,
        context subject: WorkoutContext? = nil
    ) throws -> Score {
        let resolved = try subject ?? context()
        return try WorkoutScorer.score(
            context: resolved,
            evaluation: RubricEvaluator.evaluate(resolved),
            proposal: proposal,
            scoredAt: ScoringFixture.scoredAt
        )
    }

    // MARK: - Accepting

    func testAValidProposalBecomesAnImmutableScore() throws {
        let result = try score(ScoreProposal(score: 94, rationale: "Held 142 bpm under the 150 cap with 3% drift."))

        XCTAssertEqual(result.workoutID, Fixture.workoutID)
        XCTAssertEqual(result.value.points, 94)
        XCTAssertEqual(result.planVersion.number, 1)
        XCTAssertEqual(result.rubricBandIdentifier, "easy.onCap.lowDrift")
        XCTAssertEqual(result.actualClassification, .easy)
        XCTAssertEqual(result.scheduledSession.kind, .easy)
        XCTAssertEqual(result.effectiveThreshold.points, 70)
        XCTAssertEqual(result.band, .effective)
        XCTAssertTrue(result.isEffective)
        XCTAssertEqual(result.rationale, "Held 142 bpm under the 150 cap with 3% drift.")
        XCTAssertEqual(result.scoredAt, ScoringFixture.scoredAt)
    }

    /// The straddling band in action (§10.3's 55–74 against a threshold of 70): inside
    /// one band, the model's exact number decides whether the day counted.
    func testInsideAStraddlingBandTheChosenNumberDecidesTheVerdict() throws {
        let overCap = try context(averageHeartRateBPM: 155, drift: 0.02)

        let effective = try score(
            ScoreProposal(score: 70, rationale: "Ran 155 bpm, just over the cap, but held it steady."),
            context: overCap
        )
        let marginal = try score(
            ScoreProposal(score: 69, rationale: "Ran 155 bpm, over the cap for most of the run."),
            context: overCap
        )

        XCTAssertEqual(effective.band, .effective)
        XCTAssertTrue(effective.isEffective)
        XCTAssertEqual(marginal.band, .marginal)
        XCTAssertFalse(marginal.isEffective)
    }

    func testTheBandRecordedIsTheOneTheRubricSelected() throws {
        let result = try score(
            ScoreProposal(score: 30, rationale: "Averaged 168 bpm on a day the plan asked for easy."),
            context: try ScoringFixture.context(
                classification: .hard,
                metrics: ScoringFixture.metrics(averageHeartRateBPM: 168, heartRateDriftFraction: nil)
            )
        )

        XCTAssertEqual(result.rubricBandIdentifier, "easy.ranHardInstead")
        XCTAssertEqual(result.band, .ineffective)
        XCTAssertEqual(result.actualClassification, .hard)
    }

    func testTheWholeRoundTripFromARawModelReply() throws {
        let subject = try context()

        let result = try WorkoutScorer.score(
            context: subject,
            modelResponse: #"{"score": 92, "rationale": "Stayed under the cap the whole way."}"#,
            scoredAt: ScoringFixture.scoredAt
        )

        XCTAssertEqual(result.value.points, 92)
        XCTAssertEqual(result.rubricBandIdentifier, "easy.onCap.lowDrift")
    }

    // MARK: - Rejecting the score

    /// The model ignored the range it was given. Rejected rather than clamped: a
    /// clamped 94 would look hand-picked and hide the fact that the constraint was
    /// disregarded.
    func testAScoreOutsideTheMatchedBandIsRejected() throws {
        assertThrowsScoring(
            .scoreOutsideBand,
            try score(ScoreProposal(score: 60, rationale: "Good run."))
        )
    }

    func testAScoreOutsideZeroToOneHundredIsRejected() throws {
        assertThrowsScoring(.scoreOutOfPermittedRange, try score(ScoreProposal(score: 137, rationale: "Great.")))
        assertThrowsScoring(.scoreOutOfPermittedRange, try score(ScoreProposal(score: -1, rationale: "Bad.")))
    }

    func testModelFaultsAreWorthRetrying() throws {
        XCTAssertTrue(ScoringError.malformedResponse(reason: "x").isWorthRetrying)
        XCTAssertTrue(ScoringError.scoreOutOfPermittedRange(proposed: 137).isWorthRetrying)
        XCTAssertTrue(ScoringError.rationaleRejected(reason: "x").isWorthRetrying)
        XCTAssertTrue(
            ScoringError.scoreOutsideBand(
                identifier: "easy.onCap.lowDrift",
                proposed: 60,
                permitted: try ScoreRange(lowest: 90, highest: 100)
            ).isWorthRetrying
        )
    }

    // MARK: - Rejecting the rationale

    func testAMultiLineRationaleIsRejected() throws {
        assertThrowsScoring(
            .rationaleRejected,
            try score(ScoreProposal(score: 94, rationale: "Held the cap.\nDrift was low."))
        )
    }

    func testAnEmptyOrWhitespaceRationaleIsRejected() throws {
        assertThrowsScoring(.rationaleRejected, try score(ScoreProposal(score: 94, rationale: "")))
        assertThrowsScoring(.rationaleRejected, try score(ScoreProposal(score: 94, rationale: "   ")))
    }

    func testAnOverlongRationaleIsRejected() throws {
        let tooLong = String(repeating: "a", count: RationaleContract.maximumCharacters + 1)

        assertThrowsScoring(.rationaleRejected, try score(ScoreProposal(score: 94, rationale: tooLong)))
    }

    func testARationaleAtTheLimitIsAccepted() throws {
        let atLimit = String(repeating: "a", count: RationaleContract.maximumCharacters)

        let result = try score(ScoreProposal(score: 94, rationale: atLimit))

        XCTAssertEqual(result.rationale.count, RationaleContract.maximumCharacters)
    }

    /// Liberal about formatting, strict about content: surrounding whitespace is the
    /// model's punctuation, not its answer.
    func testSurroundingWhitespaceIsTrimmedRatherThanRejected() throws {
        let result = try score(ScoreProposal(score: 94, rationale: "  Held the cap throughout.  "))

        XCTAssertEqual(result.rationale, "Held the cap throughout.")
    }

    func testControlCharactersAreRejected() throws {
        assertThrowsScoring(
            .rationaleRejected,
            try score(ScoreProposal(score: 94, rationale: "Held\tthe cap."))
        )
    }

    // MARK: - Parsing the reply

    func testAFencedJSONObjectIsAccepted() throws {
        let proposal = try ScoreProposal.parse("""
            ```json
            {"score": 91, "rationale": "Held the cap."}
            ```
            """)

        XCTAssertEqual(proposal.score, 91)
        XCTAssertEqual(proposal.rationale, "Held the cap.")
    }

    /// Not salvaged by hunting for the first brace. A model that narrated instead of
    /// answering did not follow the contract, and digging the object out of the prose
    /// would hide that from the retry logic.
    func testJSONWrappedInProseIsRejected() throws {
        assertThrowsScoring(
            .malformedResponse,
            try ScoreProposal.parse("Here is my assessment: {\"score\": 91, \"rationale\": \"Good.\"}")
        )
    }

    func testAMalformedReplyIsRejected() throws {
        assertThrowsScoring(.malformedResponse, try ScoreProposal.parse("91"))
        assertThrowsScoring(.malformedResponse, try ScoreProposal.parse(""))
        assertThrowsScoring(.malformedResponse, try ScoreProposal.parse("{\"score\": 91}"))
        assertThrowsScoring(.malformedResponse, try ScoreProposal.parse("{\"score\": \"ninety\", \"rationale\": \"x\"}"))
        assertThrowsScoring(.malformedResponse, try ScoreProposal.parse("{\"score\": 91.5, \"rationale\": \"x\"}"))
    }

    // MARK: - Refusing to score at all

    /// MAX-014 documents that a scoring context must not carry a score: a scorer shown a
    /// previous verdict is being invited to agree with it, and the auto-versus-manual
    /// divergence that measures scorer quality depends on the score being formed
    /// independently. Enforced here rather than left in prose.
    func testAContextThatAlreadyCarriesAScoreIsRefused() throws {
        let alreadyScored = try context(existingScore: Fixture.score(points: 88))

        assertThrowsScoring(
            .contextAlreadyScored,
            try WorkoutScorer.score(
                context: alreadyScored,
                modelResponse: #"{"score": 92, "rationale": "Held the cap."}"#,
                scoredAt: ScoringFixture.scoredAt
            )
        )
    }

    /// MAX-068: a chat context carries more of the athlete's record than a scoring
    /// prompt may — the pace breakdown — and scoring one would put that in the automatic,
    /// unattended call every ingested run makes. Unreachable through the real flows, and
    /// asserted anyway, because the point of the guard is that the narrower payload is
    /// enforced rather than merely conventional.
    func testAContextAssembledForChatIsRefusedForScoring() throws {
        let forChat = try ScoringFixture.context(audience: .chat)

        assertThrows(
            .inconsistent,
            try WorkoutScorer.score(
                context: forChat,
                modelResponse: #"{"score": 92, "rationale": "Held the cap."}"#,
                scoredAt: ScoringFixture.scoredAt
            )
        )
    }

    /// An evaluation from another day paired with this context would produce a
    /// confident, permanently stored score for the wrong ask.
    func testAnEvaluationFromADifferentDayIsRefused() throws {
        let easy = try context()
        let longRun = try ScoringFixture.context(
            on: ScoringFixture.longDay,
            classification: .long,
            distanceMeters: 18_000
        )

        assertThrows(
            .inconsistent,
            try WorkoutScorer.score(
                context: easy,
                evaluation: RubricEvaluator.evaluate(longRun),
                proposal: ScoreProposal(score: 80, rationale: "Covered the distance."),
                scoredAt: ScoringFixture.scoredAt
            )
        )
    }

    // MARK: - The instruction

    /// D3: the scorer does not restate a single measurement. It wraps MAX-014's fact
    /// sheet in a task, and that is the whole of its authorship.
    func testTheInstructionCarriesTheFactSheetVerbatim() throws {
        let subject = try context()

        let instruction = try WorkoutScorer.instruction(
            for: subject,
            evaluation: RubricEvaluator.evaluate(subject)
        )

        XCTAssertTrue(instruction.subject.contains(subject.factSheet()))
    }

    /// The stable half holds no run data, which is what makes it safe to cache and
    /// keeps the health data confined to one reviewable value.
    func testTheTaskHalfIsIdenticalForEveryRun() throws {
        let easy = try context()
        let overCap = try context(averageHeartRateBPM: 160, drift: 0.02)

        let first = try WorkoutScorer.instruction(for: easy, evaluation: RubricEvaluator.evaluate(easy))
        let second = try WorkoutScorer.instruction(for: overCap, evaluation: RubricEvaluator.evaluate(overCap))

        XCTAssertEqual(first.task, second.task)
        XCTAssertFalse(first.task.contains("bpm"))
        XCTAssertFalse(first.task.contains("142"))
    }

    func testTheInstructionStatesThePermittedRangeAndTheMatchedRule() throws {
        let subject = try context()

        let instruction = try WorkoutScorer.instruction(
            for: subject,
            evaluation: RubricEvaluator.evaluate(subject)
        )

        XCTAssertTrue(instruction.subject.contains("easy.onCap.lowDrift"))
        XCTAssertTrue(instruction.subject.contains("90"))
        XCTAssertTrue(instruction.subject.contains("100"))
    }

    /// When the band straddles the effective threshold the model is told where the cut
    /// falls, because its choice decides the verdict. Leaving it to infer a threshold it
    /// was never given would be the one place a number matters and nobody stated it.
    func testAStraddlingBandTellsTheModelWhereTheCutFalls() throws {
        let overCap = try context(averageHeartRateBPM: 155, drift: 0.02)

        let instruction = try WorkoutScorer.instruction(
            for: overCap,
            evaluation: RubricEvaluator.evaluate(overCap)
        )

        XCTAssertTrue(instruction.subject.contains("70"))
        XCTAssertTrue(instruction.subject.contains("effective day"))
    }

    func testTheInstructionIsRefusedForAnAlreadyScoredContext() throws {
        let alreadyScored = try context(existingScore: Fixture.score(points: 88))
        let evaluation = try RubricEvaluator.evaluate(try context())

        assertThrowsScoring(
            .contextAlreadyScored,
            try WorkoutScorer.instruction(for: alreadyScored, evaluation: evaluation)
        )
    }
}

import Foundation

/// The text put in front of the model for one scoring call, split by what it contains.
///
/// The split is not cosmetic. `task` is identical for every workout and holds no health
/// data whatsoever, so it can be sent as a system prompt and cached; `subject` is this
/// run and is the only half that carries PII. Keeping them apart means the sensitive
/// text is a single, reviewable value rather than something interleaved through a
/// template — and CLAUDE.md's rule that only what the scorer needs enters a prompt is
/// then checkable by reading one property.
public struct ScoringInstruction: Hashable, Sendable {
    /// Stable across every call. No health data, no plan data, no numbers.
    public let task: String

    /// This run: the rubric's verdict, then the context builder's fact sheet verbatim.
    public let subject: String

    init(task: String, subject: String) {
        self.task = task
        self.subject = subject
    }
}

/// Applies the plan's rubric, asks the model for the one thing the rubric cannot give,
/// and accepts or rejects what comes back (§10).
///
/// ## What the model is for
///
/// The rubric selects the band; the model places the score inside it and writes the
/// rationale. It is not consulted about which band applies, and it cannot move a run
/// across a band boundary.
///
/// The alternative reading of §10 — the model scores freely, the rubric only validates
/// — was rejected for four reasons:
///
/// 1. **§10.3 is written as a decision table.** "HR ≤ cap with low drift → 90–100 …
///    avg 151–158 → 55–74" maps conditions to ranges. The ranges are wide because the
///    width *is* the space left for judgment; if the model scored freely they would be
///    decoration.
/// 2. **D1 would stop being true.** If a free score decides the band, then the plan
///    version no longer determines the verdict — the model version does. Re-scoring a
///    historical run after a model upgrade would produce a different answer with the
///    same plan, which is exactly the irreproducibility D1 exists to prevent.
/// 3. **The effective flag drives tallies, streaks and calendar colour** (D4, FR-3.2,
///    FR-3.4). Under a free score a hallucinated 69-instead-of-71 silently breaks a
///    streak. Under this design the verdict follows from measured metrics and versioned
///    plan data everywhere the rubric author kept a band on one side of the threshold.
/// 4. **It is the half CI can actually test.** R7 notes that Claude's judgment cannot
///    be unit-tested, only the plumbing. Making band selection deterministic moves the
///    load-bearing decision into the testable half — and MAX-071 is specified as
///    "known-good runs → expected score bands", which presumes exactly this.
///
/// The cost is real and worth stating: a rubric band whose range straddles the
/// effective threshold hands the verdict back to the model for those runs (§10.3's
/// 55–74 does, against a threshold of 70). That is the rubric author's choice, it is
/// visible in the plan data, and `RubricEvaluation.verdictIsSettledByRubric` reports
/// it.
public enum WorkoutScorer {

    // MARK: - Asking

    /// Builds the instruction for one scoring call.
    ///
    /// The fact sheet is included **verbatim** from `WorkoutContext.factSheet()`. This
    /// type deliberately does not restate a single measurement: D3 gives MAX-014 sole
    /// authority over what Claude is told about a run, and this ticket owns only what it
    /// is asked to do with it.
    public static func instruction(
        for context: WorkoutContext,
        evaluation: RubricEvaluation
    ) throws -> ScoringInstruction {
        try assertScoreable(context, evaluation)

        let range = evaluation.permittedScores
        var lines: [String] = []

        lines.append("## The rubric's verdict")
        lines.append("The plan's scoring rubric has already been applied to this run. It matched the "
            + "rule \"\(evaluation.band.identifier)\", which the plan describes as: "
            + "\(evaluation.band.rationale)")
        lines.append("That rule fixes the score for this run between \(range.lowest) and "
            + "\(range.highest) inclusive.")

        switch evaluation.settledScoreBand {
        case .some(let settled):
            lines.append("Every score in that range is \(settled.rawValue), so the verdict is already "
                + "decided; you are choosing the degree, not the outcome.")
        case .none:
            // The straddling case. Say plainly where the cut falls rather than leaving
            // the model to infer a threshold it was never told.
            lines.append("A score of \(evaluation.rubric.effectiveThreshold) or above counts as an "
                + "effective day, so where you land inside the range decides whether this run "
                + "counted.")
        }

        lines.append("")
        lines.append(context.factSheet())

        return ScoringInstruction(task: taskDescription, subject: lines.joined(separator: "\n"))
    }

    /// The stable half of the prompt. Contains no data about any run.
    private static let taskDescription = """
        You are scoring one running workout against the athlete's training plan.

        The plan's rubric has already been applied deterministically, and you are told \
        which rule matched and the score range that rule permits. Your job is the part \
        the rubric cannot do:

        1. Choose the exact score within the permitted range, using the run's measured \
        numbers to decide where in that range it belongs. The bottom of the range means \
        the run barely satisfied the rule; the top means it satisfied it emphatically.
        2. Write the one-line rationale shown in the app's verdict header.

        Do not argue with the matched rule and do not score outside the permitted range. \
        A score outside it will be rejected and you will be asked again.

        Rationale rules:
        \(RationaleContract.instructionText)

        Reply with a single JSON object and nothing else — no prose before or after it:
        \(ScoreProposal.responseFormatDescription)
        """

    // MARK: - Accepting

    /// Validates a raw model reply and turns it into the immutable auto-score, or
    /// rejects it.
    ///
    /// - Parameter scoredAt: injected rather than read from the clock, so a score is a
    ///   pure function of its inputs and a test can assert on the whole record.
    public static func score(
        context: WorkoutContext,
        evaluation: RubricEvaluation,
        modelResponse: String,
        scoredAt: Date
    ) throws -> Score {
        try score(
            context: context,
            evaluation: evaluation,
            proposal: ScoreProposal.parse(modelResponse),
            scoredAt: scoredAt
        )
    }

    /// Validates a decoded proposal and turns it into the immutable auto-score.
    ///
    /// Every rejection here is a rejection of a *stored record*: nothing that fails
    /// these checks may become a `Score`, because D8 makes a stored score permanent and
    /// a wrong one cannot be taken back — only annotated, which would corrupt the
    /// correction-rate signal that annotation exists to measure.
    public static func score(
        context: WorkoutContext,
        evaluation: RubricEvaluation,
        proposal: ScoreProposal,
        scoredAt: Date
    ) throws -> Score {
        try assertScoreable(context, evaluation)

        guard ScoreValue.permittedRange.contains(proposal.score) else {
            throw ScoringError.scoreOutOfPermittedRange(proposed: proposal.score)
        }
        let value = try ScoreValue(proposal.score)

        guard evaluation.permittedScores.contains(value) else {
            throw ScoringError.scoreOutsideBand(
                identifier: evaluation.band.identifier,
                proposed: proposal.score,
                permitted: evaluation.permittedScores
            )
        }

        let rationale = try RationaleContract.validated(proposal.rationale)

        return try Score(
            workoutID: context.workout.id,
            planVersion: evaluation.plan.version,
            scheduledSession: evaluation.scheduledSession,
            actualClassification: evaluation.classification,
            value: value,
            effectiveThreshold: evaluation.rubric.effectiveThreshold,
            // The one place entitled to turn a number into a band, reading the
            // thresholds of the plan version in force on this workout's day (D1).
            band: evaluation.rubric.scoreBand(for: value),
            rubricBandIdentifier: evaluation.band.identifier,
            rationale: rationale,
            scoredAt: scoredAt
        )
    }

    /// Evaluates the rubric and accepts a reply in one step, for callers that do not
    /// need the evaluation in between.
    public static func score(
        context: WorkoutContext,
        modelResponse: String,
        scoredAt: Date
    ) throws -> Score {
        let evaluation = try RubricEvaluator.evaluate(context)
        return try score(
            context: context,
            evaluation: evaluation,
            modelResponse: modelResponse,
            scoredAt: scoredAt
        )
    }

    /// Guards shared by asking and accepting.
    ///
    /// The pairing check is a caller error rather than a scoring failure — an
    /// evaluation from a different run's context would produce a confident,
    /// permanently stored score for the wrong workout, which is the same class of
    /// mistake `WorkoutContextBuilder` refuses to assemble.
    private static func assertScoreable(
        _ context: WorkoutContext,
        _ evaluation: RubricEvaluation
    ) throws {
        if context.existingScore != nil {
            throw ScoringError.contextAlreadyScored(workoutID: context.workout.id)
        }
        guard evaluation.planDay.date == context.day,
              evaluation.plan.version == context.plan?.version
        else {
            throw DomainError.inconsistent(
                reason: "WorkoutScorer: the evaluation was made for \(evaluation.planDay.date) under "
                    + "plan \(evaluation.plan.version), which does not describe this context"
            )
        }
    }
}

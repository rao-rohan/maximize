import Foundation

/// The text put in front of the model for one scoring call, split by what it contains.
///
/// The split is not cosmetic. `task` holds no health data whatsoever, so it can be sent
/// as a system prompt and cached; `subject` is this run and is the only half that
/// carries PII. Keeping them apart means the sensitive text is a single, reviewable
/// value rather than something interleaved through a template — and CLAUDE.md's rule
/// that only what the scorer needs enters a prompt is then checkable by reading one
/// property.
///
/// `task` is identical for every workout **of the same discipline** (MAX-147): it
/// still carries no health data, no plan data and no numbers, but it is no longer one
/// literal for every call, because a lift and a run are not scored on the same grounds
/// (LIFTING-SPEC §8.3). Two stable variants instead of one is still stable — either one
/// is cacheable, and a client keys its cache on the discipline the same way it already
/// keys everything else on the workout being scored.
public struct ScoringInstruction: Hashable, Sendable {
    /// Stable across every call **for one discipline**. No health data, no plan data,
    /// no numbers — see the type's doc comment for why that survived the branch.
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

        return ScoringInstruction(
            task: taskDescription(for: context.discipline),
            subject: lines.joined(separator: "\n")
        )
    }

    /// The stable half of the prompt. Contains no data about any run — but it is not
    /// one literal for every call any more (MAX-147).
    ///
    /// ## Why a lift needs different words at all
    ///
    /// MAX-136 taught `WorkoutFactSheet` to stop describing a lift in running
    /// vocabulary; this is the instruction wrapped around that fact sheet, and it had
    /// the same problem one level up. Read literally, "using the run's measured numbers"
    /// sends the model hunting a lift's fact sheet for a pace or a cadence line that
    /// LIFTING-SPEC §10.1 deliberately omits — and worse, nothing stopped it reaching
    /// for the one number a lift's record actually has plenty of signal for reasoning
    /// about that A20 explicitly forbids scoring on: how much was lifted. §8.3 is
    /// unambiguous that no such number exists in the record, so a task that invited the
    /// model to weigh load or volume would be asking it to invent one.
    ///
    /// ## One template with a discipline branch, not two independent strings
    ///
    /// The rejection rule, the rationale contract and the JSON reply format are the same
    /// contract regardless of what is being scored — the model is asked for the same
    /// *shape* of answer either way, and only what it is told to weigh differs. Writing
    /// two complete literals would duplicate those shared paragraphs and let them drift
    /// apart the next time either is edited, which is exactly the failure
    /// `WorkoutFactSheet.factSheet()` avoids by being one renderer with one discipline
    /// branch rather than a second renderer (A12, MAX-136). This function makes the same
    /// choice at the scale of the instruction that wraps it.
    ///
    /// The branch is on `Discipline`, not `ActivityType.isRun`, for the identical reason
    /// the fact sheet's is: A17's slot is what a workout is judged against, so a hike or
    /// a ride sits in the run slot and reads the run text unchanged.
    ///
    /// **The run branch's output is pinned as a literal in `ScorerTaskTextTests`** — it
    /// predates this function and must read exactly as it did before the lift branch
    /// existed.
    private static func taskDescription(for discipline: Discipline) -> String {
        let opening: String
        let firstInstruction: String
        switch discipline {
        case .run:
            opening = "You are scoring one running workout against the athlete's training plan."
            firstInstruction = "using the run's measured numbers to decide where in that range it "
                + "belongs. The bottom of the range means the run barely satisfied the rule; the top "
                + "means it satisfied it emphatically."
        case .lift:
            // No "pace", "cadence", "cap", "splits" or "distance" — none of them describe
            // this session (§10.1) — and no "load" or "volume": §8.3 says plainly that no
            // such number exists in the record, so this text does not send the model
            // looking for one.
            opening = "You are scoring one lifting workout against the athlete's training plan."
            firstInstruction = "using the session's measured facts to decide where in that range it "
                + "belongs: whether the prescribed session happened, on the prescribed day, for "
                + "roughly the prescribed length. The bottom of the range means it barely cleared "
                + "that; the top means it matched cleanly."
        }

        return """
            \(opening)

            The plan's rubric has already been applied deterministically, and you are told \
            which rule matched and the score range that rule permits. Your job is the part \
            the rubric cannot do:

            1. Choose the exact score within the permitted range, \(firstInstruction)
            2. Write the one-line rationale shown in the app's verdict header.

            Do not argue with the matched rule and do not score outside the permitted range. \
            A score outside it will be rejected and you will be asked again.

            \(absenceRule)

            Rationale rules:
            \(RationaleContract.instructionText)

            Reply with a single JSON object and nothing else — no prose before or after it:
            \(ScoreProposal.responseFormatDescription)
            """
    }

    /// The one rule about absence this prompt was missing (MAX-175).
    ///
    /// ## Why the scorer needed its own wording, and why it is not a refusal
    ///
    /// The app's other model-facing prompts — `ChatModel.workoutTask`,
    /// `ChatModel.trainingTask`, `PlanProposalInstruction.taskDescription` — each already
    /// tell the model to *say* when something is not in front of it. This one could not
    /// borrow that sentence, because this call has no refusal available to it: the reply
    /// is a JSON object carrying a score inside a range the rubric already fixed, and a
    /// scorer that answered "I do not have that" would have failed rather than declined.
    ///
    /// So the rule is stated as the thing the scorer *can* obey: do not supply a figure
    /// the record withheld, and do not reason as though one had been supplied. That is
    /// the same principle every fact-sheet absence line is written for — "not applicable
    /// — this workout has no heart-rate data", "not recorded for this workout", and
    /// MAX-136's "read nothing into their absence" — read from the other side of the
    /// prompt. The fact sheet is careful to say *which kind* of nothing each gap is; this
    /// is what stops that care being spent on a reader who was never told what to do with
    /// it.
    ///
    /// **The concrete hazard is the rationale, and it is permanent.** The score itself is
    /// bounded by the band, but the rationale is free prose that `RationaleContract` asks
    /// to cite "the numbers that decided it", and it is stored immutably under D8 and
    /// shown in the verdict header. A run whose splits were never recorded getting a
    /// header that quotes a second-half split is exactly Helix's per-muscle story in one
    /// line — and unlike a chat turn, nobody can ask it to take that back.
    ///
    /// Kept as a named constant rather than inlined so that
    /// `HonestRefusalAcrossPromptsTests` can pin it and hold it beside the other three
    /// prompts' clauses. Internal, not public: it is prompt text, not API.
    ///
    /// Shared by both discipline branches, and therefore written in neither's vocabulary
    /// — no "pace", "cadence", "cap", "splits" or "distance", for the reason the lift
    /// branch above states, and `ScorerTaskTextTests` checks that on every commit.
    static let absenceRule = """
        The record you are given states its own absences. Where it says a figure was not \
        recorded, does not apply, or was not computed, do not supply one and do not reason \
        as though you had it: score and justify from what is stated.
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
    ///
    /// **The day and the plan version stopped being enough to identify a pairing**
    /// (MAX-133). A `PlanDay` now carries two asks, and `RubricEvaluation` records which
    /// of them it judged; a lift and a run on the same Tuesday share a date and a plan
    /// version, so the two checks below would both pass for an evaluation made against
    /// the other one's ask. The score that came out would carry the wrong discipline's
    /// prescription — permanently, under D8 — which is precisely the failure the day
    /// check exists to prevent, arriving through the axis A17 added.
    private static func assertScoreable(
        _ context: WorkoutContext,
        _ evaluation: RubricEvaluation
    ) throws {
        if context.existingScore != nil {
            throw ScoringError.contextAlreadyScored(workoutID: context.workout.id)
        }
        // Unreachable through any real flow — chat only builds a context for a run that
        // already has a score, and the check above rejects those. Kept because it is the
        // difference between "the scorer is shown less by convention" and "the scorer
        // cannot be shown more" (MAX-068): a chat context carries the pace breakdown, and
        // scoring it would put that in an automatic, unattended prompt.
        guard context.audience == .scoring else {
            throw DomainError.inconsistent(
                reason: "WorkoutScorer: this context was assembled for \(context.audience.rawValue) "
                    + "and carries more of the record than a scoring prompt may. Build it with "
                    + "audience: .scoring."
            )
        }
        guard evaluation.planDay.date == context.day,
              evaluation.plan.version == context.plan?.version
        else {
            throw DomainError.inconsistent(
                reason: "WorkoutScorer: the evaluation was made for \(evaluation.planDay.date) under "
                    + "plan \(evaluation.plan.version), which does not describe this context"
            )
        }
        let discipline = context.workout.activityType.discipline
        guard evaluation.discipline == discipline else {
            throw DomainError.inconsistent(
                reason: "WorkoutScorer: the evaluation was made against the day's "
                    + "\(evaluation.discipline.rawValue) ask, but this context carries a "
                    + "\(discipline.rawValue) workout"
            )
        }
    }
}

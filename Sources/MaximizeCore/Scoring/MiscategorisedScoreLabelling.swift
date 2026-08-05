import Foundation

/// What one labelling pass did (A21, MAX-143).
///
/// Counts only — never an identifier and never a date. CLAUDE.md rules health data out of
/// logs entirely, and a progress count is the most a caller may safely record, the same
/// line `DistanceSplitsBackfillOutcome` draws.
public struct MiscategorisedScoreLabellingOutcome: Hashable, Sendable {

    /// Labels written by this pass.
    public let scoresLabelled: Int

    /// Scores this pass found miscategorised that already carried a label, so it wrote
    /// nothing for them. Non-zero is the ordinary state of every pass after the first —
    /// it is what idempotence looks like from the outside.
    public let scoresAlreadyLabelled: Int

    public init(scoresLabelled: Int, scoresAlreadyLabelled: Int) {
        self.scoresLabelled = scoresLabelled
        self.scoresAlreadyLabelled = scoresAlreadyLabelled
    }

    public static let nothingToDo = MiscategorisedScoreLabellingOutcome(
        scoresLabelled: 0,
        scoresAlreadyLabelled: 0
    )
}

/// Labels the auto-scores that were written against the wrong discipline's ask (A21,
/// MAX-143).
///
/// ## How a score comes to be labelled, and why this way
///
/// "The scorer was asked the wrong question" is a fact the app can now *detect*: since
/// MAX-133 a workout is resolved against its own discipline's ask, so a stored score whose
/// prescription belongs to the other discipline is one the old evaluator produced. Three
/// ways of acting on that were available, and this is the third:
///
/// - **Something the athlete triggers.** Rejected. It asks the athlete to adjudicate a
///   bug in the app's own history, and a label nobody applies is a label that does not
///   exist — the average-score tile stays unexplained on exactly the devices where nobody
///   went looking.
/// - **An ongoing rule, derived at read time.** Rejected for D1's reason — see
///   `MiscategorisedScoreLabel`'s note on why the label is a stored record.
/// - **A pass that only ever adds records.** Taken. It reads scores, writes labels, and
///   has no path to a `Score` at all: the type it writes cannot reach one, and
///   `ScoreRepository` offers no update. **This is not a migration** — nothing stored is
///   rewritten, re-typed or deleted — and that distinction is the whole ticket.
///
/// ## Idempotent, and therefore needs no "has this run" flag
///
/// A pass skips any score that already carries a label, so running it on every launch
/// costs one enumeration and finds nothing to do. That is deliberately cheaper than
/// recording that it ran: a flag can be lost, can be restored from a backup out of step
/// with the rows it describes, and has to be migrated itself.
///
/// ## Candidates are lifts, and what that costs
///
/// A stored score judged against the other discipline's ask can only be a **lift judged
/// against a run ask**. The reverse would need a `.lift` kind in a plan's run slot, and
/// nothing has ever written one: the lift slot arrived with MAX-129 defaulted to rest,
/// `ScheduledSessionKind.prescribable` keeps `.lift` out of the run picker, and since
/// MAX-133 `WorkoutScorer` refuses a cross-discipline pairing outright. So filtering
/// candidates to `Discipline.lift` loses nothing real and keeps the pass proportional to
/// lifting history rather than to every workout ever stored. The *rule*
/// (`MiscategorisedScoreLabel.isMiscategorised`) stays symmetric, because a rule that is
/// total is cheaper to trust than one that has to be read alongside this paragraph.
public struct MiscategorisedScoreLabeller: Sendable {
    private let workouts: WorkoutRepository
    private let scores: ScoreRepository
    private let now: @Sendable () -> Date
    private let newLabelID: @Sendable () -> UUID

    /// - Parameters:
    ///   - now: injected rather than read from the clock, so a label is a pure function of
    ///     its inputs and a test can assert on the whole record — the convention every
    ///     other date in this package follows.
    ///   - newLabelID: injected for the same reason. A pass mints one identifier per label
    ///     rather than taking a single one, because a pass may label several scores.
    public init(
        workouts: WorkoutRepository,
        scores: ScoreRepository,
        now: @escaping @Sendable () -> Date = { Date() },
        newLabelID: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        self.workouts = workouts
        self.scores = scores
        self.now = now
        self.newLabelID = newLabelID
    }

    /// Runs one pass over stored history.
    ///
    /// - Returns: what it did, as counts.
    /// - Throws: if the store cannot be enumerated, or if writing a label fails. Both stop
    ///   the pass and both are retried whole on the next one, which costs nothing because
    ///   every label already written is skipped.
    ///
    ///   A single workout whose *ledger* cannot be read is skipped rather than failing the
    ///   pass — it is read again, fresh, next time, and losing the rest of the history to
    ///   one bad row would be the worse trade. That is
    ///   `WorkoutIngestionPipeline.backfillDistanceSplits`'s reasoning, applied to a pass
    ///   whose work is even cheaper to repeat.
    public func run() async throws -> MiscategorisedScoreLabellingOutcome {
        let candidates = try await workouts.workouts(
            startingIn: DateInterval(start: .distantPast, end: now())
        )

        var labelled = 0
        var alreadyLabelled = 0

        for workout in candidates {
            let discipline = workout.activityType.discipline
            guard discipline == .lift else { continue }
            guard let ledger = try? await scores.ledger(forWorkout: workout.id) else { continue }
            guard MiscategorisedScoreLabel.isMiscategorised(
                ledger.automatic,
                workoutDiscipline: discipline
            ) else { continue }

            // The idempotence gate. Checked against the ledger that was just read rather
            // than against anything this pass remembers, so two passes overlapping — or a
            // pass resumed after being interrupted — reach the same decision.
            guard !ledger.isMiscategorised else {
                alreadyLabelled += 1
                continue
            }

            guard let label = MiscategorisedScoreLabel.labelling(
                ledger.automatic,
                workoutDiscipline: discipline,
                id: newLabelID(),
                recordedAt: now()
            ) else { continue }

            try await scores.recordMiscategorisationLabel(label)
            labelled += 1
        }

        return MiscategorisedScoreLabellingOutcome(
            scoresLabelled: labelled,
            scoresAlreadyLabelled: alreadyLabelled
        )
    }
}

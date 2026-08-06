import Foundation

extension ScheduledSessionKind {

    /// Which of the plan's two slots this kind belongs to — nil for `.rest`, which both
    /// slots share (A17).
    ///
    /// `.rest` is genuinely neither, and that is load-bearing rather than a tidy
    /// nil: "the plan asked nothing of this discipline today" is the same sentence
    /// whichever slot says it, and a `Score` records only the ask it was judged against,
    /// never which slot that ask came out of. So a score judged against `.rest` cannot be
    /// read as evidence of *any* discipline, which is exactly what
    /// `MiscategorisedScoreLabel` needs it not to be — see that type's note on the
    /// ambiguity, and why it costs nothing.
    public var slotDiscipline: Discipline? {
        switch self {
        case .easy, .long, .hard, .other: return .run
        case .lift: return .lift
        case .rest: return nil
        }
    }
}

/// A mark on an auto-score saying it was written against the **wrong discipline's** ask,
/// and is therefore not evidence about scorer quality (A21, MAX-143).
///
/// ## What this is for
///
/// Before the plan distinguished lifting, every workout was resolved against the day's
/// run slot (MAX-133 fixed that). A strength session on an easy-run Tuesday was therefore
/// shown the easy-run bands and scored 20–45 as a failed easy run. Those scores are
/// wrong, and **D8 forbids touching them** — an auto-score is a permanent record of what
/// the scorer said, and this type does not change that by a single byte.
///
/// But leaving them unmarked is wrong too, and that is the half this type exists for. The
/// auto-versus-manual divergence *is* the scorer-quality metric (PRD §2), and D8 exists to
/// protect it. These scores are not scorer misjudgements: the model was handed a category
/// error and did its job. Counting them as misjudgements corrupts exactly the telemetry
/// D8 protects — in the opposite direction from the one D8 worries about. So the label is
/// an **additive record**, in `ScoreAnnotation`'s shape, and its one consequence is
/// `ScoreLedger.divergence` returning nil (see there).
///
/// ## Why it is a stored record and not a rule evaluated on the fly
///
/// The label's content is derivable today: `isMiscategorised(_:workoutDiscipline:)` is a
/// pure function of two facts already on disk. Deriving it at every read would be one
/// fewer record type, and it was rejected for D1's reason. A derived answer changes
/// whenever the derivation changes — a later ticket that maps a new HealthKit type to
/// `.lift`, or that adds a third discipline, would silently relabel history and move a
/// metric computed over it. A stored label pins the judgement to the moment it was made
/// and keeps the past reproducible, which is the same argument D1 makes for storing the
/// plan version on a `Score` rather than looking it up again.
///
/// It also keeps this honest about provenance: `judgedAgainst` and `actualDiscipline` are
/// written down, so the label states its own grounds rather than asking a reader to trust
/// that some pass once had a good reason.
///
/// ## Why `.rest` can never be labelled, and why that is free
///
/// A score judged against `.rest` is ambiguous — `ScheduledSessionKind.slotDiscipline`
/// explains why — so the initializer refuses to label one. Nothing is lost: on a day whose
/// run slot was rest, the old evaluator showed a lift the rest-day bands, and today's
/// evaluator shows that same lift the lift slot's rest-day bands. Every stored plan
/// prescribes rest on every lift slot (MAX-129), so the two readings resolve to the same
/// ask and produce the same band. The one case the rule cannot see is the one case where
/// there is nothing to see.
public struct MiscategorisedScoreLabel: Hashable, Sendable, Codable, Identifiable {

    /// The record's own identity, not the workout's — the shape `ScoreAnnotation` and
    /// `MuscleGroupEntry` already have, and what lets a duplicate arriving from two
    /// devices be tolerated rather than collide.
    public let id: UUID

    /// The workout whose auto-score this labels. One auto-score per workout (§11), so
    /// this identifies the score too.
    public let workoutID: UUID

    /// The ask the score was actually judged against, copied from the score at labelling
    /// time. Written down rather than looked up so the label carries its own grounds.
    public let judgedAgainst: ScheduledSessionKind

    /// The discipline the workout actually belonged to, read from
    /// `Workout.activityType.discipline` — a fact HealthKit recorded, never the
    /// classifier's judgement, for the reason `RubricCondition.actualDiscipline` gives.
    public let actualDiscipline: Discipline

    /// When the labelling pass made this judgement.
    public let recordedAt: Date

    /// - Throws: `DomainError.inconsistent` when the two disciplines do not actually
    ///   disagree. A label is a claim with grounds, and an ungrounded one would quietly
    ///   remove a score from the scorer-quality metric — the one thing this whole
    ///   mechanism must not become a way to do.
    public init(
        id: UUID,
        workoutID: UUID,
        judgedAgainst: ScheduledSessionKind,
        actualDiscipline: Discipline,
        recordedAt: Date
    ) throws {
        guard let judgedDiscipline = judgedAgainst.slotDiscipline else {
            throw DomainError.inconsistent(
                reason: "MiscategorisedScoreLabel: a score judged against rest names no discipline, "
                    + "so it cannot be labelled miscategorised"
            )
        }
        guard judgedDiscipline != actualDiscipline else {
            throw DomainError.inconsistent(
                reason: "MiscategorisedScoreLabel: the \(judgedAgainst.rawValue) ask and a "
                    + "\(actualDiscipline.rawValue) workout are the same discipline; there is nothing "
                    + "to label"
            )
        }
        self.id = id
        self.workoutID = workoutID
        self.judgedAgainst = judgedAgainst
        self.actualDiscipline = actualDiscipline
        self.recordedAt = recordedAt
    }

    /// The unchecked path, used only by `labelling(_:workoutDiscipline:id:recordedAt:)`,
    /// which has already applied the identical two guards via `isMiscategorised`. Private,
    /// so there is exactly one door into this type from outside the file — the same device
    /// `ScheduledSession.rest` uses, and the reason no `try?` appears anywhere below.
    private init(
        uncheckedID id: UUID,
        workoutID: UUID,
        judgedAgainst: ScheduledSessionKind,
        actualDiscipline: Discipline,
        recordedAt: Date
    ) {
        self.id = id
        self.workoutID = workoutID
        self.judgedAgainst = judgedAgainst
        self.actualDiscipline = actualDiscipline
        self.recordedAt = recordedAt
    }

    // MARK: - The rule

    /// Whether this stored score was judged against the other discipline's ask.
    ///
    /// **This is the whole detection.** `Score.scheduledSession` is the ask the scorer
    /// actually used, captured verbatim at scoring time so the score stays reproducible
    /// (D1); the workout's discipline is what it should have been judged against
    /// (A17/MAX-133). When those disagree, the scorer was asked a question that did not
    /// apply.
    ///
    /// - Parameter workoutDiscipline: `Workout.activityType.discipline`. Passed in rather
    ///   than read from a `Workout` so this stays a pure function of two values and a test
    ///   can drive both directions without building a workout.
    public static func isMiscategorised(_ score: Score, workoutDiscipline: Discipline) -> Bool {
        guard let judged = score.scheduledSession.kind.slotDiscipline else { return false }
        return judged != workoutDiscipline
    }

    /// The label this score needs, or **nil if it needs none**.
    ///
    /// The single place a label is minted, so the record can never claim more than
    /// `isMiscategorised` will vouch for.
    public static func labelling(
        _ score: Score,
        workoutDiscipline: Discipline,
        id: UUID,
        recordedAt: Date
    ) -> MiscategorisedScoreLabel? {
        guard isMiscategorised(score, workoutDiscipline: workoutDiscipline) else { return nil }
        return MiscategorisedScoreLabel(
            uncheckedID: id,
            workoutID: score.workoutID,
            judgedAgainst: score.scheduledSession.kind,
            actualDiscipline: workoutDiscipline,
            recordedAt: recordedAt
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id, workoutID, judgedAgainst, actualDiscipline, recordedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            workoutID: container.decode(UUID.self, forKey: .workoutID),
            judgedAgainst: container.decode(ScheduledSessionKind.self, forKey: .judgedAgainst),
            actualDiscipline: container.decode(Discipline.self, forKey: .actualDiscipline),
            recordedAt: container.decode(Date.self, forKey: .recordedAt)
        )
    }
}

/// What a surface showing a labelled score says about it (A21, MAX-143).
///
/// Copy lives in the core for the reason `MuscleGroupEntryCopy` gives: a string a person
/// reads is a product decision, and a product decision in a SwiftUI view is verified only
/// when a human opens Xcode.
///
/// **The presentation decision this encodes: nothing is hidden and no number moves.** A
/// labelled score keeps its place in history, keeps its value, keeps its band and keeps
/// its rationale — the athlete's record is not rewritten, which is D8's point applied to
/// the screen rather than to the store. What it gains is a sentence saying the verdict was
/// reached against the wrong discipline's rubric. The wrongness becomes legible rather
/// than resolved, which is the only move available once overwriting is off the table.
///
/// The voice follows CLAUDE.md's absence strings: it states what happened, in the past
/// tense, without apology and without promising a correction that D8 forbids.
public enum MiscategorisedScoreCopy {

    /// The line beside a labelled score.
    ///
    /// Says *what the app did*, not what the athlete did wrong. It avoids the word
    /// "correction" deliberately — a correction is the athlete's to make and is a
    /// different record entirely, and conflating the two is what poisons the very metric
    /// this label protects.
    public static let labelledDetail =
        "Scored before the plan distinguished lifting, so this session was judged against the running rubric."

    /// The same fact for VoiceOver, as one sentence appended after the score itself, so
    /// the number and the caveat are read as a single element rather than two unrelated
    /// labels — the treatment `MuscleGroupEntryData.accessibilityLabel` already gives.
    public static let labelledAccessibilitySuffix =
        "This score was assigned before the plan distinguished lifting."
}

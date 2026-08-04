import Foundation

/// The canonical, automatically assigned score for a workout (PRD §8 `score`, §10).
///
/// **This record is immutable (D8).** Every property is a `let`, there is no
/// `mutating` API, and there is deliberately no `copy(value:)` or `updating(...)`
/// helper — the only way to "change" a score is to attach a `ScoreAnnotation`
/// alongside it. That is not ceremony: the gap between the auto score and the manual
/// one *is* the scorer-quality metric in PRD §2, and an overwrite destroys exactly
/// the telemetry the project wants.
///
/// `isEffective` is computed rather than stored. Storing both a score and an
/// independently-settable "effective" flag makes a contradictory record
/// representable; storing the threshold that was in force instead makes the record
/// self-explaining and the flag impossible to falsify.
public struct Score: Hashable, Sendable, Codable, Identifiable {
    /// One auto-score per workout — §11's "no duplicate scores" — so the workout's id
    /// identifies the score too.
    public var id: UUID { workoutID }

    public let workoutID: UUID

    /// The plan version whose rubric produced this score (D1). Together with the
    /// stored `PlanDay`, this is what makes the score reproducible after the plan
    /// moves on.
    public let planVersion: PlanVersion

    /// What the plan asked for that day.
    public let scheduledSession: ScheduledSession

    /// What the classifier decided actually happened (§10.2).
    public let actualClassification: WorkoutClassification

    public let value: ScoreValue

    /// The effective-day threshold from the rubric in force when this was scored.
    public let effectiveThreshold: ScoreValue

    /// The rubric band that matched, when the scorer can name one. Provenance for
    /// "why did this run get a 62"; optional because a scorer that free-scores rather
    /// than band-matches should not have to invent an identifier.
    public let rubricBandIdentifier: String?

    /// One line for the verdict header (FR-1.1). Line breaks are rejected: a
    /// multi-line rationale silently breaks the header's layout contract, and the
    /// place to fix that is at the boundary, not in the view.
    public let rationale: String

    public let scoredAt: Date

    public init(
        workoutID: UUID,
        planVersion: PlanVersion,
        scheduledSession: ScheduledSession,
        actualClassification: WorkoutClassification,
        value: ScoreValue,
        effectiveThreshold: ScoreValue,
        rubricBandIdentifier: String? = nil,
        rationale: String,
        scoredAt: Date
    ) throws {
        try Validate.nonEmpty(rationale, "Score.rationale")
        guard !rationale.contains(where: { $0.isNewline }) else {
            throw DomainError.inconsistent(reason: "Score.rationale must be a single line")
        }
        if let rubricBandIdentifier {
            try Validate.nonEmpty(rubricBandIdentifier, "Score.rubricBandIdentifier")
        }
        self.workoutID = workoutID
        self.planVersion = planVersion
        self.scheduledSession = scheduledSession
        self.actualClassification = actualClassification
        self.value = value
        self.effectiveThreshold = effectiveThreshold
        self.rubricBandIdentifier = rubricBandIdentifier
        self.rationale = rationale
        self.scoredAt = scoredAt
    }

    /// §10.4 — effective at or above the threshold the plan set.
    public var isEffective: Bool { value >= effectiveThreshold }

    private enum CodingKeys: String, CodingKey {
        case workoutID, planVersion, scheduledSession, actualClassification
        case value, effectiveThreshold, rubricBandIdentifier, rationale, scoredAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            workoutID: container.decode(UUID.self, forKey: .workoutID),
            planVersion: container.decode(PlanVersion.self, forKey: .planVersion),
            scheduledSession: container.decode(ScheduledSession.self, forKey: .scheduledSession),
            actualClassification: container.decode(WorkoutClassification.self, forKey: .actualClassification),
            value: container.decode(ScoreValue.self, forKey: .value),
            effectiveThreshold: container.decode(ScoreValue.self, forKey: .effectiveThreshold),
            rubricBandIdentifier: container.decodeIfPresent(String.self, forKey: .rubricBandIdentifier),
            rationale: container.decode(String.self, forKey: .rationale),
            scoredAt: container.decode(Date.self, forKey: .scoredAt)
        )
    }
}

/// A manual correction, layered on top of an auto-score without touching it
/// (PRD §8 `score_annotation`, D8).
public struct ScoreAnnotation: Hashable, Sendable, Codable, Identifiable {
    public let id: UUID
    public let workoutID: UUID
    public let manualScore: ScoreValue
    /// Why the user disagreed. Optional, but it is the qualitative half of the
    /// correction-rate signal.
    public let note: String?
    public let createdAt: Date

    public init(
        id: UUID,
        workoutID: UUID,
        manualScore: ScoreValue,
        note: String? = nil,
        createdAt: Date
    ) throws {
        if let note {
            try Validate.nonEmpty(note, "ScoreAnnotation.note")
        }
        self.id = id
        self.workoutID = workoutID
        self.manualScore = manualScore
        self.note = note
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, workoutID, manualScore, note, createdAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            workoutID: container.decode(UUID.self, forKey: .workoutID),
            manualScore: container.decode(ScoreValue.self, forKey: .manualScore),
            note: container.decodeIfPresent(String.self, forKey: .note),
            createdAt: container.decode(Date.self, forKey: .createdAt)
        )
    }
}

/// An auto-score together with the corrections layered on it — the shape D8 actually
/// describes, made explicit so that consumers cannot accidentally read one half.
///
/// Tallies use `effectiveValue` (the correction, where one exists); the scorer-quality
/// metric uses `divergence`; the detail view shows both. Adding a correction returns a
/// *new* ledger and cannot alter `automatic`, which is the invariant the whole type
/// exists to enforce.
public struct ScoreLedger: Hashable, Sendable, Codable {
    public let automatic: Score
    /// Ascending by `createdAt`; the last one is the correction in force.
    public let annotations: [ScoreAnnotation]

    public init(automatic: Score, annotations: [ScoreAnnotation] = []) throws {
        for (index, annotation) in annotations.enumerated() {
            guard annotation.workoutID == automatic.workoutID else {
                throw DomainError.inconsistent(
                    reason: "ScoreLedger annotation \(annotation.id) belongs to a different workout"
                )
            }
            if index > 0, annotation.createdAt < annotations[index - 1].createdAt {
                throw DomainError.outOfOrder(field: "ScoreLedger.annotations", index: index)
            }
        }
        self.automatic = automatic
        self.annotations = annotations
    }

    /// The correction in force, if the user has made one.
    public var currentAnnotation: ScoreAnnotation? { annotations.last }

    /// What tallies count: the manual score where one exists, else the auto-score
    /// (§8, "where a manual annotation exists, tallies use it").
    public var effectiveValue: ScoreValue {
        currentAnnotation?.manualScore ?? automatic.value
    }

    /// Effectiveness judged against the threshold the plan set, applied to whichever
    /// score is in force.
    public var isEffective: Bool { effectiveValue >= automatic.effectiveThreshold }

    /// Manual minus automatic, in points — the correction-rate signal of PRD §2. Nil
    /// when the user has not corrected this score.
    public var divergence: Int? {
        currentAnnotation.map { $0.manualScore.points - automatic.value.points }
    }

    public var wasCorrected: Bool { currentAnnotation != nil }

    /// Additive by construction: the returned ledger carries the same `automatic`
    /// score, and there is no path in this type that replaces it.
    public func annotated(with annotation: ScoreAnnotation) throws -> ScoreLedger {
        try ScoreLedger(automatic: automatic, annotations: annotations + [annotation])
    }

    private enum CodingKeys: String, CodingKey {
        case automatic, annotations
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            automatic: container.decode(Score.self, forKey: .automatic),
            annotations: container.decode([ScoreAnnotation].self, forKey: .annotations)
        )
    }
}

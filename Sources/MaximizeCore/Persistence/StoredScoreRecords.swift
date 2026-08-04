import Foundation

/// `Score` as stored (PRD §8 `score`, §10).
///
/// ## D8 lives on the write path, not in this record
///
/// The auto-score is immutable, and nothing in a stored representation can enforce
/// that: every SwiftData property is settable by definition, so "immutable" has to be a
/// property of who is allowed to write. `ScoreRepository.recordAutomaticScore` is the
/// only door, and it refuses to replace a score that already exists. This record's
/// share of the job is to make a *contradictory* score unrepresentable on the way back
/// in — `Score.init` rejects a band that disagrees with the stored threshold, and
/// `toDomain()` goes through it.
///
/// `scheduledSession` is stored as a blob rather than three columns because it is the
/// plan's ask captured verbatim at scoring time. It exists here to make the score
/// reproducible after the plan moves on (D1), and nothing filters or sorts by it.
public struct StoredScore: Hashable, Sendable {
    public var workoutUUID: UUID
    public var planVersionNumber: Int

    /// A JSON-encoded `ScheduledSession`.
    public var scheduledSessionJSON: Data
    public var actualClassificationRawValue: String
    public var points: Int
    public var effectiveThresholdPoints: Int
    public var bandRawValue: String
    public var rubricBandIdentifier: String?
    public var rationale: String
    public var scoredAt: Date

    public init(
        workoutUUID: UUID,
        planVersionNumber: Int,
        scheduledSessionJSON: Data,
        actualClassificationRawValue: String,
        points: Int,
        effectiveThresholdPoints: Int,
        bandRawValue: String,
        rubricBandIdentifier: String?,
        rationale: String,
        scoredAt: Date
    ) {
        self.workoutUUID = workoutUUID
        self.planVersionNumber = planVersionNumber
        self.scheduledSessionJSON = scheduledSessionJSON
        self.actualClassificationRawValue = actualClassificationRawValue
        self.points = points
        self.effectiveThresholdPoints = effectiveThresholdPoints
        self.bandRawValue = bandRawValue
        self.rubricBandIdentifier = rubricBandIdentifier
        self.rationale = rationale
        self.scoredAt = scoredAt
    }

    public init(_ score: Score) throws {
        let scheduledSessionJSON = try PersistencePayload.encode(
            score.scheduledSession,
            field: "StoredScore.scheduledSessionJSON"
        )
        self.init(
            workoutUUID: score.workoutID,
            planVersionNumber: score.planVersion.number,
            scheduledSessionJSON: scheduledSessionJSON,
            actualClassificationRawValue: score.actualClassification.rawValue,
            points: score.value.points,
            effectiveThresholdPoints: score.effectiveThreshold.points,
            bandRawValue: score.band.rawValue,
            rubricBandIdentifier: score.rubricBandIdentifier,
            rationale: score.rationale,
            scoredAt: score.scoredAt
        )
    }

    /// - Note: `WorkoutClassification` and `ScoreBand` are closed enums, so an
    ///   unrecognised raw value is a corrupted or downgraded record rather than a new
    ///   variant to tolerate. Both fail loudly here. That is the opposite of
    ///   `StoredWorkout`'s treatment of `ActivityType`, and deliberately so: an unknown
    ///   activity type is a run we should still show, whereas an unknown score band is
    ///   a verdict this build cannot render or aggregate honestly.
    public func toDomain() throws -> Score {
        guard let classification = WorkoutClassification(rawValue: actualClassificationRawValue) else {
            throw DomainError.malformed(
                field: "StoredScore.actualClassificationRawValue",
                value: actualClassificationRawValue
            )
        }
        guard let band = ScoreBand(rawValue: bandRawValue) else {
            throw DomainError.malformed(field: "StoredScore.bandRawValue", value: bandRawValue)
        }
        return try Score(
            workoutID: workoutUUID,
            planVersion: try PlanVersion(planVersionNumber),
            scheduledSession: try PersistencePayload.decode(
                ScheduledSession.self,
                from: scheduledSessionJSON,
                field: "StoredScore.scheduledSessionJSON"
            ),
            actualClassification: classification,
            value: try ScoreValue(points),
            effectiveThreshold: try ScoreValue(effectiveThresholdPoints),
            band: band,
            rubricBandIdentifier: rubricBandIdentifier,
            rationale: rationale,
            scoredAt: scoredAt
        )
    }
}

/// `ScoreAnnotation` as stored (PRD §8 `score_annotation`, D8).
///
/// Additive by construction: annotations are separate records keyed by their own
/// identifier, so recording one cannot touch the auto-score. The divergence between the
/// two is the scorer-quality metric of PRD §2, and it only exists while both are on
/// record.
///
/// Note that `annotationUUID` is the record's own identity, not the workout's — a
/// workout may accumulate several corrections over time, and `ScoreLedger` keeps them
/// ordered by `createdAt`.
public struct StoredScoreAnnotation: Hashable, Sendable {
    public var annotationUUID: UUID
    public var workoutUUID: UUID
    public var manualScorePoints: Int
    public var note: String?
    public var createdAt: Date

    public init(
        annotationUUID: UUID,
        workoutUUID: UUID,
        manualScorePoints: Int,
        note: String?,
        createdAt: Date
    ) {
        self.annotationUUID = annotationUUID
        self.workoutUUID = workoutUUID
        self.manualScorePoints = manualScorePoints
        self.note = note
        self.createdAt = createdAt
    }

    public init(_ annotation: ScoreAnnotation) {
        self.init(
            annotationUUID: annotation.id,
            workoutUUID: annotation.workoutID,
            manualScorePoints: annotation.manualScore.points,
            note: annotation.note,
            createdAt: annotation.createdAt
        )
    }

    public func toDomain() throws -> ScoreAnnotation {
        try ScoreAnnotation(
            id: annotationUUID,
            workoutID: workoutUUID,
            manualScore: try ScoreValue(manualScorePoints),
            note: note,
            createdAt: createdAt
        )
    }
}

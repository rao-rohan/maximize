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

    /// The band the scorer resolved against that plan version, stored rather than
    /// recomputed (D2 applied to a classification). Nothing here turns a number into a
    /// band — `ScoreBand` deliberately has no `init(score:)`, and adding one in this
    /// type would be the same mistake wearing a different hat. What the initializer
    /// *does* enforce is that a stored band cannot contradict the stored threshold:
    /// `.effective` and a sub-threshold score is not a state worth representing. The
    /// marginal/ineffective split stays the scorer's judgement, made against the
    /// rubric's `marginalThreshold`.
    public let band: ScoreBand

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
        band: ScoreBand,
        rubricBandIdentifier: String? = nil,
        rationale: String,
        scoredAt: Date
    ) throws {
        guard (value >= effectiveThreshold) == (band == .effective) else {
            throw DomainError.inconsistent(
                reason: "Score band \(band.rawValue) contradicts score \(value) against threshold "
                    + "\(effectiveThreshold)"
            )
        }
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
        self.band = band
        self.rubricBandIdentifier = rubricBandIdentifier
        self.rationale = rationale
        self.scoredAt = scoredAt
    }

    /// §10.4 — effective at or above the threshold the plan set.
    public var isEffective: Bool { value >= effectiveThreshold }

    private enum CodingKeys: String, CodingKey {
        case workoutID, planVersion, scheduledSession, actualClassification
        case value, effectiveThreshold, band, rubricBandIdentifier, rationale, scoredAt
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
            band: container.decode(ScoreBand.self, forKey: .band),
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
/// exists to enforce. The same is true of a label (MAX-143): `labelled(with:)` returns a
/// new ledger carrying the same `automatic`, and there is no path here that replaces it.
public struct ScoreLedger: Hashable, Sendable, Codable {
    public let automatic: Score
    /// Ascending by `createdAt`; the last one is the correction in force.
    public let annotations: [ScoreAnnotation]

    /// Marks saying this auto-score was written against the wrong discipline's ask, and
    /// is therefore not evidence about scorer quality (A21, MAX-143). Ascending by
    /// `recordedAt`.
    ///
    /// **An array rather than an optional, and duplicates are tolerated rather than
    /// rejected.** Labelling is one fact about a score, so a second label says nothing
    /// new — but the label is a record keyed by its own identifier, and two devices
    /// running the pass before either has synced is precisely the "improbable, not
    /// impossible" case `WorkoutRepository` already declines to write an app around.
    /// Resolving that deterministically here (`isMiscategorised` is a property of the
    /// set, not a count) is what makes labelling twice cost nothing.
    public let labels: [MiscategorisedScoreLabel]

    public init(
        automatic: Score,
        annotations: [ScoreAnnotation] = [],
        labels: [MiscategorisedScoreLabel] = []
    ) throws {
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
        for (index, label) in labels.enumerated() {
            guard label.workoutID == automatic.workoutID else {
                throw DomainError.inconsistent(
                    reason: "ScoreLedger label \(label.id) belongs to a different workout"
                )
            }
            // A label states the ask the score was judged against. If that disagrees with
            // the score's own stored prescription, one of the two is describing a
            // different score, and silently trusting either would drop a real divergence
            // out of the scorer-quality metric.
            guard label.judgedAgainst == automatic.scheduledSession.kind else {
                throw DomainError.inconsistent(
                    reason: "ScoreLedger label \(label.id) says the score was judged against "
                        + "\(label.judgedAgainst.rawValue), but the score records "
                        + "\(automatic.scheduledSession.kind.rawValue)"
                )
            }
            if index > 0, label.recordedAt < labels[index - 1].recordedAt {
                throw DomainError.outOfOrder(field: "ScoreLedger.labels", index: index)
            }
        }
        self.automatic = automatic
        self.annotations = annotations
        self.labels = labels
    }

    /// The correction in force, if the user has made one.
    public var currentAnnotation: ScoreAnnotation? { annotations.last }

    /// The label, if this score carries one — the **earliest**, since labelling is a
    /// single fact and the first statement of it is the one that was made.
    public var miscategorisationLabel: MiscategorisedScoreLabel? { labels.first }

    /// Whether this auto-score is known to have been judged against the wrong
    /// discipline's ask (A21, MAX-143).
    public var isMiscategorised: Bool { !labels.isEmpty }

    /// What tallies count: the manual score where one exists, else the auto-score
    /// (§8, "where a manual annotation exists, tallies use it").
    public var effectiveValue: ScoreValue {
        currentAnnotation?.manualScore ?? automatic.value
    }

    /// Effectiveness judged against the threshold the plan set, applied to whichever
    /// score is in force.
    public var isEffective: Bool { effectiveValue >= automatic.effectiveThreshold }

    /// Whether this ledger is evidence about the scorer at all (PRD §2, A21).
    ///
    /// False for a labelled score, and that exclusion is the point of MAX-143: the model
    /// was handed a category error rather than misjudging a run, so counting the gap
    /// between its answer and the athlete's would measure the question, not the scorer.
    ///
    /// Exposed as its own property so an aggregate over many ledgers — a correction rate,
    /// which nothing computes yet — filters on the same predicate `divergence` already
    /// applies, instead of re-deriving the rule and getting it slightly different.
    public var countsTowardScorerQuality: Bool { !isMiscategorised }

    /// Manual minus automatic, in points — the correction-rate signal of PRD §2.
    ///
    /// Nil when the user has not corrected this score, **and nil when the score is
    /// labelled miscategorised** (A21, MAX-143). This is the metric, not the arithmetic:
    /// the subtraction is only meaningful when the auto-score was the answer to the right
    /// question, so the exclusion belongs here rather than in each future consumer, where
    /// one of them would forget it.
    ///
    /// A labelled score whose value the athlete *has* corrected is still nil. The
    /// correction stands and still drives `effectiveValue`; what it is not is evidence
    /// about the scorer, because the thing it diverges from is not the scorer's judgement
    /// of this session.
    public var divergence: Int? {
        guard countsTowardScorerQuality else { return nil }
        return currentAnnotation.map { $0.manualScore.points - automatic.value.points }
    }

    /// Whether the athlete recorded a correction. **Unaffected by labelling**, on purpose:
    /// a label says the auto-score is not evidence about the scorer, not that the
    /// correction never happened. Erasing it here would rewrite the athlete's record,
    /// which is the failure mode this whole ticket exists to avoid.
    public var wasCorrected: Bool { currentAnnotation != nil }

    /// Additive by construction: the returned ledger carries the same `automatic`
    /// score, and there is no path in this type that replaces it.
    public func annotated(with annotation: ScoreAnnotation) throws -> ScoreLedger {
        try ScoreLedger(
            automatic: automatic,
            annotations: annotations + [annotation],
            labels: labels
        )
    }

    /// Additive in exactly the way `annotated(with:)` is, and for the same reason: the
    /// returned ledger carries the identical `automatic` score, byte for byte (D8).
    public func labelled(with label: MiscategorisedScoreLabel) throws -> ScoreLedger {
        try ScoreLedger(
            automatic: automatic,
            annotations: annotations,
            labels: labels + [label]
        )
    }

    private enum CodingKeys: String, CodingKey {
        case automatic, annotations, labels
    }

    /// **`labels` is omitted when empty** (MAX-143), for the reason MAX-129 gave for
    /// `liftSession` and MAX-131 for `durationSeconds`: every ledger already encoded
    /// carries no labels, so leaving the key out leaves those bytes exactly as they are,
    /// and a payload written before this ticket decodes to a ledger with no labels —
    /// which is precisely what it meant.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(automatic, forKey: .automatic)
        try container.encode(annotations, forKey: .annotations)
        if !labels.isEmpty {
            try container.encode(labels, forKey: .labels)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            automatic: container.decode(Score.self, forKey: .automatic),
            annotations: container.decode([ScoreAnnotation].self, forKey: .annotations),
            labels: container.decodeIfPresent([MiscategorisedScoreLabel].self, forKey: .labels) ?? []
        )
    }
}

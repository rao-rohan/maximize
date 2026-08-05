import Foundation

/// What a prescribed lift is *for* — the muscle groups a plan distributes across the
/// training week (A17, owner's scope addition to MAX-129).
///
/// ## A training-plan vocabulary, not an anatomy one
///
/// The list is the granularity a weekly split is actually written at. Every common way
/// of splitting a lifting week — push/pull/legs, upper/lower, a five-day
/// one-group-per-day split — is expressible with these six and without reaching for a
/// residual case, which is the test this list was chosen to pass. Going finer (biceps
/// and triceps rather than arms, quads and hamstrings rather than legs) would let a
/// plan state distinctions no athlete writing a week actually makes, and would put two
/// spellings of the same Tuesday in the vocabulary.
///
/// Closed, and closed for `Discipline`'s reason: a case here is a claim about how
/// training is organised, so adding one should cost a conversation rather than a commit
/// nobody reads.
///
/// ## "Full body" is the whole set, not a seventh case
///
/// A `fullBody` case would overlap every other case, and overlap is what makes a set
/// stop answering questions: "does this Tuesday work chest?" would have two paths to an
/// answer and they could disagree. The complete set says the same thing with no
/// ambiguity, and `MuscleGroup.fullBody` names it so a caller does not have to spell out
/// six cases to mean "everything".
///
/// ## What this cannot do
///
/// **Nothing verifies it.** HealthKit reports `traditionalStrengthTraining` and says
/// nothing about what was worked, exactly as it says nothing about sets, reps or load —
/// the wall A20 hit when it chose adherence over volume. So a prescription can say
/// "chest and shoulders" and the app cannot check that it happened. That is a known,
/// deliberate gap: this type is what a plan may **state**, and nothing on the scoring,
/// tallies or adherence path reads it. Closing the gap is a product decision with real
/// costs on every branch (see `PROJECT_TRACKER.md`), and it needs an amendment rather
/// than a quietly-added rule here.
public enum MuscleGroup: String, Hashable, Sendable, Codable, CaseIterable {
    case chest
    case back
    case shoulders
    case arms
    case legs
    /// Trunk work — abs, obliques, lower back. Named `core` rather than `abs` because
    /// a plan that prescribes it means the whole trunk, and because that is the word
    /// the week is written in.
    case core

    /// Every group. See the type note on why this is a constant rather than a case.
    public static let fullBody: Set<MuscleGroup> = Set(MuscleGroup.allCases)
}

extension Set where Element == MuscleGroup {
    /// The groups in `MuscleGroup.allCases` order.
    ///
    /// A `Set` has no order, and two places need one: the encoder, so that an unchanged
    /// prescription re-encodes to identical bytes (`PersistencePayload` spells out why
    /// that matters), and anything that renders or speaks the list, so the same Tuesday
    /// does not read "shoulders, chest" once and "chest, shoulders" the next launch.
    /// One canonical order serves both, and `CaseIterable` already is one.
    public var ordered: [MuscleGroup] {
        MuscleGroup.allCases.filter { contains($0) }
    }
}

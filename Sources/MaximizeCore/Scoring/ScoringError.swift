import Foundation

/// Why a workout could not be scored.
///
/// Separate from `DomainError` because these are not "a value violated an invariant"
/// — they are failures of the scoring *transaction*, and the two families want
/// different responses. A `DomainError` means a caller built something impossible and
/// the fix is in the caller. A `ScoringError` splits further, along the one line that
/// matters to MAX-023: some of these mean *the model answered badly and asking again
/// might work*; the rest mean *the plan data or the caller is wrong and asking again
/// will fail identically*. `isWorthRetrying` is that distinction, made explicit so the
/// client does not have to infer it from the case name.
///
/// ## `description` never carries the workout or the day (MAX-156)
///
/// `noPlanInEffect` and `contextAlreadyScored` carry a `CalendarDay` and a workout
/// `UUID` as associated values — real identifying data about the athlete's training,
/// not a status a server put on the wire. Before this ticket `description` interpolated
/// both, on the same "diagnostic, read in a debugger" theory that lets
/// `ScoringModelError.description` carry a status code: latent, because the one call
/// site that logs a `ScoringError` (`IngestionComposition`) logs at `.private`, but a
/// `description` is a plain `String` — nothing prevents a future caller from logging it
/// `.public`, showing it on screen, or handing it to a crash reporter, and CLAUDE.md's
/// "Health and privacy" rule does not carry a "the current caller happens to be careful"
/// exception. So the payload is gone from every case's sentence, not audited caller by
/// caller.
///
/// A caller that genuinely needs the day or the workout still has it: `switch`ing on
/// `.noPlanInEffect(let day)` or `.contextAlreadyScored(let workoutID)` reaches the typed
/// value directly. That is the "separate channel" the value lives on — pattern matching
/// on a specific case rather than a blanket `String(describing:)` of any `Error` — and it
/// is safe precisely because it takes a caller writing that case name on purpose, the
/// same deliberateness `CLAUDE.md` asks for everywhere else health data is handled. No
/// second property was added to duplicate what the enum's own payload already offers.
public enum ScoringError: Error, Hashable, Sendable, CustomStringConvertible {

    // MARK: - The run cannot be scored at all

    /// No plan version governed the workout's day, so there is no rubric to apply.
    ///
    /// A real state, not a bug: the athlete existed before the app did, and
    /// `PlanCalendar` deliberately answers nil rather than inventing an ask
    /// (see `PlanCalendar.plan(on:)`). Such a workout is stored and displayed; it is
    /// simply not scored, because a score against no plan would be a number with no
    /// stated meaning.
    case noPlanInEffect(day: CalendarDay)

    /// The context handed to the scorer already carried a score.
    ///
    /// `WorkoutContext.existingScore` is documented as present for chat and **absent
    /// when scoring**: a scorer shown a previous verdict is being invited to agree with
    /// it. Rejecting it here enforces at the boundary what MAX-014 could only state in
    /// prose. It also blocks the accidental second auto-score that §11's "no duplicate
    /// scores" and D8's immutability both forbid.
    case contextAlreadyScored(workoutID: UUID)

    /// No rubric band matched, so the rubric has nothing to say about this run.
    ///
    /// **Deliberately fatal rather than defaulted.** The tempting alternative — fall
    /// back to some catch-all range — would put a score range in Swift, which is
    /// precisely the D1 violation the rubric exists to prevent. A rubric that cannot
    /// classify a run it was handed is incomplete plan data, and the repair is a new
    /// plan version with a catch-all band, authored by a human who can decide what an
    /// unrecognised run is worth.
    case noBandMatched(scheduled: ScheduledSessionKind, actual: WorkoutClassification)

    // MARK: - The model answered badly

    /// The response was not the single JSON object the contract asks for.
    case malformedResponse(reason: String)

    /// The proposed score was outside 0...100 and so is not a score at all.
    case scoreOutOfPermittedRange(proposed: Int)

    /// The proposed score was a valid score but fell outside the range the matched
    /// rubric band permits — the model ignored the constraint it was given.
    ///
    /// Rejected rather than clamped. `ScoreValue.clamping` exists and would silently
    /// produce a plausible number here, which is exactly why it is not used: a model
    /// that disregards its bounds is a fact worth surfacing, and clamping would hide
    /// it behind a score that looks hand-picked.
    case scoreOutsideBand(identifier: String, proposed: Int, permitted: ScoreRange)

    /// The rationale did not satisfy the header's one-line contract.
    case rationaleRejected(reason: String)

    /// Whether re-asking the model could plausibly succeed.
    ///
    /// True only for the model's own faults. The structural cases are deterministic in
    /// the plan data and the context: retrying them burns a token budget to receive the
    /// same failure, and — worse — invites a retry loop around a workout that will
    /// never score, which is the shape of R11's wedged pipeline.
    public var isWorthRetrying: Bool {
        switch self {
        case .noPlanInEffect, .contextAlreadyScored, .noBandMatched:
            return false
        case .malformedResponse, .scoreOutOfPermittedRange, .scoreOutsideBand, .rationaleRejected:
            return true
        }
    }

    public var description: String {
        switch self {
        case .noPlanInEffect:
            // No `day` here — see this type's note. The case name already says which
            // fact is missing; the date it was missing on is not this string's to carry.
            return "No plan version was in effect on this workout's day, so there is no rubric to score against"
        case .contextAlreadyScored:
            // No `workoutID` here, for the same reason.
            return "This workout already has a score; scoring context must not carry one"
        case let .noBandMatched(scheduled, actual):
            return "No rubric band matched a \(actual.rawValue) workout on a \(scheduled.rawValue) day. "
                + "The rubric needs a catch-all band for this combination"
        case let .malformedResponse(reason):
            return "The scoring response was malformed: \(reason)"
        case let .scoreOutOfPermittedRange(proposed):
            return "Proposed score \(proposed) is outside \(ScoreValue.permittedRange)"
        case let .scoreOutsideBand(identifier, proposed, permitted):
            return "Proposed score \(proposed) is outside \(permitted), the range band "
                + "\"\(identifier)\" permits"
        case let .rationaleRejected(reason):
            return "The rationale was rejected: \(reason)"
        }
    }
}

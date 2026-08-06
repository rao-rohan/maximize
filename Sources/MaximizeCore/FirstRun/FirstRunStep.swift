import Foundation

/// One thing a fresh install still needs from the athlete, and nothing else (MAX-162,
/// FIRST-RUN-SPEC §2).
///
/// ## Three cases, and deliberately no fourth
///
/// **This type models no completion.** There is no `isComplete`, no `.done`, no
/// `completedAt`, and no case that stands for a step that has been taken. A step is
/// *outstanding* or it is *absent from the checklist*, and absence is expressed by the
/// step not appearing in `FirstRunChecklist.remainingSteps` rather than by a flag beside
/// it.
///
/// That is a structural answer to tracker **R10**, not a stylistic one.
/// `HKHealthStore.authorizationStatus(for:)` reports *share* status only — Apple does not
/// expose read status, by design — so the app cannot establish that Health read access
/// was granted. A checklist is the single most dangerous shape for that fact, because a
/// checklist wants a tick beside every row and the athlete has visibly just answered a
/// permission sheet. A tick would be a claim the app cannot make. So there is no state
/// for a tick to be drawn from: a view cannot render "Health ✓" because no value in this
/// module means it. See FIRST-RUN-SPEC §9.1 and `FirstRunCopy`'s R10 note.
///
/// ## The order is the recoverability order
///
/// `allCases` is the order the athlete is asked in, and the order is not editorial: it is
/// `recovery`, ascending. What is lost while a step is outstanding, and whether doing it
/// later recovers that loss, is the whole ranking (FIRST-RUN-SPEC §2), and stating it as
/// a property rather than as case order means a step added later has to answer the same
/// question to get a position. `FirstRunChecklistTests` asserts the two agree.
public enum FirstRunStep: String, Hashable, Sendable, CaseIterable {

    /// Put the iOS Health permission question to the athlete.
    ///
    /// Asked first because nothing arrives until it is answered, and because iOS presents
    /// the sheet once per install — a step that cannot be offered twice is a step that
    /// goes first. **Answering it is not the same as granting it**, and no value here
    /// records either.
    case requestHealthAccess

    /// Write plan version 1.
    ///
    /// Asked second. Capture still works without a plan — the workout, its samples and
    /// its route are all stored — but derived metrics, a score, a calendar colour and
    /// chat about that run are not, and `WorkoutIngestionPipeline` reports
    /// `.storedWithoutPlan(.noPlanAuthored)`.
    case authorAPlan

    /// Store an Anthropic API key in the device's Keychain.
    ///
    /// Asked last, and the reason is the argument this ordering exists to make: it is the
    /// only step that costs the athlete money, and the only one that costs nothing to
    /// defer. Scoring is retried when a workout is next opened
    /// (`completeIngestion(forWorkout:)`, MAX-033), so a key entered on day thirty scores
    /// the previous thirty days. Asking for a paid key before the app has shown a person
    /// one of their own runs is asking them to fund a promise.
    case addAnAPIKey

    /// What is lost while this step is outstanding, and whether doing it later recovers
    /// it. The ask order is this, ascending.
    public var recovery: FirstRunStepRecovery {
        switch self {
        case .requestHealthAccess: return .nothingArrivesUntilItIsAnswered
        case .authorAPlan: return .onlyFromTheDateItIsEventuallyGiven
        case .addAnAPIKey: return .fullyRecoveredWheneverItIsDone
        }
    }
}

/// How much of what a step gates is still available if the step is done later
/// (FIRST-RUN-SPEC §2).
///
/// The intuitive first-run order is key-first, because a key feels like "setup". That
/// order is wrong, and this type is why: ranked by what a delay costs, the key is last.
public enum FirstRunStepRecovery: Int, Hashable, Sendable, CaseIterable, Comparable {

    /// Total and silent. While it is outstanding no workout arrives at all, so there is
    /// nothing to plan against, score, chart or ask about — and an app receiving nothing
    /// looks exactly like an app whose athlete has not run. Doing it later recovers only
    /// as far back as the ingester's ninety-day backfill reaches; a month of not noticing
    /// is a month gone.
    case nothingArrivesUntilItIsAnswered = 0

    /// Partial, and the lost part is lost permanently. Everything from the date the
    /// athlete eventually chooses is measured; everything before it is
    /// `.workoutPredatesEveryPlan`, which never resolves, because MAX-011 forbids a later
    /// plan version from opening before an earlier one.
    case onlyFromTheDateItIsEventuallyGiven = 1

    /// Total while outstanding, and completely recovered when it is done. Nothing is
    /// scored and chat cannot open without a key, but every workout already captured is
    /// scored when it is next opened. Nothing is lost by waiting.
    case fullyRecoveredWheneverItIsDone = 2

    public static func < (lhs: FirstRunStepRecovery, rhs: FirstRunStepRecovery) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// What the setup card on the Workouts tab is showing, or `nil` for no card
/// (FIRST-RUN-SPEC §5.2, §8).
///
/// One case per rendering, so the card switches over a value and decides nothing itself.
/// The card shows **one** state at a time: one heading, one sentence, at most one button
/// (§5.3). The remaining steps are not hidden — `FirstRunChecklist.remainingSteps`
/// carries them — they are simply not yet the question.
///
/// Three of these are Health states and none of them is a *result*. `step` answers what
/// the card's button does, and it is `nil` wherever there is nothing an athlete can
/// usefully press.
public enum FirstRunCardState: String, Hashable, Sendable, CaseIterable {

    /// §5.2 state 1 — the permission sheet has never been presented on this device.
    ///
    /// Unreachable in practice once MAX-163's cover exists, reachable in the type: a
    /// cover dismissed by a crash, a defaults write that did not land.
    case healthAccessNotRequested

    /// The request was made and did not complete (`HealthAccessState.requestFailed`).
    ///
    /// Not folded into `healthAccessNotRequested`: that state's copy says the question
    /// has not been put, which after a failed request is false. Both offer the same
    /// action, because asking again is the fix for both.
    case healthRequestDidNotComplete

    /// `HealthAccessState.healthDataUnavailable` — this device has no Health store.
    ///
    /// **Not in the spec's five states**, and added because `FirstRunChecklist` takes a
    /// `HealthAccessState` and that enum has four cases. Distinct from a refusal, which
    /// HealthKit does not disclose. It carries no action: the athlete cannot install a
    /// Health store, and offering "Request Health access" on a device that has none is a
    /// button that can only fail.
    case healthDataUnavailable

    /// §5.2 state 2 — no plan version is stored.
    case noPlanAuthored

    /// §5.2 state 3 — the Keychain was read and holds no key.
    ///
    /// Reached only from `StoredAPIKeyPresence.notStored`. A read that *failed*
    /// (`.unknown`) does not reach here — see `FirstRunChecklist`.
    case noAPIKeyStored

    /// §8, state 4 — every step is behind them and no workout is stored yet.
    ///
    /// This window lasts until the athlete's next run syncs: realistically hours,
    /// legitimately days. It is the app working correctly, and it is neither a failure
    /// nor an empty list.
    case awaitingFirstWorkout

    /// The action this card offers, or `nil` for a card that is telling the athlete
    /// something rather than asking them for something.
    public var step: FirstRunStep? {
        switch self {
        case .healthAccessNotRequested, .healthRequestDidNotComplete:
            return .requestHealthAccess
        case .noPlanAuthored:
            return .authorAPlan
        case .noAPIKeyStored:
            return .addAnAPIKey
        case .healthDataUnavailable, .awaitingFirstWorkout:
            return nil
        }
    }
}

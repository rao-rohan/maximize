import Foundation

/// A surface outside chat that can tell an athlete a read did not work.
///
/// One case per screen or section that owns a `.failed` load state, so the mapping from
/// "this load failed" to "this is what the person reads" is a value CI can enumerate
/// rather than a string typed into a `catch` block. Chat's own surfaces are deliberately
/// absent: `ChatConversationCopy.failedToLoad(for:)` owns those, and a second type
/// answering the same question for the same screen is the drift both exist to prevent.
public enum LoadFailureSurface: String, Hashable, Sendable, CaseIterable {
    /// The workouts tab's list (`WorkoutsListModel.LoadState.failed`).
    case workoutList

    /// One workout's detail screen (`WorkoutDetailModel.LoadState.failed`).
    ///
    /// **Not yet wired.** `App/Workouts/WorkoutDetailView.swift` belongs to another
    /// ticket in flight (MAX-139), so MAX-154 defined the sentence and left the call
    /// site alone rather than editing a file it was told not to take. The string is
    /// tested here like every sibling; adopting it is a one-line change in that view.
    case workoutDetail

    /// The dashboard's score-coloured calendar (`ScoreCalendarModel.LoadState.failed`).
    case scoreCalendar

    /// The dashboard's heart-rate drift section (`DriftOverlayModel.LoadState.failed`).
    case heartRateDrift

    /// The dashboard's summary tiles (`TrendTilesModel.LoadState.failed`).
    case trendTiles

    /// The plan tab (`PlanViewModel.LoadState.failed`, with `version == nil`).
    case plan

    /// One historical plan version's screen (`PlanViewModel.LoadState.failed`, with a
    /// version pinned).
    case planVersion

    /// The plan authoring screen (`PlanAuthoringModel.LoadState.failed`).
    case planAuthoring

    /// The settings screen's stored preferences (`SettingsModel.LoadState.failed`).
    case settings
}

/// What the app can honestly say about whether an Anthropic API key is stored.
///
/// Three states, not a `Bool`, because the Keychain read itself can fail. Before
/// MAX-154 a failed read set the screen's flag to `false`, so a device that could not
/// be asked said "No key is stored." — a claim about the world the app had just failed
/// to establish. `unknown` is the honest third answer.
///
/// **No case, and no copy derived from one, says anything about the key itself** — not
/// its length, not its prefix, not the account it belongs to. Presence is the entire
/// vocabulary, and it is shown on screen only, never logged (CLAUDE.md).
public enum StoredAPIKeyPresence: Hashable, Sendable, CaseIterable {
    case stored
    case notStored
    case unknown

    /// Whether a **Clear** affordance should be offered.
    ///
    /// True for `unknown` as well as `stored`: a read that failed is not evidence that
    /// nothing is there, and withholding the only control that removes a key from a
    /// device where one may well be stored is the wrong side to err on.
    public var permitsClearing: Bool {
        switch self {
        case .stored, .unknown: return true
        case .notStored: return false
        }
    }
}

/// Everything the API key section of Settings can say after an action.
///
/// One enum rather than six strings assembled in `catch` blocks, for the reason
/// `ChatConversationCopy` gives for pulling the last two `ChatModel.LoadState` cases
/// down into the core (MAX-150): a status line whose values come half from a core type
/// and half from view literals is one state machine with two voices.
public enum APIKeyStatusMessage: Hashable, Sendable, CaseIterable {
    /// The key was written to the store.
    case saved

    /// The stored key was removed.
    case cleared

    /// `AnthropicAPIKeyError.emptyKey` — the field held nothing, or only whitespace.
    case enterAKeyFirst

    /// The store could not be read, so presence is unknown. Pairs with
    /// `StoredAPIKeyPresence.unknown`.
    case couldNotCheck

    /// The write failed. The entered text is cleared by the caller, and the copy says
    /// so, because a field that silently empties itself reads as a bug.
    case couldNotSave

    /// The delete failed, so a key may still be on the device.
    case couldNotClear
}

/// What the app knows about Apple Health access — which is deliberately less than an
/// app is usually able to say.
///
/// **Tracker R10 is the whole design of this type.** `HKHealthStore
/// .authorizationStatus(for:)` reports *share* status only; Apple does not expose read
/// status, by design, so that an app cannot distinguish "denied" from "no data
/// recorded" and infer something about the person from the difference. There is
/// therefore no `granted` case and no `denied` case here, and no copy below claims
/// either. The strongest true statement available is that the sheet was answered.
public enum HealthAccessState: Hashable, Sendable, CaseIterable {
    /// The permission sheet has not been presented on this launch.
    case notRequestedYet

    /// The sheet was presented and answered. What it was answered *with* is not
    /// knowable — see the type's note.
    case requestAnswered

    /// `HealthKitObserverError.healthDataUnavailable` — this device has no Health
    /// store at all. Distinct from a refusal, which HealthKit does not disclose.
    case healthDataUnavailable

    /// The request did not complete. Never carries the underlying error: an arbitrary
    /// `Error` from HealthKit may carry sample values in its `userInfo`, and health
    /// data does not go into strings a person or a log can read (CLAUDE.md).
    case requestFailed
}

/// The single place a failure outside chat becomes a sentence.
///
/// ## Why this is in the core
///
/// CLAUDE.md: "All logic lives in `MaximizeCore`." Deciding what a person is told when
/// something fails is a decision, and before MAX-154 it was made in nine different
/// `catch` blocks and `switch` arms across `App/`, none of which CI can execute. The
/// audit that opened this ticket found the predictable result — four different verbs
/// for the same event ("Could not load workouts.", "Couldn't load the plan.",
/// "Couldn't load the calendar.", "Couldn't load this plan version."), a dashboard that
/// rendered nothing at all when it could not resolve today's date, and a Keychain read
/// failure that resolved to a confident claim that no key was stored.
///
/// ## Two rules every string below keeps
///
/// - **A failure is not an absence.** "No workouts recorded yet" and "your workouts
///   could not be read" are different sentences about different worlds, and CLAUDE.md's
///   "absence is a designed state" is not satisfied by collapsing them. `couldNotLoad`
///   and `noWorkoutsRecorded` are separate for exactly that reason, and a test asserts
///   they never coincide.
/// - **Nothing here names a type, a code, a framework or an error.** Not `OSStatus`,
///   not `HKError`, not a status code, not a case name, not "nil". A person reading a
///   failure state is owed a description of what happened to them, and a diagnostic is
///   not one. `ScoringModelError.description` and friends stay as they are — those are
///   written for a developer reading a debugger, and none of them reaches a screen.
///
/// And one rule that is about privacy rather than voice: **no string below interpolates
/// anything.** Every value is a fixed literal, so there is no argument through which a
/// workout, a date, an identifier or a key could reach a rendered sentence.
public enum FailureCopy {

    // MARK: - A read that did not work

    /// What a surface says in place of its content when a load failed.
    ///
    /// Exhaustive over `LoadFailureSurface` with no `default`, so a surface added later
    /// fails to compile here rather than inheriting a neighbour's wording.
    public static func couldNotLoad(_ surface: LoadFailureSurface) -> String {
        switch surface {
        case .workoutList:
            return "Your workouts could not be loaded. This is a problem reading them on "
                + "this device, not a sign that none were recorded."
        case .workoutDetail:
            return "This workout could not be loaded."
        case .scoreCalendar:
            return "The calendar could not be loaded."
        case .heartRateDrift:
            return "The runs in this interval could not be loaded."
        case .trendTiles:
            return "The summary for this interval could not be loaded."
        case .plan:
            return "Your plan could not be loaded. Nothing about the plan itself has changed."
        case .planVersion:
            return "This plan version could not be loaded."
        case .planAuthoring:
            return "Your plan could not be loaded, so nothing written here would be saved."
        case .settings:
            return "Your settings could not be loaded, so changes here would not be saved."
        }
    }

    // MARK: - Absence, which is not failure

    /// Shown when the workout list loaded successfully and holds nothing.
    ///
    /// **The second sentence is R10.** iOS never tells an app whether Health *read*
    /// access was granted, so "no workouts yet" is not something this app can establish
    /// on its own — an empty list is equally consistent with a refused read. The copy
    /// therefore states the ordinary reading first and names the other possibility
    /// second, without asserting either and without claiming to know whether Health is
    /// "connected", which is the claim R10 forbids.
    public static let noWorkoutsRecorded =
        "No workouts yet. iOS never tells an app whether Health access was granted, so if "
            + "you have recorded some, check Maximize under Settings › Health › Data Access & Devices."

    // MARK: - The dashboard's clock

    /// The dashboard's interval selector when today's date could not be resolved.
    ///
    /// Reachable only for a system clock outside `CalendarDay`'s 1...9999 AD domain,
    /// and stated rather than assumed away — the same treatment
    /// `TrendIntervalSelectionModel.State.failed` already gives it.
    public static let todaysDateUnresolved = "Today's date could not be worked out on this device."

    /// The dashboard's body in that same state.
    ///
    /// Before MAX-154 this state drew *nothing* below the selector — the calendar, the
    /// drift section and the tiles were simply absent, with the selector's one line the
    /// only hint that anything was wrong. A blank is not a designed state.
    public static let dashboardUnavailableWithoutToday =
        "The calendar, drift and summary all measure against today, so none of them can be "
            + "shown until this device's date can be read."

    // MARK: - The Anthropic API key

    /// What the settings screen says about whether a key is stored.
    ///
    /// Exhaustive with no `default`. Says nothing about the key beyond whether one is
    /// there, and admits when it does not know.
    public static func storedKeyPresence(_ presence: StoredAPIKeyPresence) -> String {
        switch presence {
        case .stored:
            return "A key is stored."
        case .notStored:
            return "No key is stored."
        case .unknown:
            return "Whether a key is stored could not be checked on this device."
        }
    }

    /// The status line under the key field, after an action.
    ///
    /// Exhaustive with no `default`.
    public static func apiKeyStatus(_ message: APIKeyStatusMessage) -> String {
        switch message {
        case .saved:
            return "Key saved."
        case .cleared:
            return "Key cleared."
        case .enterAKeyFirst:
            return "Enter a key first."
        case .couldNotCheck:
            return "Whether a key is stored could not be checked, so the state above may be wrong."
        case .couldNotSave:
            return "The key could not be saved. The field has been cleared — enter it again."
        case .couldNotClear:
            return "The key could not be cleared, so it may still be stored on this device."
        }
    }

    // MARK: - Apple Health

    /// What the Health section of Settings says.
    ///
    /// Exhaustive with no `default`. **No case claims access was granted** — see
    /// `HealthAccessState` and tracker R10.
    public static func healthAccess(_ state: HealthAccessState) -> String {
        switch state {
        case .notRequestedYet:
            return "Health access has not been requested yet on this launch."
        case .requestAnswered:
            return "Health access was requested. iOS does not report whether read access was "
                + "granted; workouts will appear here if it was."
        case .healthDataUnavailable:
            return "This device does not provide Health data, so workouts cannot be captured "
                + "from it."
        case .requestFailed:
            return "The Health access request did not complete. Try it again."
        }
    }

    // MARK: - Writing a plan

    /// The plan authoring screen when a draft could not be turned into a candidate for
    /// a reason `PlanAuthoringError` does not name.
    ///
    /// `PlanAuthoringError.description` is already athlete-facing and already in the
    /// core, and it is preferred wherever it applies; this is the sentence for the
    /// `catch` that follows it.
    public static let planCouldNotBePrepared =
        "This plan could not be prepared. Check the values above."

    /// The same screen when the write itself failed.
    public static let planVersionCouldNotBeSaved =
        "This plan version could not be saved. Try again."
}

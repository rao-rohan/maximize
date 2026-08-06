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
/// something fails is a decision, and before MAX-154 it was made in two dozen string
/// literals spread over eleven files in `App/`, none of which CI can execute. The
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

    // MARK: - The store itself, which is not a screen

    /// What the app says when its one store did not open (MAX-169).
    ///
    /// `nil` for `.open`: there is nothing to say when the ordinary thing happened, and a
    /// caller that renders a notice whenever one exists therefore needs no second question.
    ///
    /// ## Why this is one sentence about the app and not nine about screens
    ///
    /// `couldNotLoad(_:)` above answers "this surface's read did not work" — a local
    /// problem, worded locally, and correct for a read that failed while the store is
    /// perfectly healthy. When the *store* is what did not open, every one of those nine
    /// surfaces says its own version of it at once, and an athlete reads five separate
    /// bugs rather than the single fact that there is nowhere to read from and nowhere to
    /// write to. This is that fact, said once, in the one place that knows it.
    ///
    /// ## The three things every failure body says
    ///
    /// - **Nothing has been deleted.** The most likely reaction to a screen like this is
    ///   to reinstall the app, and with CloudKit deferred (A8) that would destroy the only
    ///   copy of the athlete's history. So the body says what is true — the history is
    ///   there and unread — before it says anything else.
    /// - **Nothing is being saved either.** The screens being empty is the visible half;
    ///   the invisible half is that ingestion has nowhere to write. Saying only the first
    ///   would leave someone believing their runs are piling up safely somewhere.
    /// - **The runs recorded meanwhile are not lost.** True by construction: with no store
    ///   the ingestion sink pins the HealthKit anchor rather than acknowledging the batch
    ///   (R9/R12), so a later launch refetches exactly what this one could not take.
    ///
    /// What varies between reasons is the second paragraph and whether a button is
    /// offered — see `StoreOpenFailureReason`.
    public static func storeAvailability(_ availability: StoreAvailability) -> StoreAvailabilityNotice? {
        switch availability {
        case .open:
            return nil

        case let .couldNotOpen(failure):
            return StoreAvailabilityNotice(
                heading: storeCouldNotOpenHeading,
                body: storeCouldNotOpenBody,
                detail: storeFailureDetail(failure),
                // Present exactly when a second attempt could plausibly work. The state
                // that cannot be helped gets no button and its detail says why, which is
                // the honest version of a control that would have done nothing.
                action: failure.permitsTryingAgain ? .tryAgain : nil
            )

        case .openedAfterTryingAgain:
            return StoreAvailabilityNotice(
                heading: "Your history opened",
                // The caveat is the whole reason this state exists rather than dropping
                // straight into the app — see `StoreAvailability.openedAfterTryingAgain`.
                // "Starts" rather than "you open Maximize": returning to a backgrounded app
                // is not a launch, and the pipeline is assembled at launch.
                body: "Everything already recorded is there. One thing has not come back with "
                    + "it: Maximize sets up its capture of new workouts once, as it starts, and "
                    + "at that moment there was nowhere to put them. Workouts recorded since "
                    + "then are collected the next time Maximize starts, and none of them are "
                    + "lost while they wait.",
                detail: nil,
                action: .goToTheApp
            )
        }
    }

    /// The heading over every store-open failure. Names the app and the athlete's own
    /// history, because "the store" is a developer's word for it.
    private static let storeCouldNotOpenHeading = "Maximize could not open your history"

    /// The paragraph that does not vary with the reason. See `storeAvailability(_:)` for
    /// the three claims it makes and why each is load-bearing.
    private static let storeCouldNotOpenBody =
        "Everything Maximize has recorded — your workouts, your plan, your scores and your "
            + "conversations — is kept in one place on this device, and it could not be opened "
            + "this time. Nothing has been deleted: this is Maximize being unable to read your "
            + "history, not a sign that it is gone. Until it opens, no screen has anything to "
            + "show and nothing new is being kept. Runs recorded in the meantime are not lost — "
            + "Maximize picks them up once it can open the store again."

    /// The second paragraph: what is specific to this failure, and what the athlete can do
    /// between attempts.
    ///
    /// Exhaustive over `StoreOpenFailureReason` with no `default`, so a reason added later
    /// fails to compile here rather than inheriting a neighbour's explanation.
    private static func storeFailureDetail(_ failure: StoreOpenFailure) -> String {
        let reason: String
        switch failure.reason {
        case .deviceHadNotBeenUnlocked:
            reason = "This happens when Maximize is woken in the background before the phone "
                + "has been unlocked since it was last restarted — your history stays encrypted "
                + "until then. Unlock the phone, then try again."
        case .noRoomOnDevice:
            reason = "The device reports that there is no room left on it to write to. Free up "
                + "some space, then try again."
        case .shapeThisBuildCannotOpen:
            reason = "Your history is not in the shape this version of Maximize expects, and it "
                + "could not be converted into it. A second attempt would do exactly the same "
                + "thing, so Maximize is not offering one. Your history is still on the device "
                + "and nothing here has changed it."
        case .unknown:
            reason = "Maximize has nothing more specific to say about why. Trying again costs "
                + "nothing and sometimes works; if it does not, nothing on the device is any "
                + "different for having tried."
        }

        // The acknowledgement goes first, so a person who has just pressed the button reads
        // an answer to what they did before reading the explanation again. Two fixed
        // literals joined — nothing here interpolates a value (see this type's note).
        guard failure.hasAlreadyBeenTriedAgain else { return reason }
        return "Trying again did not open it. " + reason
    }

    /// The title of the store notice's single button.
    ///
    /// Exhaustive with no `default`. Neither label promises an outcome: "Try again" says
    /// what the button does, not that it will work, and the state where it would not work
    /// does not offer it at all.
    public static func actionLabel(for action: StoreNoticeAction) -> String {
        switch action {
        case .tryAgain:
            return "Try again"
        case .goToTheApp:
            return "Continue"
        }
    }

    // MARK: - Absence, which is not failure

    /// Shown when the workout list loaded successfully and holds nothing.
    ///
    /// **Reachable only when the store is open** (MAX-169). Before that ticket this string
    /// and a store that never opened were the same screen: an athlete whose store had
    /// failed read "No workouts yet" and a suggestion to check their Health settings, for
    /// a device where the workouts may well have been there all along. The store's own
    /// failure is now stated at the root, in `storeAvailability(_:)`, and the workouts tab
    /// is not reached while it holds.
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

    /// The footer under Settings' "Anthropic API key" section (MAX-167).
    ///
    /// A `SecureField` with no explanation states a mechanism and never a purpose — a
    /// person who does not already know what an Anthropic API key is learns nothing from
    /// it. This sentence answers the three questions that leaves open: what the key is
    /// for, what it costs, and where it lives. A fixed literal with no data dependency —
    /// nothing here is derived from a fact the app can only learn at runtime, unlike
    /// `storedKeyPresence` or `apiKeyStatus` above — so it lives here rather than as a
    /// view literal anyway, matching every other sentence on this screen (the plan
    /// section's footer in `SettingsView.planSection` is the sibling this one is styled
    /// after) and keeping the whole vocabulary of what this screen says in one place CI
    /// can check.
    ///
    /// **A5's tripwire governs every clause.** CLAUDE.md: "if this app is ever shipped to
    /// anyone else, the key must move behind a server first." This sentence must therefore
    /// read as true and unremarkable in a single-user, never-distributed app *and* stop
    /// being comfortable the moment that stops being true — so it never says the key is
    /// "secure," "safe," or "private": those words describe a promise that would survive
    /// distribution unchanged, which is exactly the drift the tripwire exists to catch.
    /// What it says instead is checkable fact: two call sites (`AnthropicScoringModelClient`,
    /// `AnthropicStreamingChatClient`/`AnthropicPlanProposalClient`), the athlete's own
    /// Anthropic account footing the bill, on-device storage, and no third destination for
    /// the key. It also says the recoverable, reassuring truth explicitly: a workout
    /// captured before a key exists is not lost, only unscored, and is scored once a key
    /// is added (`WorkoutIngestionPipeline.completeIngestion(forWorkout:)`).
    ///
    /// **Says "on this device," never "Keychain."** No user-facing string anywhere else in
    /// this app names the framework a value is stored in — `AnthropicAPIKeyError`'s
    /// Keychain-referencing cases are `description`s written for a developer, not copy a
    /// screen shows (see this file's own "two rules" above) — and this sentence keeps that
    /// pattern rather than starting a second one.
    public static let apiKeyPurpose =
        "Maximize calls Claude to score each workout and to answer questions in chat, "
            + "using a key of your own — usage is billed to your Anthropic account, not "
            + "Maximize's. Workouts are captured and stored without one; they are simply "
            + "not scored until a key is added, and everything already recorded is scored "
            + "once it is. The key stays on this device and is sent only to Anthropic. "
            + "Create one at console.anthropic.com."

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

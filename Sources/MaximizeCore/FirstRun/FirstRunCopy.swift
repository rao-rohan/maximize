import Foundation

/// One rendering of the setup card: a heading, a sentence, an optional second sentence at
/// secondary weight, and at most one action (FIRST-RUN-SPEC §5.3).
///
/// A struct rather than four lookup functions so MAX-164 renders a value instead of
/// asking four questions and hoping the answers belong together — `ChatFailureNotice`'s
/// shape, for the same reason.
public struct FirstRunCardCopy: Hashable, Sendable {

    /// The card's title. Short, and never a claim about Health access.
    public let heading: String

    /// The one sentence under it.
    public let body: String

    /// A second paragraph at secondary weight, or `nil` for the states that do not need
    /// one. Only §8's waiting state has one, and it is the sentence that stops the first
    /// paragraph being read as a claim about permission.
    public let detail: String?

    /// What the card's single button does, or `nil` for a card with no button.
    public let action: FirstRunStep?

    /// The button's title, present exactly when `action` is.
    public var actionLabel: String? {
        action.map(FirstRunCopy.actionLabel(for:))
    }
}

/// The words the first-launch cover shows (FIRST-RUN-SPEC §4.2).
///
/// Three elements and a button. No carousel, no feature tour, no illustration.
public struct FirstRunCoverCopy: Hashable, Sendable {

    /// States the product rather than greeting the athlete. "Welcome to Maximize" tells a
    /// person nothing they did not know from tapping the icon.
    public let title: String

    /// What iOS is about to ask, and what this app reads. The sentence is the Settings
    /// section's own, so one fact has one wording in two places.
    public let health: String

    /// Where health data goes, what leaves the device, and what a reinstall costs.
    public let privacy: String

    /// The button. Deliberately not "Allow" — that is the system sheet's word, and
    /// pre-empting it is a small lie about which button does what — and deliberately not
    /// "Connect", which implies a verifiable connected state that is exactly what R10
    /// forbids claiming.
    public let continueLabel: String

    /// Body text in reading order, for a caller that wants to lay the paragraphs out
    /// without naming them one at a time.
    public var paragraphs: [String] { [health, privacy] }
}

/// Every sentence the first-run surfaces can show (MAX-162, FIRST-RUN-SPEC §4, §5, §8).
///
/// ## Why it is here and not in the two views
///
/// CLAUDE.md's thin-shell rule, and one thing more. First run is the app's least-exercised
/// surface — it runs once per install, for one athlete — so it is the surface a reader is
/// least likely to catch a wrong word on. Nothing draws these strings in CI, but
/// `FailureCopyTests` can execute every one of them and assert what they must never say,
/// and that is only possible because they are values in the core rather than literals in
/// a `Text`.
///
/// ## The rule every string below keeps: R10
///
/// **No sentence here states, implies, or leaves room to render that Health access has
/// been granted, refused, or is working.** iOS does not tell an app whether *read* access
/// was granted, so any such sentence would be a claim the app has no way to check — and
/// this is the one screen in the product where such a claim would be most tempting,
/// because the athlete has just answered a permission sheet and expects a result.
///
/// The defence is structural before it is editorial: `FirstRunStep` models no completion
/// and the Health step has no completed state, so there is no value from which a "Health
/// ✓" could be rendered even by a view that wanted one (FIRST-RUN-SPEC §9.1). The
/// editorial half is
/// `FailureCopyTests.testNoHealthCopyClaimsAccessWasGrantedOrRefused`, which enumerates
/// every string this type can produce — extended rather than duplicated, because two
/// tests asserting one rule drift and the one that drifts is the one nobody remembers.
///
/// ## One departure from the spec's wording, stated rather than hidden
///
/// FIRST-RUN-SPEC §5.2 writes state 2 as *"Runs are being captured, but until a plan
/// exists…"* and state 3 as *"Your runs are captured and measured."* Both assert that
/// capture is happening, which is precisely the claim R10 says the app cannot make: if
/// read access was refused, nothing is being captured and the app cannot tell. The
/// sentences below say what is true unconditionally — that a workout is stored *as it
/// arrives* — and the phrase "being captured" is on the banned list in the test, so this
/// cannot quietly come back. The spec's §8 wording, which it defends explicitly ("Maximize
/// is registered for new workouts" is a claim about the observer query, true whatever iOS
/// decided), is kept verbatim.
///
/// ## Privacy
///
/// **No string below interpolates anything.** Every value is a fixed literal, so there is
/// no argument through which a workout, a date, an identifier or anything about the key
/// could reach a rendered sentence — the property `FailureCopy` documents and for the
/// same reason. The one numeral is the ingester's ninety-day backfill window, which is a
/// constant of the app and not a fact about the athlete; a test holds it to
/// `AnchoredIngestionPolicy.standard`.
public enum FirstRunCopy {

    // MARK: - The first-launch cover

    /// FIRST-RUN-SPEC §4.2. MAX-163 renders this and nothing else.
    public static let cover = FirstRunCoverCopy(
        title: "Maximize scores your runs against your plan.",
        // The middle sentence is `HealthAccessSettingsSection`'s own, with its subject
        // turned into a pronoun because the sentence before it already names the app.
        // One fact, one wording, two places.
        health: "Next, iOS will ask which health data Maximize may read. It reads completed "
            + "workouts, heart rate, distance, energy, steps and route. It never writes to Health.",
        // A8 defers CloudKit, so history does not survive a reinstall and there is nothing
        // the athlete can do about it. A warning nobody can act on is noise everywhere
        // except the one screen where the app is asking to be trusted with health data.
        // The second sentence is the other half of that honesty: an app that said
        // "everything stays on your device" would be false the first time a conversation
        // was opened, and the athlete would have no way to discover it.
        privacy: "Maximize keeps your workouts on this device. The only thing that ever leaves "
            + "it is a summary of a run, or of a training block, sent to Claude when you ask a "
            + "question. Nothing is backed up, so deleting Maximize deletes its history.",
        continueLabel: "Continue"
    )

    // MARK: - The setup card

    /// What the card shows for a given state. Exhaustive with no `default`, so a state
    /// added later fails to compile here rather than inheriting a neighbour's words.
    public static func card(_ state: FirstRunCardState) -> FirstRunCardCopy {
        switch state {
        case .healthAccessNotRequested:
            return FirstRunCardCopy(
                heading: "Health access has not been requested",
                body: "Maximize cannot see any workouts until iOS has put the question to you.",
                detail: nil,
                action: .requestHealthAccess
            )

        case .healthRequestDidNotComplete:
            return FirstRunCardCopy(
                heading: "The Health request did not finish",
                body: "iOS stopped before the question was answered, so it may never have been "
                    + "put. Asking again is safe.",
                detail: nil,
                action: .requestHealthAccess
            )

        case .healthDataUnavailable:
            return FirstRunCardCopy(
                heading: "This device does not provide Health data",
                body: "Maximize reads workouts from Apple Health, which this device does not "
                    + "have, so no workout can reach it. Nothing else set up here would change that.",
                detail: nil,
                action: nil
            )

        case .noPlanAuthored:
            return FirstRunCardCopy(
                heading: "No plan yet",
                // "Stored as they arrive" rather than the spec's "runs are being
                // captured": see the type's note on the one departure.
                body: "Workouts are stored as they arrive, but until a plan exists there is "
                    + "nothing to measure them against — no metrics, no score, no chat about a run.",
                detail: nil,
                action: .authorAPlan
            )

        case .noAPIKeyStored:
            return FirstRunCardCopy(
                heading: "No Anthropic API key",
                // The last sentence is what makes this step honest rather than nagging,
                // and it is true: `completeIngestion(forWorkout:)` scores a workout the
                // next time it is opened.
                body: "Workouts are stored and measured against your plan as they arrive. Scoring "
                    + "and chat both call Claude, which needs a key of your own. Runs recorded "
                    + "before you add one are scored when you next open them, so nothing is lost "
                    + "by waiting.",
                detail: nil,
                action: .addAnAPIKey
            )

        case .awaitingFirstWorkout:
            return FirstRunCardCopy(
                heading: "Set up. Nothing recorded yet.",
                // Every clause here is checkable: registration happens at launch
                // (`startObservingWorkouts()`), the pickup on foreground
                // (`ingestPendingWorkouts()`) and through background delivery, and the
                // ninety days are `AnchoredIngestionPolicy.standard.firstRunBackfill`.
                // "Registered for new workouts" is a claim about the observer query,
                // which is true whatever iOS decided about read access — and the second
                // paragraph exists so it cannot be read as more than that.
                body: "Maximize is registered for new workouts and will pick up the next one your "
                    + "Watch syncs, usually within a few minutes. Workouts from the last 90 days "
                    + "are fetched once, the first time access is granted.",
                detail: waitingRecoveryDetail,
                action: nil
            )
        }
    }

    /// The second paragraph of §8's waiting state.
    ///
    /// **The collapse with `FailureCopy.noWorkoutsRecorded` was tried first**, as
    /// FIRST-RUN-SPEC §8 asks, and rejected on how it reads rather than on principle: that
    /// string opens with "No workouts yet.", which under a heading that already says
    /// "Nothing recorded yet." is the same sentence twice on one card. What the two share
    /// is the fact and the recovery path, and they are worded for different moments — one
    /// for a person opening an empty app, one for a person who has just finished setting
    /// up and is waiting. `FirstRunChecklistTests` asserts they still name the same place
    /// in Settings, which is the drift that would actually matter.
    private static let waitingRecoveryDetail =
        "If a run you have already recorded never appears, iOS may not have granted read "
            + "access — it never tells the app either way. Check Maximize under Settings › "
            + "Health › Data Access & Devices."

    /// The title of the card's button.
    ///
    /// Exhaustive with no `default`. Each names where it goes rather than what it
    /// achieves, because none of the three can promise its own outcome: the sheet may be
    /// refused, the plan is the athlete's to write, and the key is theirs to obtain.
    public static func actionLabel(for step: FirstRunStep) -> String {
        switch step {
        case .requestHealthAccess:
            return "Request Health access"
        case .authorAPlan:
            return "Author a plan"
        case .addAnAPIKey:
            return "Add a key in Settings"
        }
    }
}

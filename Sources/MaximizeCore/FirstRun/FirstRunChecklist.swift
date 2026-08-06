import Foundation

/// The four facts a fresh install can honestly establish about itself (MAX-162,
/// FIRST-RUN-SPEC §3).
///
/// Four, and no more: everything the first-run surfaces say is derived from these, so
/// there is exactly one description of "what is set up" and both surfaces read it.
///
/// ## Why two of these are enums rather than booleans
///
/// `healthAccess` and `apiKeyPresence` are the two facts the app can fail to establish,
/// and MAX-154 is the ticket that found what happens when a failed check is stored as
/// `false`: a Keychain read that errored became a screen stating flatly that no key was
/// stored. `HealthAccessState` and `StoredAPIKeyPresence` already carry the honest third
/// answer, so this type reuses them rather than putting a boolean beside them
/// (FIRST-RUN-SPEC §9.1).
///
/// The other two are genuine booleans. "A plan version is stored" and "a workout is
/// stored" are queries against the local store whose failure mode is a thrown error the
/// caller sees, not a false negative it cannot distinguish.
///
/// ## `healthAccess` must be the device's answer, not the launch's
///
/// **Read this before wiring the app up.** `HealthAccessState.notRequestedYet` is
/// documented as "not presented *on this launch*", because the Settings section that
/// introduced it holds the state in `@State` and starts every launch not having asked. A
/// checklist built from that value would put `.healthAccessNotRequested` on the card at
/// every launch of a perfectly working install, which is exactly the nagging §5.4
/// forbids.
///
/// For first run the fact wanted is the device-lifetime one — *has the sheet ever been
/// presented on this device* — which is what MAX-163's `FirstRunPresentationRecording`
/// exists to record. The app is expected to compose it: a recorded presentation resolves
/// to `.requestAnswered`, which is precisely what that case means (the sheet was
/// presented and answered; what it was answered *with* is not knowable).
///
/// ## Privacy
///
/// Nothing here is a workout, a date, or key material. `apiKeyPresence` is the whole of
/// what this module ever learns about the key — not its length, not its prefix, not its
/// account (CLAUDE.md, and `StoredAPIKeyPresence`'s own note). None of these values is
/// logged; they exist in memory on the way to a card.
public struct FirstRunFacts: Hashable, Sendable {

    /// What the app can say about the Health permission sheet. See the type note above:
    /// this is the device-lifetime answer, not the current launch's.
    public let healthAccess: HealthAccessState

    /// Whether at least one plan version is stored (`PlanRepository`).
    public let hasAuthoredPlan: Bool

    /// Whether an Anthropic API key is stored, or whether that could not be checked.
    public let apiKeyPresence: StoredAPIKeyPresence

    /// Whether at least one workout is stored. Separates §8's "set up, nothing recorded
    /// yet" window from "set up, and the app is running normally".
    public let hasCapturedWorkout: Bool

    public init(
        healthAccess: HealthAccessState,
        hasAuthoredPlan: Bool,
        apiKeyPresence: StoredAPIKeyPresence,
        hasCapturedWorkout: Bool
    ) {
        self.healthAccess = healthAccess
        self.hasAuthoredPlan = hasAuthoredPlan
        self.apiKeyPresence = apiKeyPresence
        self.hasCapturedWorkout = hasCapturedWorkout
    }

    /// Day one, before anything has happened: the sheet has never been presented, no plan
    /// exists, the Keychain holds nothing, and no workout has been stored.
    public static let freshInstall = FirstRunFacts(
        healthAccess: .notRequestedYet,
        hasAuthoredPlan: false,
        apiKeyPresence: .notStored,
        hasCapturedWorkout: false
    )
}

/// What a fresh install still needs, in the order it should be asked for, and the single
/// next thing to offer (MAX-162, FIRST-RUN-SPEC §3, §5).
///
/// ## What each caller reads
///
/// - **MAX-164, the setup card:** `card`. It is the whole seam — one optional value,
///   switched over, with `FirstRunCopy.card(_:)` supplying every word and the action.
///   `nil` means no card. The card must not assemble a state out of `facts` itself.
/// - **MAX-163, the launch cover:** nothing here. The cover is gated on whether it has
///   been shown before (`FirstRunPresentationRecording`, that ticket's own protocol), not
///   on what is set up, and its words are `FirstRunCopy.cover`.
/// - **Either, later:** `remainingSteps` and `nextStep`, if the owner decides the card
///   should list all three steps rather than only the next one (FIRST-RUN-SPEC §15,
///   question 2). The type carries both today so that is a view change rather than a
///   redesign.
///
/// ## The rule that is not in here, and whose it is
///
/// §5.4: the card **does not come back** once a condition it named later becomes false —
/// a key cleared in Settings six weeks later is chat's problem to mention
/// (`ChatFailureNotice`), not first run's to re-open. This type is a pure function of
/// facts and cannot express "already shown once", so MAX-164 owns that: resolve the
/// checklist when the tab appears and after returning from a screen it sent the athlete
/// to, and stop consulting it once it has answered `nil`.
///
/// ## No step is ever marked done
///
/// See `FirstRunStep`. A step that has been taken leaves `remainingSteps`; it does not
/// acquire a tick. There is no value in this module a view could render as "Health
/// connected", which is what makes tracker R10's rule structural rather than a promise.
public struct FirstRunChecklist: Hashable, Sendable {

    /// The facts this checklist was resolved from, kept so a caller can answer a follow-up
    /// question without re-deriving anything.
    public let facts: FirstRunFacts

    /// Everything still outstanding, in the order it should be asked for — which is
    /// `FirstRunStep.allCases`' order, which is `FirstRunStepRecovery` ascending.
    ///
    /// A step leaves this list when it stops being outstanding. It never appears in it
    /// annotated as complete.
    ///
    /// **Empty does not mean "set up".** It is also empty on a device that provides no
    /// Health data, where no step remains that could change anything. `card` is the
    /// question to ask about what the athlete should see.
    public let remainingSteps: [FirstRunStep]

    /// What the setup card shows, or `nil` for no card.
    public let card: FirstRunCardState?

    /// The single action to offer, or `nil` when there is nothing useful to press.
    ///
    /// Always the card's own action (`card?.step`) and always the first outstanding step
    /// when there is one — the two agree by construction and `FirstRunChecklistTests`
    /// asserts it over every combination of facts.
    public var nextStep: FirstRunStep? { remainingSteps.first }

    public init(facts: FirstRunFacts) {
        self.facts = facts
        self.remainingSteps = Self.resolveRemainingSteps(for: facts)
        self.card = Self.resolveCard(for: facts)
    }

    // MARK: - Resolution

    /// Whether the Health sheet is still worth putting to the athlete.
    ///
    /// True only where asking again can achieve something. `.requestAnswered` is not a
    /// success — it is the end of what iOS will tell this app, and there is nothing
    /// further to ask. `.healthDataUnavailable` cannot be asked at all.
    private static func isHealthAccessOutstanding(_ state: HealthAccessState) -> Bool {
        switch state {
        case .notRequestedYet, .requestFailed:
            return true
        case .requestAnswered, .healthDataUnavailable:
            return false
        }
    }

    private static func resolveRemainingSteps(for facts: FirstRunFacts) -> [FirstRunStep] {
        // A device with no Health store can never receive a workout, so a plan and a key
        // would be steps toward nothing. The card says so instead, and offers no action.
        guard facts.healthAccess != .healthDataUnavailable else { return [] }

        return FirstRunStep.allCases.filter { step in
            switch step {
            case .requestHealthAccess:
                return isHealthAccessOutstanding(facts.healthAccess)
            case .authorAPlan:
                return !facts.hasAuthoredPlan
            case .addAnAPIKey:
                // `.unknown` is deliberately absent. A Keychain read that failed is not
                // evidence that no key is stored, and MAX-154's finding was exactly this
                // conflation reaching a screen as a confident absence. Settings already
                // says the honest thing where the athlete can act on it
                // (`FailureCopy.storedKeyPresence(.unknown)`); a first-run card that
                // asked for a key that may well be there would be a second voice on one
                // fact, and a nag built on a guess.
                return facts.apiKeyPresence == .notStored
            }
        }
    }

    /// Resolved from the facts directly rather than from `remainingSteps`, because two of
    /// the Health cases produce a card with no step at all. The two derivations agree on
    /// every combination of facts and a test holds them to it.
    private static func resolveCard(for facts: FirstRunFacts) -> FirstRunCardState? {
        switch facts.healthAccess {
        case .notRequestedYet:
            return .healthAccessNotRequested
        case .requestFailed:
            return .healthRequestDidNotComplete
        case .healthDataUnavailable:
            return .healthDataUnavailable
        case .requestAnswered:
            break
        }

        guard facts.hasAuthoredPlan else { return .noPlanAuthored }
        guard facts.apiKeyPresence != .notStored else { return .noAPIKeyStored }

        // Everything asked for is behind them. The card stays for the window before the
        // first workout arrives (§8), and then it is gone and does not return.
        return facts.hasCapturedWorkout ? nil : .awaitingFirstWorkout
    }
}

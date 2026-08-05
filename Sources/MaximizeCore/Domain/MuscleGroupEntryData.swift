import Foundation

/// What the workout detail screen says about a session's muscle groups, and what the
/// picker that sets them says (A22).
///
/// Copy lives here rather than in the view for the reason CLAUDE.md gives for every
/// other decision in this package: a string a person reads is a product decision, and a
/// product decision in a SwiftUI view is verified only when a human opens Xcode.
/// `ChatConversationCopy` is the established shape for this — no branching on state
/// beyond the words themselves, and a test that pins the wording so two surfaces cannot
/// drift into two voices.
///
/// **The prompt is the feature's onboarding.** A lift that says *"tell me what you
/// trained"* is how the athlete discovers the field exists, so the awaiting-entry copy
/// is written as a question the app is asking, not as a blank or an apology (A22, and
/// CLAUDE.md's "absence is a designed state").
public enum MuscleGroupEntryCopy {

    /// The section's heading on the workout detail screen.
    public static let sectionTitle = "Muscle groups"

    /// The prompt, on both surfaces that ask. Deliberately the same sentence in the
    /// verdict header and in the section below it: one question, asked once, in one
    /// voice — two wordings would read as two different asks on one screen.
    public static let awaitingEntryHeadline = "Tell me what you trained"

    /// The section's second line while nothing has been entered. States *why* the app
    /// has to ask, because the honest answer is not obvious: the athlete's watch
    /// recorded the session in full and this is the one thing it did not record.
    public static let awaitingEntryDetail =
        "HealthKit records that you lifted, not what you worked. Set the groups and this session is on the record."

    /// The verdict header's second line for `WorkoutVerdict.Scoring.awaitingMuscleGroups`.
    ///
    /// Present tense and no spinner — the wait is on the athlete, and nothing is in
    /// progress. It states the dependency without promising a number: a lift is not
    /// scored until the groups are set, which is true today and stays true when the
    /// lift rubric lands.
    public static let awaitingEntryVerdictDetail =
        "This lift isn't scored until you set the muscle groups it worked."

    /// The section's second line once groups have been entered. Says who said so,
    /// because on a screen where every other number came from the watch, this one did
    /// not.
    public static let enteredDetail = "Set by you — HealthKit doesn't record what a lift worked."

    /// Opens the picker when nothing has been entered.
    public static let setAction = "Set muscle groups"

    /// Opens the picker when something has.
    public static let changeAction = "Change"

    /// The picker's own title. The question form again, matching the prompt that led
    /// the athlete here.
    public static let editorTitle = "What did you train?"

    public static let editorSave = "Save"
    public static let editorCancel = "Cancel"

    /// Under the picker's list. Says the entry is not final, which is what makes it
    /// safe to answer without deliberating.
    public static let editorFooter =
        "Pick every group this session worked. You can change it later; earlier answers are kept."

    /// The picker's summary before anything is selected.
    ///
    /// This is the **editor's** empty state, not a workout's: a stored entry can never
    /// hold zero groups (see `MuscleGroupEntry`), so this sentence never describes a
    /// session — only a half-made selection.
    public static let noneSelected = "No groups selected"

    /// The groups, in `MuscleGroup.allCases` order, as a sentence: "Chest", "Chest and
    /// back", "Chest, back and shoulders".
    ///
    /// Ordered rather than set-ordered so the same session does not read "shoulders,
    /// chest" one launch and "chest, shoulders" the next — the reason
    /// `Set<MuscleGroup>.ordered` exists. Only the first name is capitalised: this is a
    /// sentence about a session, not a list of headings.
    public static func describe(_ groups: Set<MuscleGroup>) -> String {
        let names = groups.ordered.map(\.displayName)
        guard let first = names.first else { return noneSelected }
        let rest: [String] = names.dropFirst().map { $0.lowercased() }
        guard let last = rest.last else { return first }
        guard rest.count > 1 else { return first + " and " + last }
        let leading = ([first] + rest.dropLast()).joined(separator: ", ")
        return leading + " and " + last
    }
}

/// The muscle-group section's state for one workout: whether it appears at all, and
/// what it says if it does.
///
/// The branch is here rather than in the view because "does this screen ask the
/// question?" is a business rule — it is A22's *narrowness*, in code. The amendment
/// spends PRD §3's manual-entry non-goal for one field on one kind of workout, and
/// `resolve(activityType:entry:)` is the single place that decides which workouts those
/// are. A view asking `activityType == .traditionalStrengthTraining` for itself would
/// be that rule written a second time, in the layer CI cannot run.
public struct MuscleGroupEntryData: Hashable, Sendable {

    public enum State: Hashable, Sendable {
        /// Not a strength session. The section does not appear, and no run is ever
        /// asked what muscles it worked.
        case notALift

        /// A lift the athlete has not answered for. **Not "no groups"** — see
        /// `MuscleGroupEntry` for why the two are different states and why only this
        /// one prompts.
        case awaitingEntry

        /// The answer in force. Never empty, by `MuscleGroupEntry`'s construction.
        case entered(Set<MuscleGroup>)
    }

    public let state: State

    /// - Parameters:
    ///   - activityType: the captured type, straight from `Workout`. Read through
    ///     `Discipline` rather than compared to a case, so a strength type mapped
    ///     later (HealthKit's `functionalStrengthTraining`, say) is asked the question
    ///     without a second edit here.
    ///   - entry: `MuscleGroupLog.current` — the latest thing the athlete said, or nil
    ///     if they have not said anything.
    public static func resolve(
        activityType: ActivityType,
        entry: MuscleGroupEntry?
    ) -> MuscleGroupEntryData {
        guard activityType.discipline == .lift else {
            return MuscleGroupEntryData(state: .notALift)
        }
        guard let entry else {
            return MuscleGroupEntryData(state: .awaitingEntry)
        }
        return MuscleGroupEntryData(state: .entered(entry.groups))
    }

    /// Whether the detail screen shows the section at all.
    public var isShown: Bool { state != .notALift }

    /// The groups in force, or nil while the app is still waiting on the athlete.
    public var groups: Set<MuscleGroup>? {
        guard case let .entered(groups) = state else { return nil }
        return groups
    }

    /// The section's first line: the prompt while waiting, the answer once given.
    public var headline: String {
        switch state {
        case .notALift, .awaitingEntry: return MuscleGroupEntryCopy.awaitingEntryHeadline
        case let .entered(groups): return MuscleGroupEntryCopy.describe(groups)
        }
    }

    /// The section's second line.
    public var detail: String {
        switch state {
        case .notALift, .awaitingEntry: return MuscleGroupEntryCopy.awaitingEntryDetail
        case .entered: return MuscleGroupEntryCopy.enteredDetail
        }
    }

    /// The button that opens the picker.
    public var actionTitle: String {
        switch state {
        case .notALift, .awaitingEntry: return MuscleGroupEntryCopy.setAction
        case .entered: return MuscleGroupEntryCopy.changeAction
        }
    }

    /// One sentence for VoiceOver, so the prompt and its reason are read as a single
    /// element rather than as two unrelated labels — the treatment
    /// `VerdictHeaderView.noVerdictSection` already gives its own two lines.
    public var accessibilityLabel: String {
        switch state {
        case .notALift, .awaitingEntry:
            return "\(MuscleGroupEntryCopy.sectionTitle). \(headline). \(detail)"
        case let .entered(groups):
            return "\(MuscleGroupEntryCopy.sectionTitle). \(MuscleGroupEntryCopy.describe(groups))."
        }
    }

    /// The picker's starting state for this section.
    public var selection: MuscleGroupSelection { MuscleGroupSelection(recorded: groups) }
}

/// The picker's working state: what is ticked right now, and whether it is worth
/// recording.
///
/// A value type in the core rather than a `Set` in a `@State`, because two rules decide
/// whether the Save button does anything and both are rules rather than rendering:
///
/// - **An empty selection cannot be saved.** "I trained nothing" is not a thing this
///   record can say (`MuscleGroupEntry`), so the picker must not be able to produce it.
/// - **An unchanged selection cannot be saved either.** Entries are additive and never
///   overwritten, so a Save that recorded the same set again would grow the log by a
///   record that says nothing — the log is history, and history of "no change" is
///   noise.
public struct MuscleGroupSelection: Hashable, Sendable {

    /// What the athlete has already recorded, if anything. Kept so `canSave` can tell
    /// an edit from a re-statement.
    public let recorded: Set<MuscleGroup>?

    public private(set) var groups: Set<MuscleGroup>

    /// Starts from what is already on record — a change begins from the current answer,
    /// not from a blank slate.
    public init(recorded: Set<MuscleGroup>?) {
        self.recorded = recorded
        self.groups = recorded ?? []
    }

    public func contains(_ group: MuscleGroup) -> Bool { groups.contains(group) }

    public mutating func toggle(_ group: MuscleGroup) {
        if groups.contains(group) {
            groups.remove(group)
        } else {
            groups.insert(group)
        }
    }

    /// Whether this selection is worth writing. See the type note for both rules.
    public var canSave: Bool { !groups.isEmpty && groups != recorded }

    /// What the picker shows above its list.
    public var summary: String { MuscleGroupEntryCopy.describe(groups) }

    /// The record this selection would write.
    ///
    /// Goes through `MuscleGroupEntry`'s validating initializer rather than around it,
    /// so an empty selection cannot reach storage even if a caller ignores `canSave`.
    public func entry(id: UUID, workoutID: UUID, recordedAt: Date) throws -> MuscleGroupEntry {
        try MuscleGroupEntry(id: id, workoutID: workoutID, groups: groups, recordedAt: recordedAt)
    }
}

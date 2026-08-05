import Foundation

/// Which screen the persistent Ask button is currently sitting on top of (§7.5).
///
/// ## Why this is a value in the core rather than a `Bool` in a view
///
/// The button is subject-aware, and that is the whole point of it (§2.1): the label is
/// the only thing on screen telling the athlete which pile of their own data a tap is
/// about to send somewhere. "Which pile" is therefore a *decision*, not styling, and
/// CLAUDE.md is explicit about where a decision lives — a view working out "am I a
/// workout screen?" by inspecting itself is the shape to avoid.
///
/// What the app layer supplies is one fact: a workout detail screen is showing, or none
/// is. Everything downstream of that fact — which subject, which label, what VoiceOver
/// says — is settled here, under test, on every commit.
///
/// ## Why `release(_:)` takes an identifier
///
/// The app layer reports focus from `onAppear` and clears it from `onDisappear`, and
/// **those two do not fire in a guaranteed order across a screen change**.
/// `DayWorkoutsView` pages between several `WorkoutDetailView`s inside a `TabView`
/// (MAX-108), so a swipe from run A to run B can deliver either
/// `appear(B) → disappear(A)` or `disappear(A) → appear(B)`.
///
/// Unconditional clearing loses on the first ordering: B's focus is set and then wiped
/// by A's late disappearance, leaving the button reading "Ask" on a screen showing a
/// run. Matching the identifier makes both orderings converge on B, which is what the
/// athlete is looking at. This is exactly the kind of ordering bug that is invisible in
/// review and expensive on a device, which is why it is a tested function rather than
/// two lines of view code.
public struct ChatEntryPointFocus: Hashable, Sendable {

    /// The run whose detail screen is showing, or nil when none is.
    public private(set) var workoutID: UUID?

    /// Nothing focused — every tab root, before anything is pushed.
    public init() {
        self.workoutID = nil
    }

    /// - Parameter workoutID: the run whose detail screen has just appeared.
    public init(workoutID: UUID?) {
        self.workoutID = workoutID
    }

    /// A workout detail screen appeared. The most recent one always wins: a push, or a
    /// page of `DayWorkoutsView`, is the screen the athlete is now looking at.
    public mutating func focus(_ workoutID: UUID) {
        self.workoutID = workoutID
    }

    /// A workout detail screen disappeared. A no-op unless it is the screen currently
    /// held — see this type's note on ordering.
    public mutating func release(_ workoutID: UUID) {
        guard self.workoutID == workoutID else { return }
        self.workoutID = nil
    }
}

/// What the persistent Ask button says and what a tap opens (§2.1, §7).
///
/// One entry point, everywhere, in the same place — so the only thing that varies
/// between screens is this value, and every field of it is decided here.
///
/// ## Why the label is not decoration
///
/// §2.1, verbatim: the label "is the only thing on screen telling the athlete which pile
/// of their own data is about to be sent somewhere, and that is worth the pixels." A
/// button reading "Ask" on a workout screen would open that run's thread while saying
/// nothing about it; a button reading "Ask about this run" on the dashboard would be a
/// lie about what leaves the device. Neither is a styling mistake, which is why neither
/// is a view's to make.
///
/// ## Why the glyph does not vary
///
/// `ChatSubjectKind.glyphSystemImageName` distinguishes a workout row from a training
/// row *in a list of threads*, where the rows sit next to each other and the glyph is
/// what tells them apart. This is the opposite situation: one control, in one place, on
/// every screen. A control that changed its icon as you navigated would read as a
/// different control — the thing "one entry point, everywhere, in the same place" exists
/// to prevent — so the glyph is fixed and the subject is carried by the words.
public struct ChatEntryPoint: Hashable, Sendable {

    /// What a tap opens. `ChatSheet` hands this straight to `ChatModel`, which resolves
    /// the most recently active thread for it (§2.2) — this type does not decide which
    /// *thread*, only which subject.
    public let subject: ChatSubject

    /// The button's visible label — "Ask" or "Ask about this run" (§2.1).
    public let label: String

    /// The same label where the full one will not fit — a large Dynamic Type size in a
    /// bar the system sizes, or the tab bar's minimised state.
    ///
    /// It drops the verb rather than the scope, and that ranking is the decision: with
    /// the chat glyph beside it, "This run" still says which pile of data a tap sends,
    /// whereas a truncated "Ask about th…" says neither one thing nor the other. The
    /// training label is already two syllables and does not need a shorter form, so it
    /// is its own compact form rather than a second string that could drift from it.
    public let compactLabel: String

    /// What VoiceOver reads. Never abbreviated, and never merely "Ask": a label whose
    /// visible form leans on the screen behind it for context gives a VoiceOver user
    /// nothing, since that context is exactly what they cannot glance at.
    public let accessibilityLabel: String

    /// The scope, spoken. This is where a training entry point names its window — the
    /// visible label deliberately does not (§2.1 asks for "Ask"), so the hint is the
    /// only place a VoiceOver user hears which days a tap is about.
    public let accessibilityHint: String

    /// The button's icon, fixed across subjects — see this type's note on the glyph.
    ///
    /// A plain string, matching `RootTab.symbolName`'s own rule: "no SF Symbols import,
    /// no UIKit. The core says *which* symbol; the app layer is what draws it."
    public static let glyphSystemImageName = "bubble.left.and.bubble.right"

    /// Resolves the button for the screen currently showing.
    ///
    /// - Parameters:
    ///   - focus: what the app layer has reported about the screen on top. A workout
    ///     detail screen wins over everything, on every tab — reaching a run from the
    ///     dashboard's calendar (MAX-108) is still a run.
    ///   - currentInterval: the dashboard's live selection, which §3.4 makes the app's
    ///     single notion of "what period are we talking about". Frozen into a
    ///     `TrainingScope` here, at the moment the button is drawn, so the thread a tap
    ///     opens is about the window the athlete can currently see.
    /// - Returns: nil only when there is no workout focused *and* no interval could be
    ///   resolved — i.e. `TrendIntervalSelectionModel.State.failed`, whose only cause is
    ///   a system clock outside `CalendarDay`'s 1...9999 AD domain. §7.3 says the button
    ///   does not hide, and it does not: there is simply no subject to open a
    ///   conversation about in a state no device can reach.
    public static func resolve(
        focus: ChatEntryPointFocus,
        currentInterval: TrendInterval?
    ) -> ChatEntryPoint? {
        if let workoutID = focus.workoutID {
            return ChatEntryPoint(
                subject: .workout(workoutID),
                label: "Ask about this run",
                compactLabel: "This run",
                accessibilityLabel: "Ask about this run",
                accessibilityHint: "Opens this run's conversation."
            )
        }

        guard let currentInterval, let scope = try? TrainingScope(resolving: currentInterval) else {
            return nil
        }
        return ChatEntryPoint(
            subject: .training(scope),
            label: "Ask",
            compactLabel: "Ask",
            accessibilityLabel: "Ask about your training",
            accessibilityHint: "Opens a conversation about \(scope.label)."
        )
    }
}

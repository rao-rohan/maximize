import Foundation

/// Everything the proposal card says (CHAT-FIRST-SPEC.md §4.6, MAX-101).
///
/// ## Why the card renders a diff, and why the diff is here
///
/// §4.6 states the argument better than a summary can: *"A model asked to drop Thursday
/// to 6 km may also, helpfully, move the cap to 148 — and in a full re-statement of the
/// plan that edit is invisible among fourteen unchanged fields. A diff makes it one
/// highlighted row."* The diff is what turns **accept** from a leap of faith into a
/// decision, so what counts as a change — and what each row says about it — is a
/// decision CI has to be able to check. It lives here, under test, and the App layer
/// only draws it.
///
/// For a first plan there is nothing to compare against, so every row is `.stated` and
/// the card simply says what is prescribed.
///
/// ## Built from the session, not from the proposal alone
///
/// `build(applying:to:distanceUnit:)` takes the same `PlanAuthoringSession` the handoff
/// will use, and the "after" side is literally `session.draft.applying(proposal)` — the
/// value `PlanAuthoringView` will be prefilled with. The card therefore cannot describe
/// a plan different from the one the athlete is about to see in the form, which is the
/// only version of this feature worth shipping.
///
/// ## Nothing here reaches storage
///
/// A13: applying is fine, storing is D1's door and it opens by hand. This type holds
/// values and strings. It has no repository, returns no `Plan`, and the proposal it
/// carries is carried so the accept action can hand on *exactly what was reviewed*
/// rather than re-asking the model.
public struct PlanProposalReview: Hashable, Sendable {

    /// What the athlete's plan situation is, which is what decides whether there is a
    /// diff to render at all. Mirrors `PlanAuthoringSession.Mode` rather than
    /// reinterpreting it.
    public enum Standing: Hashable, Sendable {
        case firstPlan
        case revision(supersedes: PlanVersion, inEffectSince: CalendarDay)
    }

    /// How one row of the card relates to the plan in force.
    ///
    /// `.stated` is deliberately distinct from `.unchanged`: on a first plan there is no
    /// previous value, and rendering "unchanged" against nothing would tell the athlete
    /// something false. **No case is distinguishable by colour alone** — each one that
    /// needs attention carries a word (`marker`), because two states that differ only in
    /// hue are indistinguishable to a meaningful fraction of people (CLAUDE.md, the UI
    /// standard).
    public enum Change: Hashable, Sendable {
        /// No plan is in force. The row states a value; there is nothing to compare it
        /// against.
        case stated
        /// A revision, and this field is what it already was.
        case unchanged
        /// A revision, and this field differs from the plan in force.
        case changed(from: String)
        /// A revision, and the plan in force had nothing here at all — a long-run arc
        /// week past the end of the current arc, most often.
        case added

        public var isChange: Bool {
            switch self {
            case .changed, .added: return true
            case .stated, .unchanged: return false
            }
        }

        /// The word that carries this state when colour cannot.
        public var marker: String? {
            switch self {
            case .stated, .unchanged: return nil
            case .changed: return "Changed"
            case .added: return "New"
            }
        }
    }

    /// One field of the plan, as the card states it.
    public struct Row: Hashable, Sendable, Identifiable {
        /// Stable across rebuilds of the same card — a field key, not a UUID, so a
        /// `ForEach` does not re-identify every row when a value changes.
        public let id: String
        public let label: String
        /// What this proposal prescribes. Never empty: a field the proposal leaves out
        /// gets a designed absence string rather than a blank.
        public let value: String
        public let change: Change

        public var isChange: Bool { change.isChange }

        /// One sentence carrying the whole row, for VoiceOver — a label, a value, and
        /// the old value when there is one, rather than three unrelated fragments a
        /// screen reader would announce out of order.
        public var spokenDescription: String {
            switch change {
            case .stated, .unchanged:
                return "\(label): \(value)"
            case let .changed(previous):
                return "\(label): changed from \(previous) to \(value)"
            case .added:
                return "\(label): new, \(value)"
            }
        }
    }

    /// A group of rows with a heading. Ordered as the card reads, top to bottom.
    public struct Section: Hashable, Sendable, Identifiable {
        public let id: String
        public let title: String
        public let rows: [Row]

        public var changedRows: [Row] { rows.filter(\.isChange) }
        public var hasChanges: Bool { rows.contains(where: \.isChange) }
    }

    public let standing: Standing

    /// The proposal this card describes, carried so **accept** hands on exactly what was
    /// reviewed. Holding it is not a step toward storage — see the type's note.
    public let proposal: PlanProposal

    public let sections: [Section]

    /// The sentence about lifts, always present.
    ///
    /// **Never optional, and never omitted when there is "nothing to say".** A proposal
    /// cannot prescribe a lift — `PlanProposal`'s vocabulary comes from
    /// `ScheduledSessionKind.prescribable`, which excludes `.lift` until MAX-141 — so an
    /// athlete who wrote "and lift on Tuesdays" into the conversation would otherwise be
    /// told yes by omission: they would see a card full of the changes they asked for and
    /// nothing at all indicating that one of them was not made. Saying so on every card
    /// costs one line and is the only honest option.
    public let liftNote: String

    public var isRevision: Bool {
        if case .revision = standing { return true }
        return false
    }

    public var changedRowCount: Int {
        sections.reduce(0) { $0 + $1.changedRows.count }
    }

    public var rowCount: Int {
        sections.reduce(0) { $0 + $1.rows.count }
    }

    /// Every changed row, in card order, so a caller wanting only the diff does not have
    /// to flatten the sections itself.
    public var changedRows: [Row] {
        sections.flatMap(\.changedRows)
    }

    /// The card's title.
    public var headline: String {
        switch standing {
        case .firstPlan:
            return "Proposed plan"
        case let .revision(supersedes, _):
            return "Proposed revision of plan \(supersedes)"
        }
    }

    /// The card's one-line summary, immediately under the headline.
    ///
    /// The revision wording leads with the count because that is the number a person
    /// scans for — "did it change one thing or nine" is the question the diff exists to
    /// answer, and the answer should not require counting highlighted rows.
    public var summary: String {
        switch standing {
        case .firstPlan:
            return "No plan is in force yet, so this is the whole of it."
        case let .revision(supersedes, inEffectSince):
            let since = CalendarDayLabel.full(inEffectSince)
            switch changedRowCount {
            case 0:
                return "Nothing changes against plan \(supersedes), in effect since \(since)."
            case 1:
                return "One change against plan \(supersedes), in effect since \(since)."
            case let count:
                return "\(count) changes against plan \(supersedes), in effect since \(since)."
            }
        }
    }

    /// What tapping **accept** actually does, said before it is tapped.
    ///
    /// Worded as the boundary rather than as an outcome, because the boundary is the
    /// product: chat proposes, the athlete taps, and nothing reaches storage in between
    /// (§4.10, A13). An athlete who reads this sentence and taps knows they are opening a
    /// form, not saving a plan.
    public static let acceptExplanation =
        "Opening this fills in the plan editor. Nothing is saved until you set the start "
            + "date there and save it yourself — the plan in force does not change before then."

    /// What tapping **discard** does. The other half of the same promise.
    public static let discardExplanation = "Discarding leaves the plan in force exactly as it is."

    public static let acceptTitle = "Open in the plan editor"
    public static let discardTitle = "Discard"

    // MARK: - Building it

    /// Prepares the card for a proposal, against the session the handoff will use.
    ///
    /// - Parameters:
    ///   - proposal: the parsed, validated proposal — `PlanProposal.parse`'s output.
    ///   - session: `PlanAuthoring.session(revising:today:)`'s answer for the athlete's
    ///     stored plans. Its `mode` decides whether there is a diff to draw and its
    ///     `draft` is the "before" side; for a first plan the draft is the standard seed
    ///     and is deliberately **not** diffed against — an athlete has never seen it, so
    ///     "changed from 152 bpm" would be a comparison against a number they never
    ///     chose.
    ///   - distanceUnit: the athlete's display preference (MAX-047). Distances are stored
    ///     in metres always; this only decides what the card reads.
    ///
    /// - Throws: whatever `PlanDraft.applying(_:)` throws, which for a parsed proposal is
    ///   nothing — see that method's note.
    public static func build(
        applying proposal: PlanProposal,
        to session: PlanAuthoringSession,
        distanceUnit: DistanceUnit
    ) throws -> PlanProposalReview {
        let after = try session.draft.applying(proposal)

        let standing: Standing
        let before: PlanDraft?
        switch session.mode {
        case .firstPlan:
            standing = .firstPlan
            before = nil
        case let .revision(supersedes, inEffectSince):
            standing = .revision(supersedes: supersedes, inEffectSince: inEffectSince)
            before = session.draft
        }

        return PlanProposalReview(
            standing: standing,
            proposal: proposal,
            sections: [
                targetsSection(before: before, after: after),
                weekSection(before: before, after: after, distanceUnit: distanceUnit),
                arcSection(before: before, after: after, distanceUnit: distanceUnit),
                goalsSection(before: before, after: after),
            ],
            liftNote: liftNote(for: after)
        )
    }

    // MARK: - The sections

    private static func targetsSection(before: PlanDraft?, after: PlanDraft) -> Section {
        let isRevision = before != nil
        return Section(
            id: "targets",
            title: "Targets",
            rows: [
                row(
                    id: "heartRateCap",
                    label: "Heart-rate cap",
                    before: before.map { PlanCopy.heartRateCap($0.heartRateCapBPM) },
                    after: PlanCopy.heartRateCap(after.heartRateCapBPM),
                    isRevision: isRevision
                ),
                row(
                    id: "cadence",
                    label: "Cadence target",
                    before: before.map {
                        PlanCopy.cadenceBand(
                            lowStepsPerMinute: $0.cadenceLowStepsPerMinute,
                            highStepsPerMinute: $0.cadenceHighStepsPerMinute
                        )
                    },
                    after: PlanCopy.cadenceBand(
                        lowStepsPerMinute: after.cadenceLowStepsPerMinute,
                        highStepsPerMinute: after.cadenceHighStepsPerMinute
                    ),
                    isRevision: isRevision
                ),
                row(
                    id: "effectiveThreshold",
                    label: "Effective at",
                    before: before.map { PlanCopy.scorePoints($0.effectiveThresholdPoints) },
                    after: PlanCopy.scorePoints(after.effectiveThresholdPoints),
                    isRevision: isRevision
                ),
                row(
                    id: "marginalThreshold",
                    label: "Marginal at",
                    before: before.map { PlanCopy.scorePoints($0.marginalThresholdPoints) },
                    after: PlanCopy.scorePoints(after.marginalThresholdPoints),
                    isRevision: isRevision
                ),
            ]
        )
    }

    /// Seven rows, Monday-first, one per weekday — the **run** slot only.
    ///
    /// The lift slot is not diffed because a proposal cannot move it; `liftNote` says so
    /// in words rather than drawing seven rows that can never differ.
    private static func weekSection(
        before: PlanDraft?,
        after: PlanDraft,
        distanceUnit: DistanceUnit
    ) -> Section {
        let isRevision = before != nil
        let rows = Weekday.allCases.sorted().map { weekday in
            row(
                id: "week.\(weekday)",
                label: PlanCopy.weekday(weekday),
                before: before.map { runSlotText($0[weekday], distanceUnit: distanceUnit) },
                after: runSlotText(after[weekday], distanceUnit: distanceUnit),
                isRevision: isRevision
            )
        }
        return Section(id: "week", title: "The week", rows: rows)
    }

    /// One row per arc week present on either side, ascending, under a row stating the
    /// arc's length.
    ///
    /// A week the proposal drops is still shown — as a row saying so — rather than
    /// silently vanishing from the card. A shortened arc is exactly the kind of edit §4.6
    /// wants visible: it is how a sixteen-week block quietly becomes a twelve-week one.
    private static func arcSection(
        before: PlanDraft?,
        after: PlanDraft,
        distanceUnit: DistanceUnit
    ) -> Section {
        let isRevision = before != nil

        var beforeByWeek: [Int: Double] = [:]
        for week in before?.longRunArc ?? [] {
            beforeByWeek[week.index] = week.distanceMeters
        }
        var afterByWeek: [Int: Double] = [:]
        for week in after.longRunArc {
            afterByWeek[week.index] = week.distanceMeters
        }

        var rows = [
            row(
                id: "arc.length",
                label: "Arc length",
                before: before.map { weekCount($0.longRunArc.count) },
                after: weekCount(after.longRunArc.count),
                isRevision: isRevision
            )
        ]
        rows += Set(beforeByWeek.keys).union(afterByWeek.keys).sorted().map { index in
            row(
                id: "arc.\(index)",
                label: "Week \(index)",
                before: beforeByWeek[index].map { PlanCopy.distance($0, unit: distanceUnit) },
                after: afterByWeek[index]
                    .map { PlanCopy.distance($0, unit: distanceUnit) }
                    ?? "No longer in the arc",
                isRevision: isRevision
            )
        }
        return Section(id: "arc", title: "Long-run arc", rows: rows)
    }

    private static func goalsSection(before: PlanDraft?, after: PlanDraft) -> Section {
        let isRevision = before != nil
        return Section(
            id: "goals",
            title: "Goals",
            rows: [
                row(
                    id: "goals.statements",
                    label: "Stated goals",
                    before: before.map { goalText($0.goalStatements) },
                    after: goalText(after.goalStatements),
                    isRevision: isRevision
                ),
                row(
                    id: "goals.targetDay",
                    label: "Target day",
                    before: before.map { targetDayText($0.goalTargetDay) },
                    after: targetDayText(after.goalTargetDay),
                    isRevision: isRevision
                ),
            ]
        )
    }

    // MARK: - Row assembly

    /// The one place a change is decided.
    ///
    /// Comparing the **rendered** strings rather than the underlying `Double`s is
    /// deliberate. A cap of 148.0 and one of 148.2 render identically and are, to an
    /// athlete reading a card, the same plan; flagging that as a change would train them
    /// to ignore the highlight, which costs the diff its entire value. The card is a
    /// statement about what is displayed, so it diffs what is displayed.
    ///
    /// - Parameters:
    ///   - before: the plan in force's value for this field, or nil when the plan in
    ///     force has no such field. `isRevision` is what tells the two apart from "there
    ///     is no plan in force at all", which would otherwise look identical here.
    private static func row(
        id: String,
        label: String,
        before: String?,
        after: String,
        isRevision: Bool
    ) -> Row {
        let change: Change
        switch before {
        case .none:
            change = isRevision ? .added : .stated
        case let .some(previous) where previous == after:
            change = .unchanged
        case let .some(previous):
            change = .changed(from: previous)
        }
        return Row(id: id, label: label, value: after, change: change)
    }

    private static func runSlotText(_ day: PlanDraft.DayDraft, distanceUnit: DistanceUnit) -> String {
        // Unreachable: every draft reaching this type came either from a stored plan or
        // from `applying(_:)` over a validated proposal, and `DayDraft.session()` refuses
        // neither. A designed absence string rather than a force unwrap, which non-test
        // code may not write.
        guard let session = try? day.session() else { return "Not stated" }
        return PlanCopy.session(session, unit: distanceUnit)
    }

    private static func weekCount(_ count: Int) -> String {
        count == 1 ? "1 week" : "\(count) weeks"
    }

    private static func goalText(_ statements: String) -> String {
        let lines = statements
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return "None stated" }
        return lines.joined(separator: " · ")
    }

    private static func targetDayText(_ day: CalendarDay?) -> String {
        guard let day else { return "None stated" }
        return CalendarDayLabel.full(day)
    }

    // MARK: - Lifts

    /// See `liftNote`. Worded from what the applied draft actually carries, so the
    /// sentence names the athlete's real lift days rather than describing the feature.
    private static func liftNote(for after: PlanDraft) -> String {
        let liftDays = after.week
            .filter { $0.liftKind != .rest }
            .map { PlanCopy.weekday($0.weekday) }

        guard !liftDays.isEmpty else {
            return "Lifts are not part of a drafted plan. This proposal covers the run slot only, "
                + "and prescribes no lift days — set those in the plan editor."
        }
        return "Lifts are not part of a drafted plan, so your lift days carry through unchanged: "
            + liftDays.joined(separator: ", ") + ". Change those in the plan editor."
    }
}

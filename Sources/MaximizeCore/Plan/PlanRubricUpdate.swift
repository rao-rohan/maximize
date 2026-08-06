import Foundation

/// What adopting the rubric this build of the app ships would change about the bands a
/// stored plan version already carries (MAX-173).
///
/// ## The gap this exists to close
///
/// D1 makes the plan versioned data, and `StandardPlanSeed` is authoring *input*: it
/// supplies the bands a **first** plan starts from and is then out of the loop forever.
/// That is exactly the property that keeps a threshold out of code — and it is also why,
/// before this type, a correction to a seed band could never reach anybody. Every
/// revision was built with `rubricBands: current.rubric.bands`, so the fixes MAX-132 and
/// MAX-146 wrote (the three `lift.*` adherence bands; `.actualDiscipline(oneOf: [.run])`
/// on `rest.ranAnyway`) were unreachable on any device whose plan already existed. Chat
/// proposals go through the same authoring door, so they inherited the same stale bands.
///
/// The mechanism D1 provides for a rubric change is a **new plan version**, and that is
/// what `PlanAuthoringSession` now writes. This type is the description of the change,
/// so the athlete is told what a save adopts rather than having it swapped underneath
/// them.
///
/// ## Why this is stated in rationales rather than diffed band by band
///
/// A `RubricBand` is an identifier, an ordered condition list, a score range and a
/// rationale. Four of those five are not renderable to a person in any useful way —
/// *"`.metric(averageHeartRateBPM, greaterThan, .heartRateCap(offsetBPM: 8))` gained
/// `.actualDiscipline(oneOf: [.run])`"* is a sentence about a data structure, not about
/// training, and an athlete asked to approve it can only guess. What **is** renderable is
/// `RubricBand.rationale`: it is the line that appears in a verdict header (FR-1.1), so a
/// new rule can be shown in the exact words it will later use. So this carries counts and
/// rationales, and the surfaces built on it state the change plainly instead of pretending
/// to a diff nobody could read.
///
/// ## Emptiness is the whole safety property
///
/// `isEmpty` is true exactly when the two band lists are the same rules in the same order
/// — and band order is part of a rubric's meaning, since `RubricEvaluator` takes the first
/// match. A plan already carrying the current bands therefore produces no notice, no
/// control and no change, which is what keeps this from nagging every athlete who is
/// already up to date.
public struct PlanRubricUpdate: Hashable, Sendable {

    /// Rationales of rules the current rubric has and the stored one does not, in rubric
    /// order — the words a verdict will use once this version is in effect.
    public let addedRules: [String]

    /// Rationales of rules present in both under the same identifier, whose bands differ
    /// in any way: conditions, score range, applicability or wording. The **current**
    /// rationale, because that is what a verdict would say from here on.
    public let changedRules: [String]

    /// Rationales of rules the stored rubric has and the current one does not, taken from
    /// the stored band, because that is the wording being withdrawn.
    public let removedRules: [String]

    /// Whether the rules the two rubrics share are checked in a different order.
    ///
    /// Worth its own flag rather than folding into `changedRules`: first-match-wins means
    /// a reorder can change every verdict on a day without a single band differing, and a
    /// summary that said "nothing changed" in that case would be false.
    public let reordersExistingRules: Bool

    /// Nothing to adopt: the same rules, in the same order.
    public var isEmpty: Bool {
        addedRules.isEmpty
            && changedRules.isEmpty
            && removedRules.isEmpty
            && !reordersExistingRules
    }

    /// How many rules this touches — added, changed and withdrawn together. A reorder is
    /// deliberately not counted: it is a fact about the list, not about a number of rules,
    /// and adding one to a count would misstate it.
    public var ruleCount: Int {
        addedRules.count + changedRules.count + removedRules.count
    }

    /// - Parameters:
    ///   - stored: the bands the version being superseded was saved with.
    ///   - current: `StandardPlanSeed.rubricBands()`, the bands this build ships.
    ///
    /// Identifiers are assumed unique within each list, which `ScoringRubric.init`
    /// enforces for anything that ever reached a `Plan`; a duplicate would be resolved to
    /// its first occurrence here rather than crashing.
    init(stored: [RubricBand], current: [RubricBand]) {
        var storedByIdentifier: [String: RubricBand] = [:]
        for band in stored where storedByIdentifier[band.identifier] == nil {
            storedByIdentifier[band.identifier] = band
        }
        var currentByIdentifier: [String: RubricBand] = [:]
        for band in current where currentByIdentifier[band.identifier] == nil {
            currentByIdentifier[band.identifier] = band
        }

        var added: [String] = []
        var changed: [String] = []
        for band in current {
            guard let previous = storedByIdentifier[band.identifier] else {
                added.append(band.rationale)
                continue
            }
            if previous != band {
                changed.append(band.rationale)
            }
        }

        var removed: [String] = []
        for band in stored where currentByIdentifier[band.identifier] == nil {
            removed.append(band.rationale)
        }

        // Compared over the identifiers the two lists share, so an added or withdrawn rule
        // does not read as a reorder of everything after it.
        let sharedStoredOrder = stored
            .map(\.identifier)
            .filter { currentByIdentifier[$0] != nil }
        let sharedCurrentOrder = current
            .map(\.identifier)
            .filter { storedByIdentifier[$0] != nil }

        self.addedRules = added
        self.changedRules = changed
        self.removedRules = removed
        self.reordersExistingRules = sharedStoredOrder != sharedCurrentOrder
    }
}

import Foundation
import MaximizeCore
import Observation

/// Drives the plan-authoring screen (MAX-080): opens a session against whatever is
/// stored, holds the draft the controls bind to, and writes the finished version.
///
/// Same shape as `SettingsModel`, deliberately, down to the `LoadState`: the view
/// observes `state` and forwards intent, and the repository is an optional parameter
/// that — left nil — resolves to `PersistenceComposition.store` and to nothing else.
/// MAX-049 was exactly a defaulted parameter reaching a no-op stub in production; there
/// is no stub here to reach, and a store that could not be opened is `.failed` rather
/// than "no plan authored yet". Those two are very different sentences to show an
/// athlete: the first means *try again later*, the second means *the app cannot score
/// anything until you do this*.
///
/// **No plan logic lives here.** Which version number the write takes, the earliest day
/// it may start, whether the draft converts, and what the version would govern are all
/// `PlanAuthoringSession`'s answers, computed in `MaximizeCore` under test. What is
/// genuinely this layer's is the two things the core declines to do: read the wall
/// clock, and pick a time zone to turn an instant into a civil day.
///
/// ## Opening prefilled from a chat proposal (MAX-101, §4.6)
///
/// `init(proposal:)` is the handoff target for the proposal card. The session is still
/// derived exactly as it always was — against whatever is stored, at load time — and the
/// proposal is then applied to *that* session's draft (`PlanDraft.applying(_:)`). Two
/// consequences worth naming:
///
/// - **The version and the effective date still come from storage, never from the
///   model.** §4.4 forbids a proposal carrying either, and this screen would ignore them
///   if it did: `session.version` and `session.suggestedEffectiveFrom` are computed here
///   the same way they are for a hand-authored revision.
/// - **Prefilling is not saving.** Nothing is written by `load()`. The athlete still sets
///   the date and taps Save, and `save()` is still the only method that touches
///   `PlanRepository.store(_:)` — A13's door, opened by hand.
@MainActor
@Observable
final class PlanAuthoringModel {

    enum LoadState: Equatable {
        case loading
        case editing(Editing)
        /// The store could not be opened, or a read failed. Never shown for "no plan
        /// exists" — that is an `Editing` state whose session is `.firstPlan`.
        case failed
    }

    struct Editing: Equatable {
        let session: PlanAuthoringSession
        /// The athlete's display unit (MAX-047). Distances are stored in metres always;
        /// this only decides what the steppers read.
        let distanceUnit: DistanceUnit
        var draft: PlanDraft
        var effectiveFrom: CalendarDay
        /// The week this version would govern, or empty while the draft does not
        /// convert.
        var governedDays: [PlanDay]
        /// Why the draft cannot be saved, in the athlete's words. Nil when it can.
        var problem: String?
        /// Set after a successful write, and cleared by the next edit.
        var confirmation: String?

        /// Why this form arrived already filled in, when it did (MAX-101). Nil for the
        /// ordinary case: an athlete who opened the screen from the plan tab is not
        /// prefilled from anything and does not need telling so.
        ///
        /// Survives an edit, unlike `confirmation`: where the values came from stays true
        /// however many of them the athlete then changes, and a note that vanished on the
        /// first keystroke would leave them wondering what they were looking at.
        var prefill: PlanPrefillNotice?

        var canSave: Bool { problem == nil }
    }

    /// The banner shown when the form was filled in from a chat proposal (§4.6's
    /// handoff).
    ///
    /// Every string here is the core's, taken from a `PlanProposalReview` rebuilt against
    /// *this* screen's session — so the headline on the form is the same headline the
    /// card said a tap ago. The lift slot no longer needs a sentence of its own here
    /// (MAX-141): it prefills the same way the run slot does, and the form's own week
    /// section shows what was carried over.
    struct PlanPrefillNotice: Equatable {
        let headline: String
        let explanation: String
    }

    private(set) var state: LoadState = .loading
    private(set) var isSaving = false

    private let planRepository: (any PlanRepository)?
    private let settingsRepository: (any SettingsRepository)?
    private let timeZone: TimeZone
    private let todayOverride: CalendarDay?

    /// The chat proposal this screen was opened with, if any (MAX-101). Held rather than
    /// applied at `init` because the session it applies *to* does not exist until
    /// `load()` has read the store — and applying it to a session built from stale data
    /// is exactly the failure the handoff is shaped to avoid.
    ///
    /// Cleared by a successful `save()`, which reloads: at that moment the screen is
    /// authoring the version *after* the one just written, and re-applying the proposal
    /// on top of it — banner and all — would offer to make the same change twice.
    private var proposal: PlanProposal?

    /// - Parameters:
    ///   - planRepository: defaults to `PersistenceComposition.store`. Overridable only
    ///     so a preview or a test can inject a fake; there is deliberately no other
    ///     fallback (see the type's note on MAX-049).
    ///   - settingsRepository: same, for the display unit.
    ///   - today: the athlete's civil day. Defaults to now in `timeZone`; pinned by
    ///     tests and previews so the screen does not depend on the wall clock.
    ///   - timeZone: the zone an instant becomes a day in. `.current` is the honest
    ///     answer for a single-user, single-device app, and it is threaded in from here
    ///     rather than read inside `MaximizeCore` — matching `WorkoutDetailModel` and
    ///     `ScoreCalendarModel`.
    ///   - proposal: a chat proposal to prefill the form with (MAX-101), or nil for the
    ///     ordinary case of an athlete opening the screen to author by hand. Applied to
    ///     the session `load()` builds, never to one built ahead of it.
    init(
        planRepository: (any PlanRepository)? = nil,
        settingsRepository: (any SettingsRepository)? = nil,
        today: CalendarDay? = nil,
        timeZone: TimeZone = .current,
        proposal: PlanProposal? = nil
    ) {
        // Written as `if let` rather than `??` for the reason `SettingsModel` is: the
        // fallback is a concrete `MaximizeStore?` and the property is an existential,
        // and spelling the coercion out leaves nothing for inference to get wrong.
        if let planRepository {
            self.planRepository = planRepository
        } else {
            self.planRepository = PersistenceComposition.store
        }
        if let settingsRepository {
            self.settingsRepository = settingsRepository
        } else {
            self.settingsRepository = PersistenceComposition.store
        }
        self.timeZone = timeZone
        self.todayOverride = today
        self.proposal = proposal
    }

    // MARK: - Loading

    func load() async {
        guard let planRepository,
              let today = todayOverride ?? (try? CalendarDay(Date(), in: timeZone))
        else {
            state = .failed
            return
        }
        do {
            let session = try PlanAuthoring.session(
                revising: try await planRepository.planCalendar(),
                today: today
            )
            let unit = await loadedDistanceUnit()
            let applied = try prefilled(session: session, distanceUnit: unit)
            state = .editing(
                refreshed(
                    Editing(
                        session: session,
                        distanceUnit: unit,
                        draft: applied?.draft ?? session.draft,
                        effectiveFrom: session.suggestedEffectiveFrom,
                        governedDays: [],
                        problem: nil,
                        confirmation: nil,
                        prefill: applied?.notice
                    )
                )
            )
        } catch {
            state = .failed
        }
    }

    /// Applies the chat proposal, if there is one, and prepares the banner explaining
    /// that the form arrived filled in (MAX-101, §4.6).
    ///
    /// The review is rebuilt here rather than carried across the handoff, and that is
    /// deliberate: a review built in chat describes the session chat saw, and this screen
    /// has just read the store again. Rebuilding is what keeps the banner's headline true
    /// of the draft actually on screen.
    ///
    /// - Throws: from `PlanDraft.applying(_:)`, which for a parsed proposal throws
    ///   nothing — a failure here reaches `.failed` rather than silently opening an
    ///   un-prefilled form, because a form that quietly ignored the proposal would look
    ///   like the model had proposed the seed.
    private func prefilled(
        session: PlanAuthoringSession,
        distanceUnit: DistanceUnit
    ) throws -> (draft: PlanDraft, notice: PlanPrefillNotice)? {
        guard let proposal else { return nil }
        let review = try PlanProposalReview.build(
            applying: proposal,
            to: session,
            distanceUnit: distanceUnit
        )
        return (
            draft: try session.draft.applying(proposal),
            notice: PlanPrefillNotice(
                headline: review.headline,
                explanation: PlanProposalReview.acceptExplanation
            )
        )
    }

    /// A settings read that fails is not a reason to refuse to author a plan — the unit
    /// is a display preference, and `AppSettings.standard`'s is a defensible answer.
    /// A *plan* read that fails is a different matter and does reach `.failed`.
    private func loadedDistanceUnit() async -> DistanceUnit {
        guard let settingsRepository,
              let settings = try? await settingsRepository.settings()
        else {
            return AppSettings.standard.distanceUnit
        }
        return settings.distanceUnit
    }

    // MARK: - Editing

    /// Applies an edit and re-derives everything that depends on it.
    ///
    /// A closure rather than one forwarding method per field: the mutating methods on
    /// `PlanDraft` are the vocabulary (and they are the ones that keep a rest day from
    /// carrying a distance), so the view names the edit it wants and this stays the
    /// single place that revalidates afterwards.
    func edit(_ transform: (inout PlanDraft) -> Void) {
        guard case .editing(var editing) = state else { return }
        transform(&editing.draft)
        editing.confirmation = nil
        state = .editing(refreshed(editing))
    }

    /// The effective date as the instant a `DatePicker` binds to, and back.
    ///
    /// The picker speaks `Date`; the plan speaks `CalendarDay`, which carries no time
    /// and no zone precisely so a run at 23:40 cannot drift onto the next day. This
    /// pair is the only place the two meet on this screen.
    ///
    /// **Noon, not midnight** — the same choice, and the same reason, as
    /// `TrendIntervalSelectionModel.date(forSeeding:in:)`: a spring-forward can delete
    /// 00:00–00:59 in some zones entirely, so a midnight-anchored instant can land on
    /// the wrong civil day when read back. Noon has never been skipped.
    var effectiveFromDate: Date? {
        guard case let .editing(editing) = state else { return nil }
        return instant(atNoonOn: editing.effectiveFrom)
    }

    /// The earliest instant the picker may offer, or nil when any date is permitted (a
    /// first plan). Bounding the control is how MAX-080's "do not offer a date that
    /// will be rejected" is met; `PlanAuthoringSession` checks it again regardless.
    var earliestEffectiveFromDate: Date? {
        guard case let .editing(editing) = state,
              let earliest = editing.session.earliestEffectiveFrom
        else { return nil }
        return instant(atNoonOn: earliest)
    }

    func setEffectiveFrom(date: Date) {
        guard let day = try? CalendarDay(date, in: timeZone) else { return }
        setEffectiveFrom(day)
    }

    private func instant(atNoonOn day: CalendarDay) -> Date {
        var components = DateComponents()
        components.year = day.year
        components.month = day.month
        components.day = day.day
        components.hour = 12
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        // Unreachable for a valid `CalendarDay` in a real zone; `Date()` rather than a
        // force unwrap because non-test code may not force-unwrap.
        return calendar.date(from: components) ?? Date()
    }

    func setEffectiveFrom(_ day: CalendarDay) {
        guard case .editing(var editing) = state else { return }
        editing.effectiveFrom = day
        editing.confirmation = nil
        state = .editing(refreshed(editing))
    }

    /// Asks the session what this candidate would govern, and records why it could not
    /// be asked when it could not. This is the only place `problem` is written, so the
    /// message on screen is always about the draft currently on screen.
    private func refreshed(_ editing: Editing) -> Editing {
        var editing = editing
        do {
            editing.governedDays = try editing.session.governedDays(
                from: editing.draft,
                effectiveFrom: editing.effectiveFrom
            )
            editing.problem = nil
        } catch let error as PlanAuthoringError {
            editing.governedDays = []
            editing.problem = error.description
        } catch {
            editing.governedDays = []
            editing.problem = FailureCopy.planCouldNotBePrepared
        }
        return editing
    }

    private func markProblem(_ problem: String, on editing: Editing) {
        var updated = editing
        updated.problem = problem
        updated.confirmation = nil
        state = .editing(updated)
    }

    // MARK: - Saving

    /// Writes the candidate as a **new version** and reopens the screen on top of it.
    ///
    /// Reloading rather than patching the state in place is what makes the D1 story
    /// visible: the moment a version is saved, the screen is authoring the *next* one,
    /// its earliest permitted date has moved past the version just written, and the
    /// draft is a copy of what was saved. There is no state in which the screen is
    /// still editing a version that exists on disk.
    func save() async {
        guard case let .editing(editing) = state, let planRepository, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        let saved: Plan
        do {
            saved = try editing.session.plan(from: editing.draft, effectiveFrom: editing.effectiveFrom)
            try await planRepository.store(saved)
        } catch let error as PlanAuthoringError {
            markProblem(error.description, on: editing)
            return
        } catch {
            markProblem(FailureCopy.planVersionCouldNotBeSaved, on: editing)
            return
        }

        // The proposal has been acted on; the next version is authored from what was
        // saved. See the property's own note.
        proposal = nil
        await load()
        guard case .editing(var reloaded) = state else { return }
        reloaded.confirmation = "Saved plan \(saved.version), effective from \(saved.effectiveFrom)."
        state = .editing(reloaded)
    }
}

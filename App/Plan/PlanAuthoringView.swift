import SwiftUI
import MaximizeCore

/// Authoring and revising the training plan (MAX-080).
///
/// ## What this screen is, and what it deliberately is not
///
/// It is the only way a `Plan` record comes into existence. Before it, nothing in the
/// app called `PlanRepository.store(_:)`, so `planCalendar()` answered nil forever and
/// every run ingested as `.noPlanAuthored` — captured, but with no derived metrics
/// (they are measured against the plan's cap), therefore no score, therefore no chat.
///
/// It is **not** a rubric editor. The ordered band conditions of PRD §10.3 are carried
/// forward from the version being revised, or seeded on a first plan; what is editable
/// here is every value an athlete has a number in mind for — the HR cap, the cadence
/// band, the two score thresholds, the weekly template, and the long-run arc. Editing
/// band conditions needs a structured rule editor and is its own ticket.
///
/// ## Every control here writes a new version
///
/// D1: changing a threshold is a new plan version, never an edit. There is no "save
/// changes" on the current plan, because that operation does not exist — `Plan`'s
/// properties are `let`, `PlanDraft` cannot address a stored version, and the only door
/// from draft to plan stamps the next version number. The save button says so, and
/// after a save the screen is authoring the version after the one just written.
///
/// The view holds no plan logic. Every branch below reads a value `PlanAuthoringModel`
/// already resolved from `PlanAuthoringSession`, which is where the decisions live and
/// where CI can see them.
struct PlanAuthoringView: View {
    @State private var model: PlanAuthoringModel

    /// MAX-166: non-nil exactly while the conversational-route sheet is up. Carries the
    /// subject resolved **at the moment of the tap**, matching `RootTabView.chatOpening`'s
    /// own reasoning — what opens is what the button said it would open, not whatever
    /// "this week" happens to resolve to by the time the sheet's closure runs.
    @State private var conversationalRouteOpening: ConversationalRouteOpening?

    /// `ChatSubject` is `Hashable`, which is all `sheet(item:)` needs of an identifier —
    /// mirrors `RootTabView.ChatOpening` exactly, one file only needing it for one door.
    private struct ConversationalRouteOpening: Identifiable {
        let subject: ChatSubject
        var id: ChatSubject { subject }
    }

    /// - Parameters:
    ///   - planRepository/settingsRepository/workoutRepository: forwarded to
    ///     `PlanAuthoringModel`, which defaults them to `PersistenceComposition.store` —
    ///     never to a stub. See that type's docs. The workout store is read only to say
    ///     what a first plan's date costs (MAX-165); this screen writes no workout.
    ///   - proposal: a chat proposal to open prefilled from (MAX-101, §4.6). Nil is the
    ///     ordinary case — an athlete opening the screen from the plan tab or Settings.
    ///     Prefilling changes nothing about how this screen saves: the version number and
    ///     the permitted date range are still derived from storage, and Save is still the
    ///     only thing that writes.
    init(
        planRepository: (any PlanRepository)? = nil,
        settingsRepository: (any SettingsRepository)? = nil,
        workoutRepository: (any WorkoutRepository)? = nil,
        proposal: PlanProposal? = nil
    ) {
        _model = State(
            initialValue: PlanAuthoringModel(
                planRepository: planRepository,
                settingsRepository: settingsRepository,
                workoutRepository: workoutRepository,
                proposal: proposal
            )
        )
    }

    var body: some View {
        Form {
            switch model.state {
            case .loading:
                ProgressView()
            case .failed:
                Section {
                    quietText(FailureCopy.couldNotLoad(.planAuthoring))
                }
            case let .editing(editing):
                editingSections(editing)
            }
        }
        .navigationTitle("Training plan")
        .task { await model.load() }
        // MAX-166: the conversational route's own presentation, entirely separate from
        // this screen's `Form` state — tapping it neither saves nor discards the draft
        // underneath, matching `SettingsView`'s `isAuthoringPlan` sheet for the same
        // reason: presentation and the plan being edited are two different facts.
        .sheet(item: $conversationalRouteOpening) { opening in
            ChatSheet(subject: opening.subject, currentInterval: conversationalRouteInterval())
        }
    }

    /// Split into two groups only because `ViewBuilder` takes at most ten children and
    /// this screen has more sections than that; nothing else distinguishes the halves.
    @ViewBuilder
    private func editingSections(_ editing: PlanAuthoringModel.Editing) -> some View {
        Group {
            prefillSection(editing)
            statusSection(editing)
            conversationalRouteSection(editing)
            effectiveFromSection(editing)
            capSection(editing)
            durationFloorSection(editing)
            cadenceSection(editing)
            thresholdsSection(editing)
            rubricSection(editing)
        }
        Group {
            weekSection(editing)
            arcSection(editing)
            goalsSection(editing)
            previewSection(editing)
            saveSection(editing)
        }
    }

    // MARK: - Arrived from a chat proposal (MAX-101)

    /// Says, at the top of the form, that these values came from a conversation and that
    /// none of them is saved yet.
    ///
    /// Absent entirely for a hand-authored plan — an athlete who opened this screen and
    /// typed is not prefilled from anything and does not need telling so. That makes this
    /// the rare section whose absence is correct rather than a designed empty state.
    ///
    /// Every string comes from the core (`PlanProposalReview`), so the headline here is
    /// the same one the card said a tap ago.
    @ViewBuilder
    private func prefillSection(_ editing: PlanAuthoringModel.Editing) -> some View {
        if let prefill = editing.prefill {
            Section("From your conversation") {
                Text(prefill.headline)
                quietText(prefill.explanation)
            }
        }
    }

    // MARK: - Where the plan stands

    @ViewBuilder
    private func statusSection(_ editing: PlanAuthoringModel.Editing) -> some View {
        Section("Current plan") {
            Text(PlanAuthoringFormatting.describe(editing.session.mode))
            quietText(PlanAuthoringFormatting.explain(editing.session.mode))
        }
    }

    // MARK: - The conversational route (MAX-166)

    /// FIRST-RUN-SPEC §10/§12: the door to `ChatConversationView`'s existing "Draft a plan
    /// from this conversation" (MAX-101), offered here because this is where a person who
    /// dislikes the form below is already standing — placed right after "Current plan" so
    /// that reading it is the decision, not something found after scrolling past every
    /// stepper on this screen.
    ///
    /// **Never hidden.** `editing.conversationalRoute` (`PlanAuthoringConversationalRoute`,
    /// `MaximizeCore`) decides whether the button is enabled and always supplies the
    /// sentence under it — a missing key reads as a designed absence, not a control that
    /// silently stopped appearing. This view renders exactly what that value says and
    /// decides nothing itself.
    ///
    /// That includes MAX-190's fix for `docs/CHAT-AUDIT.md` §2.6: when this screen was
    /// itself pushed by `ChatSheet` from an accepted proposal, `conversationalRoute`
    /// disables this same button rather than let it open a second `ChatSheet` on top of
    /// the first. The section still renders unconditionally on every path — the gate is
    /// entirely `PlanAuthoringConversationalRoute`'s, never a branch here.
    @ViewBuilder
    private func conversationalRouteSection(_ editing: PlanAuthoringModel.Editing) -> some View {
        Section {
            Button(PlanAuthoringConversationalRoute.actionLabel) {
                conversationalRouteTapped()
            }
            .disabled(!editing.conversationalRoute.isAvailable)
            .accessibilityHint(
                "Opens a conversation you describe the plan in. Nothing is saved until you "
                    + "review it on this screen."
            )

            quietText(editing.conversationalRoute.explanation)
        }
    }

    /// A14: presents the sheet and nothing else. No call fires until the athlete sends a
    /// message inside the conversation this opens.
    private func conversationalRouteTapped() {
        guard let subject = conversationalRouteSubject() else { return }
        conversationalRouteOpening = ConversationalRouteOpening(subject: subject)
    }

    /// "This week", the same fallback `ChatSheet.defaultInterval()` resolves to when
    /// nothing live is handed in. This screen has no dashboard interval to read — only
    /// `RootTabView` owns the one live selection (§3.4) — so it resolves its own the same
    /// way that fallback does, deliberately duplicated rather than reaching across files
    /// this ticket did not touch. Nil only where `CalendarDay`'s 1...9999 AD domain
    /// cannot express today, matching every other caller of this pattern.
    private func conversationalRouteInterval() -> TrendInterval? {
        guard let today = try? CalendarDay(Date(), in: .current) else { return nil }
        return try? TrendInterval.thisWeek(today: today)
    }

    /// A fresh training thread, frozen to `conversationalRouteInterval()` — matching how
    /// `ChatSheet.startNewTrainingChat()` freezes the dashboard's own selection into a
    /// `TrainingScope`. Nil in the same close-to-unreachable case the interval above is.
    private func conversationalRouteSubject() -> ChatSubject? {
        guard let interval = conversationalRouteInterval(),
              let scope = try? TrainingScope(resolving: interval)
        else { return nil }
        return .training(scope)
    }

    // MARK: - When it takes effect

    @ViewBuilder
    private func effectiveFromSection(_ editing: PlanAuthoringModel.Editing) -> some View {
        Section("Takes effect") {
            // Two DatePickers rather than one with an optional bound: SwiftUI's ranged
            // and unranged initialisers are different overloads, and a first plan is
            // genuinely unbounded — it is the only version allowed to reach backwards,
            // and doing so is how runs already on the device come under a plan.
            if let earliest = model.earliestEffectiveFromDate {
                DatePicker(
                    "First day governed",
                    selection: effectiveFromBinding,
                    in: earliest...,
                    displayedComponents: .date
                )
            } else {
                DatePicker(
                    "First day governed",
                    selection: effectiveFromBinding,
                    displayedComponents: .date
                )
            }

            if editing.session.earliestEffectiveFrom != nil {
                quietText(
                    "A new version has to start after the current one. Earlier dates are not "
                        + "offered, because a version that reached back would re-govern days "
                        + "that have already been scored."
                )
            }

            // MAX-165: what this date costs, in the athlete's own figures. Absent when it
            // costs nothing — the core returns nil rather than a rendered zero, so the
            // ordinary case does not read as a warning. Every word and the number itself
            // are `PlanAuthoringSession`'s; nothing is decided here.
            if let excluded = editing.excludedWorkoutsNotice {
                quietText(excluded)
            }
        }
    }

    private var effectiveFromBinding: Binding<Date> {
        Binding(
            get: { model.effectiveFromDate ?? Date() },
            set: { model.setEffectiveFrom(date: $0) }
        )
    }

    // MARK: - The tunable numbers

    @ViewBuilder
    private func capSection(_ editing: PlanAuthoringModel.Editing) -> some View {
        Section("Easy-run heart-rate cap") {
            Stepper(
                value: Binding(
                    get: { editing.draft.heartRateCapBPM },
                    set: { value in model.edit { $0.heartRateCapBPM = value } }
                ),
                in: 100...220,
                step: 1
            ) {
                row("Cap", "\(Int(editing.draft.heartRateCapBPM)) bpm")
            }

            quietText(
                "Drawn on every HR curve, and the anchor the rubric's bands are written "
                    + "against — moving it moves them with it."
            )
        }
    }

    /// A plan-level value (MAX-151), so it sits beside the cap rather than in the weekly
    /// grid — see `PlanProposalReview.targetsSection`'s own row for the same field, so
    /// the card and this screen never say a plan's floor two different things.
    @ViewBuilder
    private func durationFloorSection(_ editing: PlanAuthoringModel.Editing) -> some View {
        Section("Fragment duration floor") {
            Stepper(
                value: durationFloorMinutesBinding(
                    seconds: editing.draft.minimumSessionDurationSeconds
                ),
                in: 0...30,
                step: 1
            ) {
                row(
                    "Floor",
                    editing.draft.minimumSessionDurationSeconds
                        .map { PlanAuthoringFormatting.duration($0) } ?? "None"
                )
            }

            quietText(
                "A recorded run with heart-rate data but no distance sample — a treadmill "
                    + "started before the belt moved, an indoor track with no GPS lock — "
                    + "shorter than this reads as a mis-started session rather than a real "
                    + "one. A run that does carry a distance is judged on distance instead; "
                    + "this only ever applies when there is none to test."
            )
        }
    }

    /// Steps in whole minutes, stored in seconds. Zero reads as "no floor stated" rather
    /// than a floor of zero seconds, matching `liftDurationMinutesBinding`'s own "None"
    /// convention below.
    private func durationFloorMinutesBinding(seconds: Double?) -> Binding<Double> {
        Binding(
            get: { ((seconds ?? 0) / 60).rounded() },
            set: { minutes in
                model.edit {
                    $0.minimumSessionDurationSeconds = minutes <= 0 ? nil : minutes * 60
                }
            }
        )
    }

    @ViewBuilder
    private func cadenceSection(_ editing: PlanAuthoringModel.Editing) -> some View {
        Section("Cadence target") {
            Stepper(
                value: Binding(
                    get: { editing.draft.cadenceLowStepsPerMinute },
                    set: { value in model.edit { $0.cadenceLowStepsPerMinute = value } }
                ),
                in: 120...220,
                step: 1
            ) {
                row("Lower", "\(Int(editing.draft.cadenceLowStepsPerMinute)) spm")
            }

            Stepper(
                value: Binding(
                    get: { editing.draft.cadenceHighStepsPerMinute },
                    set: { value in model.edit { $0.cadenceHighStepsPerMinute = value } }
                ),
                in: 120...220,
                step: 1
            ) {
                row("Upper", "\(Int(editing.draft.cadenceHighStepsPerMinute)) spm")
            }
        }
    }

    @ViewBuilder
    private func thresholdsSection(_ editing: PlanAuthoringModel.Editing) -> some View {
        Section("Score thresholds") {
            Stepper(
                value: Binding(
                    get: { editing.draft.effectiveThresholdPoints },
                    set: { value in model.edit { $0.effectiveThresholdPoints = value } }
                ),
                in: ScoreValue.permittedRange,
                step: 1
            ) {
                row("Effective at", "\(editing.draft.effectiveThresholdPoints)")
            }

            Stepper(
                value: Binding(
                    get: { editing.draft.marginalThresholdPoints },
                    set: { value in model.edit { $0.marginalThresholdPoints = value } }
                ),
                in: ScoreValue.permittedRange,
                step: 1
            ) {
                row("Marginal at", "\(editing.draft.marginalThresholdPoints)")
            }

            quietText("The two cut points behind the calendar's green, amber and red.")
        }
    }

    // MARK: - How workouts are judged (MAX-173)

    /// The one place the app can adopt a corrected rubric, and it does so by writing a new
    /// plan version like everything else on this screen.
    ///
    /// **Absent whenever there is nothing to adopt**, which is the ordinary case for an
    /// athlete already up to date and for every first plan. That is a designed absence in
    /// the strict sense — the core returns nil rather than "no changes", for
    /// `excludedWorkoutsNotice`'s reason: a row that always says nothing is a row read and
    /// dismissed on every visit.
    ///
    /// **The switch is on when the section appears**, because the core's session adopts by
    /// default (`PlanAuthoringSession.adoptsCurrentRubric`, which carries the argument).
    /// So this offers a decline rather than an opt-in, and states what declining leaves in
    /// place. Nothing here decides anything: every sentence, and the fact there is a
    /// section at all, is `PlanAuthoringSession`'s answer.
    ///
    /// **No band-level diff, deliberately.** A rendered `RubricCondition` is a sentence
    /// about a data structure; a `RubricBand.rationale` is the line the athlete will read
    /// on a verdict. So the rules are listed in the words they will use, under a plain
    /// statement of how many changed. See `PlanRubricUpdate`.
    @ViewBuilder
    private func rubricSection(_ editing: PlanAuthoringModel.Editing) -> some View {
        if let notice = editing.session.rubricUpdateNotice {
            Section("How workouts are judged") {
                Text(notice)

                Toggle(
                    PlanCopy.rubricAdoptionTitle,
                    isOn: Binding(
                        get: { editing.session.adoptsCurrentRubric },
                        set: { model.setAdoptsCurrentRubric($0) }
                    )
                )

                if editing.session.adoptsCurrentRubric {
                    ruleList(PlanCopy.rubricUpdateAddedHeading, editing.session.rubricUpdate.addedRules)
                    ruleList(PlanCopy.rubricUpdateChangedHeading, editing.session.rubricUpdate.changedRules)
                    ruleList(PlanCopy.rubricUpdateRemovedHeading, editing.session.rubricUpdate.removedRules)
                    quietText(PlanCopy.rubricUpdatePermanence)
                } else if let decline = editing.session.rubricUpdateDeclineNotice {
                    quietText(decline)
                }
            }
        }
    }

    /// A heading and the rules under it, or nothing at all when that category is empty.
    ///
    /// Keyed by position rather than by the rationale itself: two bands are free to share a
    /// rationale — `ScoringRubric` only requires *identifiers* to be unique — and a
    /// `ForEach` with duplicate identities renders unpredictably. The list is rebuilt whole
    /// or not at all, so a positional identity has nothing to get wrong here.
    @ViewBuilder
    private func ruleList(_ heading: String, _ rules: [String]) -> some View {
        if !rules.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.tight) {
                quietText(heading)
                ForEach(rules.indices, id: \.self) { index in
                    Text(rules[index])
                }
            }
            .padding(.vertical, Spacing.hairspace)
        }
    }

    // MARK: - The recurring week

    @ViewBuilder
    private func weekSection(_ editing: PlanAuthoringModel.Editing) -> some View {
        Section("Weekly template") {
            ForEach(editing.draft.week) { day in
                VStack(alignment: .leading, spacing: Spacing.snug) {
                    // The weekday, and the fact both slots roll up to — the caption a
                    // scanning eye reads before either picker's own detail, so checking
                    // a proposed week means reading the caption down the list rather
                    // than opening fourteen pickers (MAX-137).
                    VStack(alignment: .leading, spacing: Spacing.hairspace) {
                        Text(PlanAuthoringFormatting.describe(day.weekday))
                            .font(.sectionHeading)
                        quietText(PlanAuthoringFormatting.describe(day.obligationSummary))
                    }

                    Picker(
                        "Run",
                        selection: Binding(
                            get: { day.kind },
                            set: { kind in model.edit { $0.setKind(kind, on: day.weekday) } }
                        )
                    ) {
                        // `prescribable`, not `allCases`: offering `.lift` here would
                        // put a lift ask where the run ask goes. The core owns that
                        // rule; see `ScheduledSessionKind.prescribable`.
                        ForEach(ScheduledSessionKind.prescribable, id: \.self) { kind in
                            Text(PlanAuthoringFormatting.describe(kind)).tag(kind)
                        }
                    }
                    .pickerStyle(.menu)

                    if day.kind != .rest {
                        Stepper(
                            value: distanceBinding(for: day.weekday, meters: day.distanceMeters),
                            in: distanceRange(editing.distanceUnit, from: 0, to: 60),
                            step: editing.distanceUnit.meters(fromConverted: 0.5)
                        ) {
                            row(
                                "Distance",
                                day.distanceMeters.map {
                                    PlanAuthoringFormatting.distance($0, unit: editing.distanceUnit)
                                } ?? "None"
                            )
                        }
                    }

                    Picker(
                        "Lift",
                        selection: Binding(
                            get: { day.liftKind },
                            set: { kind in model.edit { $0.setLiftKind(kind, on: day.weekday) } }
                        )
                    ) {
                        // The lift slot's own, smaller vocabulary — a lift is either
                        // prescribed or it is not. See
                        // `ScheduledSessionKind.liftPrescribable`.
                        ForEach(ScheduledSessionKind.liftPrescribable, id: \.self) { kind in
                            Text(PlanAuthoringFormatting.describe(kind)).tag(kind)
                        }
                    }
                    .pickerStyle(.menu)

                    if day.liftKind == .lift {
                        Menu {
                            ForEach(MuscleGroup.allCases, id: \.self) { group in
                                Toggle(
                                    PlanAuthoringFormatting.describe(group),
                                    isOn: Binding(
                                        get: { day.liftMuscleGroups.contains(group) },
                                        set: { _ in
                                            model.edit {
                                                $0.toggleLiftMuscleGroup(group, on: day.weekday)
                                            }
                                        }
                                    )
                                )
                            }
                        } label: {
                            row("Groups", PlanAuthoringFormatting.describe(day.liftSummary))
                        }

                        // Collapsed by default rather than two more permanent controls
                        // (MAX-148): seven weekdays × two slots is dense enough already,
                        // and duration and note are the two lift fields an athlete sets
                        // occasionally, not every time they open this screen. The label
                        // states the pair so the row is still scannable closed.
                        DisclosureGroup {
                            Stepper(
                                value: liftDurationMinutesBinding(
                                    for: day.weekday,
                                    seconds: day.liftDurationSeconds
                                ),
                                in: 0...240,
                                step: 5
                            ) {
                                row(
                                    "Duration",
                                    day.liftDurationSeconds.map { PlanAuthoringFormatting.duration($0) }
                                        ?? "None"
                                )
                            }

                            TextField(
                                "Note",
                                text: Binding(
                                    get: { day.liftNote ?? "" },
                                    set: { value in
                                        model.edit { $0.setLiftNote(value, on: day.weekday) }
                                    }
                                ),
                                axis: .vertical
                            )
                            .lineLimit(1...3)
                        } label: {
                            row(
                                "Duration & note",
                                PlanAuthoringFormatting.liftDetail(
                                    durationSeconds: day.liftDurationSeconds,
                                    note: day.liftNote
                                )
                            )
                        }
                    }
                }
                .padding(.vertical, Spacing.tight)
            }

            quietText(
                "A long run's distance comes from the arc below for the week it falls in; "
                    + "the distance set here is only used once the arc has run out."
            )
            quietText(
                "A lift's muscle groups are a statement of intent — nothing checks that they "
                    + "were the ones actually worked. Leaving them unstated is a real choice, "
                    + "distinct from resting."
            )
        }
    }

    /// Steps in whole minutes, stored in seconds. Zero reads as "no prescribed
    /// duration" rather than a duration of zero, matching `distanceBinding`'s own
    /// "None" convention for the run slot's distance.
    private func liftDurationMinutesBinding(for weekday: Weekday, seconds: Double?) -> Binding<Double> {
        Binding(
            get: { ((seconds ?? 0) / 60).rounded() },
            set: { minutes in
                model.edit {
                    $0.setLiftDurationSeconds(minutes <= 0 ? nil : minutes * 60, on: weekday)
                }
            }
        )
    }

    /// Steps in the athlete's own unit, stored in metres. Zero reads as "no prescribed
    /// distance" rather than as a distance of zero, which `ScheduledSession` rejects —
    /// a hard session described only by a note is a real thing the plan can say.
    private func distanceBinding(for weekday: Weekday, meters: Double?) -> Binding<Double> {
        Binding(
            get: { meters ?? 0 },
            set: { value in
                model.edit { $0.setDistanceMeters(value <= 0 ? nil : value, on: weekday) }
            }
        )
    }

    // MARK: - The long-run arc

    @ViewBuilder
    private func arcSection(_ editing: PlanAuthoringModel.Editing) -> some View {
        Section("Long-run arc") {
            ForEach(editing.draft.longRunArc) { week in
                Stepper(
                    value: Binding(
                        get: { week.distanceMeters },
                        set: { value in
                            model.edit { $0.setLongRunDistanceMeters(value, forWeek: week.index) }
                        }
                    ),
                    in: distanceRange(editing.distanceUnit, from: 1, to: 60),
                    step: editing.distanceUnit.meters(fromConverted: 0.5)
                ) {
                    row(
                        "Week \(week.index)",
                        PlanAuthoringFormatting.distance(
                            week.distanceMeters,
                            unit: editing.distanceUnit
                        )
                    )
                }
            }

            Button("Add a week") { model.edit { $0.appendLongRunWeek() } }

            Button("Remove the last week", role: .destructive) {
                model.edit { $0.removeLastLongRunWeek() }
            }
            .disabled(editing.draft.longRunArc.count <= 1)

            quietText(
                "Weeks are counted from the Monday on or before the date above. When the arc "
                    + "runs out, that is the moment to author the next version."
            )
        }
    }

    // MARK: - Goals

    @ViewBuilder
    private func goalsSection(_ editing: PlanAuthoringModel.Editing) -> some View {
        Section("Goals") {
            TextField(
                "One per line",
                text: Binding(
                    get: { editing.draft.goalStatements },
                    set: { value in model.edit { $0.goalStatements = value } }
                ),
                axis: .vertical
            )
            .lineLimit(2...5)

            Toggle(
                "Has a target date",
                isOn: Binding(
                    get: { editing.draft.goalTargetDay != nil },
                    set: { isOn in
                        model.edit { $0.goalTargetDay = isOn ? editing.effectiveFrom : nil }
                    }
                )
            )

            quietText("Narrative context for the scorer and for chat; nothing branches on it.")
        }
    }

    // MARK: - What it would govern

    @ViewBuilder
    private func previewSection(_ editing: PlanAuthoringModel.Editing) -> some View {
        Section("The first week this version governs") {
            if editing.governedDays.isEmpty {
                quietText("Not available until the values above are valid.")
            } else {
                ForEach(editing.governedDays) { planDay in
                    row(
                        PlanFormatting.dayLabel(planDay.date),
                        PlanAuthoringFormatting.describeBothSessions(
                            planDay,
                            unit: editing.distanceUnit
                        )
                    )
                }
            }
        }
    }

    // MARK: - Saving

    @ViewBuilder
    private func saveSection(_ editing: PlanAuthoringModel.Editing) -> some View {
        Section {
            Button("Save as plan \(editing.session.version.description)") {
                Task { await model.save() }
            }
            .disabled(!editing.canSave || model.isSaving)

            if let problem = editing.problem {
                Text(problem)
                    .font(.metricLabel)
                    .foregroundStyle(Color.scoreIneffective)
            }

            if let confirmation = editing.confirmation {
                quietText(confirmation)
            }
        } footer: {
            Text(
                "Saving never changes an existing version. Scores already recorded keep the "
                    + "version they were made under."
            )
        }
    }

    // MARK: - Small shared pieces

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(Color.textSecondary)
        }
    }

    /// A stepper's bounds, expressed in the athlete's unit and converted once.
    ///
    /// A local rather than an inline `a...b`: written inline the range operator would
    /// have to wrap across a line, where a leading `...` parses as the *prefix*
    /// operator and means something else entirely.
    private func distanceRange(
        _ unit: DistanceUnit,
        from lower: Double,
        to upper: Double
    ) -> ClosedRange<Double> {
        unit.meters(fromConverted: lower)...unit.meters(fromConverted: upper)
    }

    private func quietText(_ copy: String) -> some View {
        Text(copy)
            .font(.metricLabel)
            .foregroundStyle(Color.textSecondary)
    }
}

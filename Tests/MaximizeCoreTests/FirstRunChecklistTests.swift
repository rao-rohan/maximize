import Foundation
import XCTest
@testable import MaximizeCore

/// MAX-162: the four facts a fresh install can establish, the order they are asked in,
/// and the one thing offered at each stage (FIRST-RUN-SPEC §2, §5, §8).
///
/// The whole ticket is here because none of it can be observed anywhere else. First run
/// happens once per install, for one athlete, on a device no test reaches — so every
/// branch below is a branch a person would otherwise only ever see by deleting the app
/// and reinstalling it. There are forty-eight combinations of the four facts and this
/// file resolves all of them.
///
/// The R10 rule — that nothing here may claim Health access was granted or refused — is
/// asserted in `FailureCopyTests`, over `FailureCopy` and `FirstRunCopy` together, rather
/// than a second time here. Two tests asserting one rule drift.
final class FirstRunChecklistTests: XCTestCase {

    // MARK: - The fact space

    /// Every combination of the four facts: four Health states × plan or no plan × three
    /// key presences × a workout or none.
    private var everyCombination: [FirstRunFacts] {
        var facts: [FirstRunFacts] = []
        for health in HealthAccessState.allCases {
            for hasPlan in [false, true] {
                for key in StoredAPIKeyPresence.allCases {
                    for hasWorkout in [false, true] {
                        facts.append(
                            FirstRunFacts(
                                healthAccess: health,
                                hasAuthoredPlan: hasPlan,
                                apiKeyPresence: key,
                                hasCapturedWorkout: hasWorkout
                            )
                        )
                    }
                }
            }
        }
        return facts
    }

    private func checklist(
        health: HealthAccessState = .requestAnswered,
        plan: Bool = true,
        key: StoredAPIKeyPresence = .stored,
        workout: Bool = true
    ) -> FirstRunChecklist {
        FirstRunChecklist(
            facts: FirstRunFacts(
                healthAccess: health,
                hasAuthoredPlan: plan,
                apiKeyPresence: key,
                hasCapturedWorkout: workout
            )
        )
    }

    private func label(_ facts: FirstRunFacts) -> String {
        "health: \(facts.healthAccess), plan: \(facts.hasAuthoredPlan), "
            + "key: \(facts.apiKeyPresence), workout: \(facts.hasCapturedWorkout)"
    }

    func testTheFactSpaceIsTheFourFactsAndNothingElse() {
        XCTAssertEqual(HealthAccessState.allCases.count, 4)
        XCTAssertEqual(StoredAPIKeyPresence.allCases.count, 3)
        XCTAssertEqual(everyCombination.count, 48)
        XCTAssertEqual(Set(everyCombination).count, 48)
    }

    // MARK: - Exactly one next action, always

    /// The central invariant, over all forty-eight. The card's button and the checklist's
    /// next step are two derivations — one from the facts directly, one from the ordered
    /// remaining steps — and they must never disagree, or the card would offer an action
    /// the checklist does not think is next.
    func testTheCardsActionIsAlwaysTheNextStep() {
        for facts in everyCombination {
            let checklist = FirstRunChecklist(facts: facts)
            XCTAssertEqual(
                checklist.card?.step,
                checklist.nextStep,
                "the card and the step list disagree for \(label(facts))"
            )
        }
    }

    /// One heading, one sentence, one button (§5.3). Never two buttons, even when two
    /// steps are outstanding.
    func testAtMostOneActionIsOfferedNoMatterHowManyStepsRemain() {
        for facts in everyCombination {
            let checklist = FirstRunChecklist(facts: facts)
            guard let state = checklist.card else {
                XCTAssertTrue(
                    checklist.remainingSteps.isEmpty,
                    "no card, but steps remain for \(label(facts))"
                )
                continue
            }
            let copy = FirstRunCopy.card(state)
            XCTAssertEqual(copy.action, checklist.nextStep, "for \(label(facts))")
            XCTAssertEqual(
                copy.actionLabel == nil,
                copy.action == nil,
                "the label and the action disagree for \(label(facts))"
            )
        }
    }

    /// A fresh install: all three outstanding, and the Health question is the only one put.
    func testADayOneInstallIsAskedForHealthAccessAndNothingElse() {
        let checklist = FirstRunChecklist(facts: .freshInstall)

        XCTAssertEqual(checklist.remainingSteps, [.requestHealthAccess, .authorAPlan, .addAnAPIKey])
        XCTAssertEqual(checklist.nextStep, .requestHealthAccess)
        XCTAssertEqual(checklist.card, .healthAccessNotRequested)
        XCTAssertEqual(FirstRunCopy.card(.healthAccessNotRequested).actionLabel, "Request Health access")
    }

    // MARK: - The order: Health → plan → key

    /// `allCases` is the ask order, and the ask order is what a delay costs — ascending.
    /// A step added later has to answer that question to get a position.
    func testTheAskOrderIsTheRecoverabilityOrder() {
        XCTAssertEqual(FirstRunStep.allCases, [.requestHealthAccess, .authorAPlan, .addAnAPIKey])
        XCTAssertEqual(
            FirstRunStep.allCases.map(\.recovery),
            FirstRunStep.allCases.map(\.recovery).sorted()
        )
        XCTAssertEqual(Set(FirstRunStep.allCases.map(\.recovery)).count, FirstRunStep.allCases.count)
        XCTAssertEqual(FirstRunStep.requestHealthAccess.recovery, .nothingArrivesUntilItIsAnswered)
        XCTAssertEqual(FirstRunStep.addAnAPIKey.recovery, .fullyRecoveredWheneverItIsDone)
    }

    /// Whatever else is outstanding, an unanswered Health question is what is asked.
    /// Health fails silently, and it is the only one of the three the app can never check.
    func testHealthIsAskedBeforeAnythingElse() {
        let stillAQuestion: Set<HealthAccessState> = [.notRequestedYet, .requestFailed]
        for facts in everyCombination where stillAQuestion.contains(facts.healthAccess) {
            let checklist = FirstRunChecklist(facts: facts)
            XCTAssertEqual(checklist.nextStep, .requestHealthAccess, "for \(label(facts))")
            XCTAssertEqual(checklist.remainingSteps.first, .requestHealthAccess, "for \(label(facts))")
        }
    }

    /// The plan is asked once the sheet has been answered, and before the key — a missing
    /// plan strands everything before the date eventually chosen, a missing key strands
    /// nothing.
    func testThePlanIsAskedAfterHealthAndBeforeTheKey() {
        let checklist = self.checklist(health: .requestAnswered, plan: false, key: .notStored, workout: false)

        XCTAssertEqual(checklist.remainingSteps, [.authorAPlan, .addAnAPIKey])
        XCTAssertEqual(checklist.nextStep, .authorAPlan)
        XCTAssertEqual(checklist.card, .noPlanAuthored)
    }

    /// The one step that costs money is the last one put, and it is never put while
    /// something above it is outstanding.
    func testTheKeyIsNeverAskedForBeforeTheStepsAboveIt() {
        for facts in everyCombination {
            let checklist = FirstRunChecklist(facts: facts)
            guard checklist.nextStep == .addAnAPIKey else { continue }
            XCTAssertEqual(checklist.healthIsSettled, true, "for \(label(facts))")
            XCTAssertTrue(facts.hasAuthoredPlan, "for \(label(facts))")
            XCTAssertEqual(checklist.card, .noAPIKeyStored, "for \(label(facts))")
            XCTAssertEqual(checklist.remainingSteps, [.addAnAPIKey], "for \(label(facts))")
        }
    }

    /// Remaining steps are always in ask order — never re-sorted by a later edit into
    /// "whatever the caller passed".
    func testRemainingStepsAreAlwaysInAskOrder() {
        for facts in everyCombination {
            let remaining = FirstRunChecklist(facts: facts).remainingSteps
            let inOrder = FirstRunStep.allCases.filter { remaining.contains($0) }
            XCTAssertEqual(remaining, inOrder, "for \(label(facts))")
            XCTAssertEqual(Set(remaining).count, remaining.count, "a step repeats for \(label(facts))")
        }
    }

    // MARK: - No step is ever completed, only absent

    /// R10's structural half, asserted from this side: the card's vocabulary is six
    /// states and none of them is a result. A seventh case meaning "Health is on" would
    /// fail here before it could ever reach a view.
    func testTheCardVocabularyHasNoCompletedState() {
        XCTAssertEqual(
            Set(FirstRunCardState.allCases),
            [
                .healthAccessNotRequested,
                .healthRequestDidNotComplete,
                .healthDataUnavailable,
                .noPlanAuthored,
                .noAPIKeyStored,
                .awaitingFirstWorkout,
            ]
        )
    }

    /// A step that has been taken leaves the list. It does not stay in it annotated.
    func testATakenStepLeavesTheChecklistRatherThanBeingMarkedDone() {
        let beforePlan = checklist(health: .notRequestedYet, plan: false, key: .notStored, workout: false)
        let afterPlan = checklist(health: .notRequestedYet, plan: true, key: .notStored, workout: false)

        XCTAssertTrue(beforePlan.remainingSteps.contains(.authorAPlan))
        XCTAssertFalse(afterPlan.remainingSteps.contains(.authorAPlan))
        XCTAssertEqual(afterPlan.remainingSteps, [.requestHealthAccess, .addAnAPIKey])
    }

    /// An answered sheet removes the Health step and produces no state of its own. There
    /// is nowhere for "granted" to be stored, so nowhere for it to be drawn from.
    func testAnAnsweredSheetRemovesTheHealthStepWithoutRecordingAResult() {
        let checklist = self.checklist(health: .requestAnswered, plan: false, key: .notStored, workout: false)

        XCTAssertFalse(checklist.remainingSteps.contains(.requestHealthAccess))
        XCTAssertEqual(checklist.card, .noPlanAuthored)
    }

    // MARK: - The Health states that are not a question

    /// A request that did not complete is not a request that was never made, and is not
    /// worded as one — but both offer the same button, because asking again is the fix
    /// for both.
    func testAFailedRequestIsNotWordedAsAnUnaskedOne() {
        let unasked = checklist(health: .notRequestedYet, plan: true, key: .stored, workout: true)
        let failed = checklist(health: .requestFailed, plan: true, key: .stored, workout: true)

        XCTAssertEqual(unasked.card, .healthAccessNotRequested)
        XCTAssertEqual(failed.card, .healthRequestDidNotComplete)
        XCTAssertNotEqual(
            FirstRunCopy.card(.healthAccessNotRequested).body,
            FirstRunCopy.card(.healthRequestDidNotComplete).body
        )
        XCTAssertEqual(unasked.nextStep, .requestHealthAccess)
        XCTAssertEqual(failed.nextStep, .requestHealthAccess)
    }

    /// A device with no Health store is told so and offered nothing — no button that can
    /// only fail, and no further steps, because a plan and a key are steps toward data
    /// that can never arrive.
    func testADeviceWithoutHealthDataIsToldSoAndAskedForNothing() {
        for facts in everyCombination where facts.healthAccess == .healthDataUnavailable {
            let checklist = FirstRunChecklist(facts: facts)
            XCTAssertEqual(checklist.card, .healthDataUnavailable, "for \(label(facts))")
            XCTAssertEqual(checklist.remainingSteps, [], "for \(label(facts))")
            XCTAssertNil(checklist.nextStep, "for \(label(facts))")
            XCTAssertNil(FirstRunCopy.card(.healthDataUnavailable).action)
        }
    }

    // MARK: - A Keychain that could not be read is not an absent key

    /// MAX-154's finding, kept from coming back on a new surface: a read that failed is
    /// not evidence that nothing is stored, so it never becomes "No Anthropic API key" and
    /// never becomes a step. Settings says the honest thing where the athlete can act on
    /// it.
    func testAnUnreadableKeyStoreIsNeverReportedAsAMissingKey() {
        for facts in everyCombination where facts.apiKeyPresence == .unknown {
            let checklist = FirstRunChecklist(facts: facts)
            XCTAssertFalse(checklist.remainingSteps.contains(.addAnAPIKey), "for \(label(facts))")
            XCTAssertNotEqual(checklist.card, .noAPIKeyStored, "for \(label(facts))")
        }

        // And the state it does not reach is the one a stored-nothing device gets.
        XCTAssertEqual(
            checklist(health: .requestAnswered, plan: true, key: .notStored, workout: true).card,
            .noAPIKeyStored
        )
    }

    // MARK: - Set up, and nothing recorded yet (§8)

    /// The window between the last step and the first workout. It lasts hours, and
    /// legitimately days, and it is neither an error nor an absence of setup — so it is
    /// its own state rather than an empty list.
    func testTheSetUpButNothingRecordedWindowIsItsOwnState() {
        let waiting = checklist(health: .requestAnswered, plan: true, key: .stored, workout: false)

        XCTAssertEqual(waiting.card, .awaitingFirstWorkout)
        XCTAssertEqual(waiting.remainingSteps, [])
        XCTAssertNil(waiting.nextStep)

        let copy = FirstRunCopy.card(.awaitingFirstWorkout)
        XCTAssertNil(copy.action, "the waiting state has nothing to press")
        XCTAssertNotNil(copy.detail, "the waiting state's second paragraph is what keeps it honest")
    }

    /// And it ends the moment a workout is stored. The card is gone, and nothing in this
    /// type brings it back.
    func testTheCardIsGoneOnceSomethingIsRecorded() {
        let settled = checklist(health: .requestAnswered, plan: true, key: .stored, workout: true)

        XCTAssertNil(settled.card)
        XCTAssertEqual(settled.remainingSteps, [])
        XCTAssertNil(settled.nextStep)
    }

    /// The only combination with no card at all is the fully settled one. Every other
    /// combination has something to say.
    func testNoCardIsShownOnlyWhenEverythingIsBehindThem() {
        for facts in everyCombination {
            let checklist = FirstRunChecklist(facts: facts)
            guard checklist.card == nil else { continue }
            XCTAssertEqual(facts.healthAccess, .requestAnswered, "for \(label(facts))")
            XCTAssertTrue(facts.hasAuthoredPlan, "for \(label(facts))")
            XCTAssertNotEqual(facts.apiKeyPresence, .notStored, "for \(label(facts))")
            XCTAssertTrue(facts.hasCapturedWorkout, "for \(label(facts))")
        }
    }

    // MARK: - The copy the two views render

    /// Every state answers with its own words, and none of them is a placeholder.
    func testEveryCardStateHasItsOwnHeadingAndSentence() {
        var headings: Set<String> = []
        var bodies: Set<String> = []
        for state in FirstRunCardState.allCases {
            let copy = FirstRunCopy.card(state)
            XCTAssertFalse(
                copy.heading.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "\(state) has no heading"
            )
            XCTAssertTrue(copy.body.hasSuffix("."), "\(state)'s sentence does not end in a full stop")
            XCTAssertTrue(
                copy.heading.first.map { $0.isUppercase } ?? false,
                "\(state)'s heading does not start with a capital"
            )
            XCTAssertEqual(copy.action, state.step, "\(state)'s copy offers a different action")
            headings.insert(copy.heading)
            bodies.insert(copy.body)
        }
        XCTAssertEqual(headings.count, FirstRunCardState.allCases.count, "two states share a heading")
        XCTAssertEqual(bodies.count, FirstRunCardState.allCases.count, "two states share a sentence")
    }

    /// Each button names where it goes, and no two go to the same place.
    func testEveryStepHasItsOwnActionLabel() {
        let labels = FirstRunStep.allCases.map(FirstRunCopy.actionLabel(for:))
        XCTAssertEqual(Set(labels).count, labels.count)
        XCTAssertEqual(labels, ["Request Health access", "Author a plan", "Add a key in Settings"])
    }

    /// §8's second paragraph and `FailureCopy.noWorkoutsRecorded` are two sentences about
    /// one fact, written for two moments. The collapse was tried and rejected on how it
    /// reads; what must not drift is the recovery path, so it is asserted rather than
    /// trusted.
    func testTheWaitingCopyAndTheEmptyListNameTheSameRecoveryPath() {
        let path = "Settings › Health › Data Access & Devices"
        guard let detail = FirstRunCopy.card(.awaitingFirstWorkout).detail else {
            return XCTFail("the waiting state lost its second paragraph")
        }
        XCTAssertTrue(detail.contains(path))
        XCTAssertTrue(FailureCopy.noWorkoutsRecorded.contains(path))
        XCTAssertNotEqual(detail, FailureCopy.noWorkoutsRecorded)
    }

    /// The one numeral in the whole module is the ingester's backfill window, and it is a
    /// constant of the app rather than a fact about the athlete. If the policy changes,
    /// this sentence is wrong, so the two are asserted together.
    func testTheWaitingCopysBackfillMatchesTheIngestersPolicy() {
        XCTAssertEqual(AnchoredIngestionPolicy.standard.firstRunBackfill, 90 * 24 * 60 * 60)
        XCTAssertTrue(FirstRunCopy.card(.awaitingFirstWorkout).body.contains("90 days"))
    }

    /// Nothing else carries a digit. Every string in this module is a fixed literal with
    /// no parameter to interpolate, so a workout, a date or an identifier has no route
    /// into a rendered sentence — a digit anywhere else would mean one had grown a route
    /// (CLAUDE.md, "health data is PII").
    func testNoSentenceCarriesADigitExceptTheBackfillWindow() {
        for state in FirstRunCardState.allCases where state != .awaitingFirstWorkout {
            let copy = FirstRunCopy.card(state)
            let texts: [String?] = [copy.heading, copy.body, copy.detail, copy.actionLabel]
            for text in texts.compactMap({ $0 }) {
                XCTAssertFalse(
                    text.contains(where: { $0.isNumber }),
                    "\(state) carries a digit: \"\(text)\""
                )
            }
        }
        for text in [
            FirstRunCopy.cover.title,
            FirstRunCopy.cover.health,
            FirstRunCopy.cover.privacy,
            FirstRunCopy.cover.continueLabel,
        ] {
            XCTAssertFalse(
                text.contains(where: { $0.isNumber }),
                "the cover carries a digit: \"\(text)\""
            )
        }
        XCTAssertFalse(
            FirstRunCopy.card(.awaitingFirstWorkout).heading.contains(where: { $0.isNumber })
        )
    }

    // MARK: - The cover (§4.2), which MAX-163 renders

    /// Three elements and a button, and each one is load-bearing: the title states the
    /// product rather than greeting anyone, the middle paragraph is the Settings section's
    /// own sentence about what is read, and the last is the CloudKit answer plus the one
    /// thing that does leave the device.
    func testTheCoverStatesTheProductWhatIsReadAndWhatLeavesTheDevice() {
        let cover = FirstRunCopy.cover

        XCTAssertEqual(cover.title, "Maximize scores your runs against your plan.")
        XCTAssertTrue(cover.health.contains("iOS will ask which health data Maximize may read"))
        XCTAssertTrue(
            cover.health.contains(
                "completed workouts, heart rate, distance, energy, steps and route"
            ),
            "the cover no longer uses the Settings section's sentence about what is read"
        )
        XCTAssertTrue(cover.health.contains("It never writes to Health."))
        XCTAssertTrue(cover.privacy.contains("sent to Claude when you ask a question"))
        XCTAssertTrue(cover.privacy.contains("deleting Maximize deletes its history"))
        XCTAssertEqual(cover.paragraphs, [cover.health, cover.privacy])
    }

    /// "Allow" is the system sheet's own word and pre-empting it is a small lie about
    /// which button does what; "Connect" implies a verifiable connected state, which is
    /// the claim R10 forbids outright.
    func testTheCoversButtonIsNeitherAllowNorConnect() {
        XCTAssertEqual(FirstRunCopy.cover.continueLabel, "Continue")
        let lowered = FirstRunCopy.cover.continueLabel.lowercased()
        XCTAssertFalse(lowered.contains("allow"))
        XCTAssertFalse(lowered.contains("connect"))
    }
}

/// Whether the Health question has stopped being a question — used only by the ordering
/// test above, and kept out of the shipped type because no caller has needed it and a
/// property called anything like "health is settled" is one careless rename away from
/// reading as "Health is on".
private extension FirstRunChecklist {
    var healthIsSettled: Bool { !remainingSteps.contains(.requestHealthAccess) }
}

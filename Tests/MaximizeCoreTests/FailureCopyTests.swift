import Foundation
import XCTest
@testable import MaximizeCore

/// MAX-154: every failure outside chat that becomes a sentence, and the rules that
/// sentence keeps.
///
/// These tests exist because none of the call sites can be executed. `App/` is compiled
/// by CI and never run (tracker R2, R13), so a `catch` block's wording has never been
/// checked by anything except a person reading a diff. Pulling the decision into
/// `MaximizeCore` is what makes it checkable at all; this file is the check.
///
/// The properties asserted are deliberately the ones an audit found violated in the code
/// this ticket replaced: two surfaces sharing one sentence, a failure worded as an
/// absence, a state that claimed knowledge it did not have, and a diagnostic reaching a
/// screen.
final class FailureCopyTests: XCTestCase {

    // MARK: - Every case, enumerated

    /// One sentence, paired with a label naming where it came from — so a failing
    /// whole-set assertion says which case broke the rule rather than only quoting the
    /// string it produced.
    private struct Entry {
        let label: String
        let text: String
    }

    /// Every string `FailureCopy` can produce, in one place, so the whole-set properties
    /// below cannot silently miss a mapping added later.
    private var allCopy: [Entry] {
        var entries: [Entry] = []
        for surface in LoadFailureSurface.allCases {
            entries.append(
                Entry(label: "couldNotLoad(.\(surface.rawValue))", text: FailureCopy.couldNotLoad(surface))
            )
        }
        for presence in StoredAPIKeyPresence.allCases {
            entries.append(
                Entry(label: "storedKeyPresence(\(presence))", text: FailureCopy.storedKeyPresence(presence))
            )
        }
        for message in APIKeyStatusMessage.allCases {
            entries.append(
                Entry(label: "apiKeyStatus(\(message))", text: FailureCopy.apiKeyStatus(message))
            )
        }
        for state in HealthAccessState.allCases {
            entries.append(
                Entry(label: "healthAccess(\(state))", text: FailureCopy.healthAccess(state))
            )
        }
        entries.append(Entry(label: "noWorkoutsRecorded", text: FailureCopy.noWorkoutsRecorded))
        entries.append(Entry(label: "todaysDateUnresolved", text: FailureCopy.todaysDateUnresolved))
        entries.append(
            Entry(
                label: "dashboardUnavailableWithoutToday",
                text: FailureCopy.dashboardUnavailableWithoutToday
            )
        )
        entries.append(Entry(label: "planCouldNotBePrepared", text: FailureCopy.planCouldNotBePrepared))
        entries.append(
            Entry(label: "planVersionCouldNotBeSaved", text: FailureCopy.planVersionCouldNotBeSaved)
        )
        return entries
    }

    /// Every string `FirstRunCopy` can produce (MAX-162).
    ///
    /// Deliberately **not** folded into `allCopy`: the whole-set properties above are
    /// about failure sentences, and a first-run card is headings and button titles as well
    /// as sentences — "No plan yet" and "Continue" are correct copy and would fail
    /// `testEverySentenceIsRealCopy`'s full stop. What the two sets do share is the one
    /// rule neither may break, and `testNoHealthCopyClaimsAccessWasGrantedOrRefused` runs
    /// over both.
    private var allFirstRunCopy: [Entry] {
        var entries: [Entry] = []
        for state in FirstRunCardState.allCases {
            let copy = FirstRunCopy.card(state)
            entries.append(Entry(label: "card(.\(state.rawValue)).heading", text: copy.heading))
            entries.append(Entry(label: "card(.\(state.rawValue)).body", text: copy.body))
            if let detail = copy.detail {
                entries.append(Entry(label: "card(.\(state.rawValue)).detail", text: detail))
            }
            if let actionLabel = copy.actionLabel {
                entries.append(Entry(label: "card(.\(state.rawValue)).action", text: actionLabel))
            }
        }
        let cover = FirstRunCopy.cover
        entries.append(Entry(label: "cover.title", text: cover.title))
        entries.append(Entry(label: "cover.health", text: cover.health))
        entries.append(Entry(label: "cover.privacy", text: cover.privacy))
        entries.append(Entry(label: "cover.continueLabel", text: cover.continueLabel))
        return entries
    }

    /// The enums are the inventory. If a case is added and this count is not updated,
    /// the author has been made to look at whether the new case needs its own sentence —
    /// which is the whole point of enumerating them.
    func testTheInventoryCoversEveryDeclaredCase() {
        XCTAssertEqual(LoadFailureSurface.allCases.count, 9)
        XCTAssertEqual(StoredAPIKeyPresence.allCases.count, 3)
        XCTAssertEqual(APIKeyStatusMessage.allCases.count, 6)
        XCTAssertEqual(HealthAccessState.allCases.count, 4)
        XCTAssertEqual(allCopy.count, 27)

        // MAX-162's inventory, counted for the same reason: six card states, each with a
        // heading and a sentence, one second paragraph, four buttons, and the cover's
        // four strings.
        XCTAssertEqual(FirstRunCardState.allCases.count, 6)
        XCTAssertEqual(FirstRunStep.allCases.count, 3)
        XCTAssertEqual(allFirstRunCopy.count, 21)
    }

    // MARK: - No case falls through to a generic fallback

    /// **The central assertion of this ticket.** A `default:` arm, or a copy-paste that
    /// gave two surfaces the same words, is invisible at the call site and shows up as a
    /// person being told something that is not about what they were looking at. Every
    /// case must answer with its own sentence.
    func testNoTwoCasesShareASentence() {
        var seen: [String: String] = [:]
        for entry in allCopy {
            if let firstLabel = seen[entry.text] {
                XCTFail(
                    "\(entry.label) produces the same sentence as \(firstLabel): \"\(entry.text)\""
                )
            }
            seen[entry.text] = entry.label
        }
        XCTAssertEqual(seen.count, allCopy.count)
    }

    /// Nothing answers with a placeholder, an empty string, or whitespace.
    func testEverySentenceIsRealCopy() {
        for entry in allCopy {
            XCTAssertFalse(
                entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "\(entry.label) is blank"
            )
            XCTAssertTrue(entry.text.hasSuffix("."), "\(entry.label) does not end in a full stop")
            XCTAssertEqual(
                entry.text,
                entry.text.trimmingCharacters(in: .whitespacesAndNewlines),
                "\(entry.label) has stray leading or trailing whitespace"
            )
            XCTAssertTrue(
                entry.text.first.map { $0.isUppercase } ?? false,
                "\(entry.label) does not start with a capital"
            )
        }
    }

    // MARK: - A failure reaches the person as a description, not as a diagnostic

    /// The second class of defect the audit looked for: a failure that arrives as noise.
    /// A person is owed a description of what happened to them; a type name, a framework
    /// name, a status code or an enum case is not one.
    ///
    /// `ScoringModelError.description` and its siblings deliberately do the opposite —
    /// they are written for a developer reading a debugger — and none of them reaches a
    /// screen. This test is what keeps that true from this side.
    func testNoSentenceNamesATypeAFrameworkOrAnError() {
        let banned = [
            "error", "nil", "null", "exception", "failed", "failure",
            "keychain", "healthkit", "swiftdata", "coredata", "osstatus", "hkerror",
            "status code", "http", "json", "uuid", "optional", "unwrap",
        ]
        for entry in allCopy {
            let lowered = entry.text.lowercased()
            for term in banned {
                XCTAssertFalse(
                    lowered.contains(term),
                    "\(entry.label) says \"\(term)\": \"\(entry.text)\""
                )
            }
        }
    }

    /// No digit appears in any sentence, anywhere.
    ///
    /// Not a style rule — a privacy one, and the cheapest available proof of it. Every
    /// value this type can produce is a fixed literal with no parameter to interpolate,
    /// so a workout identifier, a date, a measurement or a status code has no route into
    /// a rendered sentence. A digit appearing here would mean one of those had grown a
    /// route, which is the finding CLAUDE.md's "health data is PII" rule is about.
    func testNoSentenceCarriesADigit() {
        for entry in allCopy {
            XCTAssertFalse(
                entry.text.contains(where: { $0.isNumber }),
                "\(entry.label) carries a digit, so something is being interpolated: \"\(entry.text)\""
            )
        }
    }

    // MARK: - A failure is not an absence

    /// CLAUDE.md: absence is a designed state. It is not satisfied by wording a failure
    /// as one. "No workouts recorded yet" and "your workouts could not be read" describe
    /// different worlds and must not converge.
    func testTheEmptyListAndTheFailedListAreDifferentSentences() {
        let failure = FailureCopy.couldNotLoad(.workoutList)
        let absence = FailureCopy.noWorkoutsRecorded

        XCTAssertNotEqual(failure, absence)
        XCTAssertFalse(failure.contains(absence))
        XCTAssertFalse(absence.contains(failure))

        // The failure copy says explicitly that it is not the absence, because an empty
        // screen is the thing a person will otherwise read it as.
        XCTAssertTrue(failure.lowercased().contains("not a sign that none were recorded"))
    }

    // MARK: - R10: the app does not claim what it cannot know

    /// Tracker R10: `HKHealthStore.authorizationStatus(for:)` reports share status only.
    /// The app cannot establish that Health *read* access was granted or refused, so no
    /// state may be worded as though it had.
    ///
    /// **Extended by MAX-162 over `FirstRunCopy` rather than copied into a second test**
    /// (FIRST-RUN-SPEC §9.3). First run is where this rule is under the most pressure —
    /// the athlete has just answered a permission sheet and a setup card is the natural
    /// place to tick it off — and it is also the least-exercised surface in the app, so a
    /// wrong word there would survive a long time. Two tests asserting one rule drift, and
    /// the one that drifts is the one nobody remembers to update; this is the one.
    func testNoHealthCopyClaimsAccessWasGrantedOrRefused() {
        let claims = [
            "connected", "granted access", "access granted", "denied", "refused",
            "not connected", "you have granted", "permission granted",
            // MAX-162: each of these is a phrase a well-meaning first-run edit reaches
            // for. The last is the sharpest, because FIRST-RUN-SPEC's own §5.2 draft
            // reached for it — "Runs are being captured" asserts that capture is
            // happening, which is exactly what iOS never tells this app. The shipped
            // wording says workouts are stored *as they arrive*, which is true whatever
            // iOS decided.
            "you're all set", "you are all set", "health is on", "reading your workouts",
            "being captured",
        ]

        var entries = HealthAccessState.allCases.map {
            Entry(label: "healthAccess(\($0))", text: FailureCopy.healthAccess($0))
        }
        entries += allFirstRunCopy

        for entry in entries {
            let lowered = entry.text.lowercased()
            for claim in claims {
                XCTAssertFalse(
                    lowered.contains(claim),
                    "\(entry.label) claims read access it cannot verify: \"\(claim)\""
                )
            }
        }
    }

    /// The one place the app *does* talk about read access says only that it cannot be
    /// known — the strongest true statement available.
    func testTheAnsweredRequestSaysOnlyThatTheSheetWasAnswered() {
        let text = FailureCopy.healthAccess(.requestAnswered)
        XCTAssertTrue(text.contains("does not report whether read access was granted"))
    }

    /// The empty-list copy is the other surface R10 reaches, because an empty list and a
    /// refused read are indistinguishable from inside the app. It names the second
    /// possibility without asserting it, and — the R10 rule proper — never says Health is
    /// or is not connected.
    func testTheEmptyListCopyNamesTheUnknowableWithoutAssertingIt() {
        let text = FailureCopy.noWorkoutsRecorded
        XCTAssertTrue(text.contains("iOS never tells an app whether Health access was granted"))
        XCTAssertFalse(text.lowercased().contains("connected"))
        XCTAssertFalse(text.lowercased().contains("denied"))
    }

    // MARK: - The key store admits when it does not know

    /// Before this ticket a failed Keychain read set the screen's flag to `false`, so a
    /// device that could not be asked stated flatly that no key was stored. Three states,
    /// three sentences, and the third one says it does not know.
    func testAnUncheckableKeyStoreIsNotReportedAsAnAbsentKey() {
        XCTAssertNotEqual(
            FailureCopy.storedKeyPresence(.unknown),
            FailureCopy.storedKeyPresence(.notStored)
        )
        XCTAssertTrue(FailureCopy.storedKeyPresence(.unknown).lowercased().contains("could not be checked"))
        XCTAssertEqual(FailureCopy.storedKeyPresence(.notStored), "No key is stored.")
        XCTAssertEqual(FailureCopy.storedKeyPresence(.stored), "A key is stored.")
    }

    /// A key may well be on the device when the read failed, so the control that removes
    /// one stays available. Withholding it is the wrong side to err on.
    func testClearingIsOfferedWheneverAKeyMightBeStored() {
        XCTAssertTrue(StoredAPIKeyPresence.stored.permitsClearing)
        XCTAssertTrue(StoredAPIKeyPresence.unknown.permitsClearing)
        XCTAssertFalse(StoredAPIKeyPresence.notStored.permitsClearing)
    }

    /// Nothing about the key itself — length, prefix, shape — is describable through any
    /// of this vocabulary. Presence is the whole of it.
    func testNoKeyCopyDescribesTheKeyItself() {
        let banned = ["characters", "starts with", "begins with", "sk-", "length", "prefix", "ends with"]
        let texts = StoredAPIKeyPresence.allCases.map { FailureCopy.storedKeyPresence($0) }
            + APIKeyStatusMessage.allCases.map { FailureCopy.apiKeyStatus($0) }
        for text in texts {
            let lowered = text.lowercased()
            for term in banned {
                XCTAssertFalse(lowered.contains(term), "\"\(text)\" describes the key: \"\(term)\"")
            }
        }
    }

    /// The save failure clears the field, so the copy says the field was cleared. A text
    /// field that empties itself with no explanation reads as the app losing the input.
    func testTheSaveFailureExplainsWhyTheFieldEmptied() {
        XCTAssertTrue(FailureCopy.apiKeyStatus(.couldNotSave).contains("The field has been cleared"))
    }

    /// A delete that failed leaves the key where it was, and says so, because "Key
    /// cleared." would be a claim the app has just failed to make true.
    func testTheClearFailureDoesNotClaimTheKeyIsGone() {
        XCTAssertNotEqual(
            FailureCopy.apiKeyStatus(.couldNotClear),
            FailureCopy.apiKeyStatus(.cleared)
        )
        XCTAssertTrue(FailureCopy.apiKeyStatus(.couldNotClear).contains("may still be stored"))
    }

    // MARK: - The dashboard's blank

    /// The audit's clearest instance of "a failure that reaches the person as nothing":
    /// with today's date unresolvable, `DashboardView` rendered the selector's one-line
    /// message and then nothing at all where the calendar, drift section and tiles go.
    /// The body now has copy of its own, and it is not the selector's sentence repeated.
    func testTheDashboardBodyHasItsOwnSentenceWhenTodayIsUnresolvable() {
        XCTAssertNotEqual(
            FailureCopy.dashboardUnavailableWithoutToday,
            FailureCopy.todaysDateUnresolved
        )
        XCTAssertTrue(FailureCopy.dashboardUnavailableWithoutToday.contains("measure against today"))
    }

    // MARK: - One voice

    /// The audit found four verbs for one event across five screens: "Could not load
    /// workouts.", "Couldn't load the plan.", "Couldn't load the calendar.", "Couldn't
    /// load this plan version.", "Couldn't load the runs in this interval." One voice
    /// means one of them, everywhere — and the one chosen is the one
    /// `ChatConversationCopy.failedToLoad` already used before this ticket, so the app
    /// has a single failure verb rather than a chat one and a not-chat one.
    func testEveryLoadFailureUsesTheVerbChatAlreadyUsed() {
        XCTAssertTrue(ChatConversationCopy.failedToLoad(for: .workout).contains("could not be loaded"))
        for surface in LoadFailureSurface.allCases {
            XCTAssertTrue(
                FailureCopy.couldNotLoad(surface).contains("could not be loaded"),
                "couldNotLoad(.\(surface.rawValue)) does not use the app's failure verb: "
                    + "\"\(FailureCopy.couldNotLoad(surface))\""
            )
        }
    }

    /// No load-failure sentence tells a person to do something the screen gives them no
    /// way to do. None of these surfaces has a retry control, so none of them says
    /// "try again" — the two that do (`planVersionCouldNotBeSaved`, and the Health
    /// request) sit behind buttons a person can press again.
    func testNoLoadFailureAsksForAnActionTheScreenCannotOffer() {
        for surface in LoadFailureSurface.allCases {
            XCTAssertFalse(
                FailureCopy.couldNotLoad(surface).lowercased().contains("try again"),
                "couldNotLoad(.\(surface.rawValue)) asks for a retry the screen has no control for"
            )
        }
        XCTAssertTrue(FailureCopy.planVersionCouldNotBeSaved.contains("Try again."))
        XCTAssertTrue(FailureCopy.healthAccess(.requestFailed).contains("Try it again."))
    }
}

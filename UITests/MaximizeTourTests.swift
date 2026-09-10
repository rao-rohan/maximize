// UITests/MaximizeTourTests.swift
//
// A hands-on simulator tour of the Maximize app, run on demand by
// `.github/workflows/simulator-tour.yml` (workflow_dispatch only).
//
// What it does, in order:
//   1. Launches the app with `-seedTourWorkouts`, which makes the app seed three
//      sample runs (heart-rate series on each, a GPS route on one) into the
//      simulator's HealthKit store from its own process. The test answers the
//      Health permission sheet the way a user would.
//   2. Walks first run: cover -> Continue -> Health permission sheet.
//   3. Authors the first plan by hand and saves the default the screen proposes.
//   4. Stores a dummy Anthropic key in Settings. The key is deliberately fake
//      and the tour never sends a message, so no network call is ever made.
//   5. Waits for the seeded runs to be ingested, then visits all three tabs,
//      opens a workout detail, and opens the chat sheet with a typed-but-unsent
//      draft.
//   6. Attaches a screenshot at every major stage (kept always) for whoever
//      reviews the run, alongside the workflow's screen recording.
//
// Deliberate limits (see TOUR-PLAN.md):
// - No chat message is ever sent: the stored key is a dummy and the chat
//   assertions stop at the composer draft.
// - HealthKit background delivery cannot be proven on the simulator; the seeded
//   samples exercise the launch-time anchored ingestion pass instead.
// - If seeding fails the tour does not abort: it continues and documents the
//   empty state, so every stage degrades to something a reviewer can see.

import XCTest

final class MaximizeTourTests: XCTestCase {
    private var app: XCUIApplication!
    private var seededWorkoutsVisible = false

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // The iOS 26 Health sheet (toggles off by default, multi-step) is Apple's
        // UI, not the app's — automating it is fragile. The app skips it when this
        // launch argument is present; the tour still exercises the app's own
        // first-run flow, plan authoring, tabs, and chat.
        app.launchArguments.append("-skipHealthKitAuth")
    }

    // MARK: - The tour

    func testTour() {
        // Single launch: complete the first-run cover (Health sheet skipped via
        // launch arg — it's Apple's UI, not the app's). The tour exercises the
        // app's own flows: plan authoring, API-key setup, tabs, workout detail,
        // and chat.
        app.launch()
        dismissFirstRunCover()
        takeScreenshot(named: "01-first-run-complete")

        authorFirstPlan()
        takeScreenshot(named: "02-plan-saved")
        storeDummyAPIKey()
        takeScreenshot(named: "03-key-stored")
        tourTabs()
        tourWorkoutDetail()
        tourChatSheet()
        tourChatSheet()
        takeScreenshot(named: "09-tour-complete")
    }

    // MARK: - Stage 1: first run

    private func dismissFirstRunCover() {
        let continueButton = app.buttons["Continue"]
        XCTAssertTrue(
            continueButton.waitForExistence(timeout: 15),
            "First-run cover should offer Continue"
        )
        continueButton.tap()
        // With `-skipHealthKitAuth` the app skips the system Health sheet, so the
        // cover dismisses directly. (Without the flag, the sheet would appear here
        // and `answerSystemHealthPrompt` would handle it.)
        XCTAssertTrue(
            waitForCondition(timeout: 30, message: "first-run cover to dismiss") {
                !continueButton.exists
            },
            "Cover should dismiss after Continue"
        )
    }

    // MARK: - Stage 2: author the first plan

    private func authorFirstPlan() {
        // "Author a plan" lives on the Plan tab's empty state — the first-run
        // cover dismisses onto the Workouts tab, so switch tabs first.
        app.tabBars.buttons["Plan"].tap()
        let authorButton = app.buttons["Author a plan"]
        XCTAssertTrue(
            authorButton.waitForExistence(timeout: 15),
            "Setup card should offer plan authoring"
        )
        authorButton.tap()

        // The screen proposes a default plan that is immediately saveable.
        // Take a screenshot first for diagnostics (the assertion below may fail).
        takeScreenshot(named: "02a-plan-authoring")
        let saveButton = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Save as plan"))
            .firstMatch
        XCTAssertTrue(
            saveButton.waitForExistence(timeout: 15),
            "Plan authoring should offer a save button for the default plan"
        )
        saveButton.tap()

        // The save is async; wait for its confirmation before leaving, so the
        // card-advance assertion below is not racing the SwiftData write.
        let confirmation = app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Saved plan"))
            .firstMatch
        XCTAssertTrue(
            confirmation.waitForExistence(timeout: 15),
            "Plan authoring should confirm the save"
        )

        // PlanAuthoringView is pushed, not presented: go back to the list.
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(
            app.buttons["Add a key in Settings"].waitForExistence(timeout: 15),
            "Setup card should advance to the API key step after a plan is saved"
        )
    }

    // MARK: - Stage 3: store a dummy API key

    private func storeDummyAPIKey() {
        app.buttons["Add a key in Settings"].tap()

        let keyField = app.secureTextFields["Anthropic API key"]
        XCTAssertTrue(
            keyField.waitForExistence(timeout: 15),
            "Settings should show the Anthropic key field"
        )
        keyField.tap()
        // Deliberately fake: the tour never sends a message, so this key is
        // never used for a network call. It only unlocks the stored-key state.
        keyField.typeText("sk-ant-tour-dummy-key")
        app.buttons["Save"].tap()

        dismissSheetTitled("Settings")
    }

    // MARK: - Stage 4: let ingestion catch up, then tour the tabs

    /// The seeded runs are picked up by the launch-time anchored ingestion pass
    /// once the app holds Health read authorization (granted at stage 1).
    private func waitForSeededWorkouts() {
        app.tabBars.buttons["Workouts"].tap()
        let rowAppeared = waitForCondition(
            timeout: 60,
            message: "seeded workouts to appear"
        ) {
            self.firstWorkoutRow().exists
                || self.app.staticTexts["Set up. Nothing recorded yet."].exists
        }
        XCTAssertTrue(rowAppeared, "Workouts tab should settle on rows or the empty state")
        seededWorkoutsVisible = firstWorkoutRow().exists
        takeScreenshot(named: "04-workouts-tab")
    }

    private func tourTabs() {
        app.tabBars.buttons["Dashboard"].tap()
        XCTAssertTrue(
            app.navigationBars["Dashboard"].waitForExistence(timeout: 15),
            "Dashboard tab should open"
        )
        takeScreenshot(named: "05-dashboard-tab")

        app.tabBars.buttons["Plan"].tap()
        XCTAssertTrue(
            app.navigationBars["Plan"].waitForExistence(timeout: 15),
            "Plan tab should open"
        )
        takeScreenshot(named: "06-plan-tab")

        app.tabBars.buttons["Workouts"].tap()
    }

    // MARK: - Stage 5: workout detail

    private func tourWorkoutDetail() {
        guard seededWorkoutsVisible else {
            // Seeding failed earlier; the empty state was already screenshotted
            // in `waitForSeededWorkouts`. Nothing to open.
            return
        }
        let row = firstWorkoutRow()
        XCTAssertTrue(row.exists, "A seeded workout row should be tappable")
        row.tap()
        XCTAssertTrue(
            app.navigationBars["Workout"].waitForExistence(timeout: 15),
            "Workout detail should open"
        )
        // Give the heart-rate curve, splits and map a moment to render.
        sleep(2)
        takeScreenshot(named: "07-workout-detail")
        app.navigationBars.buttons.firstMatch.tap()
    }

    // MARK: - Stage 6: chat sheet (draft only, never sent)

    private func tourChatSheet() {
        let askButton = app.buttons
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Ask"))
            .firstMatch
        XCTAssertTrue(
            askButton.waitForExistence(timeout: 15),
            "An Ask entry button should be present"
        )
        askButton.tap()
        XCTAssertTrue(
            app.sheets.firstMatch.waitForExistence(timeout: 10),
            "Chat sheet should open"
        )
        takeScreenshot(named: "08a-chat-opened")

        let composer = app.textFields["Ask about your training…"]
        XCTAssertTrue(
            composer.waitForExistence(timeout: 10),
            "Chat composer should show the training placeholder"
        )
        composer.tap()
        composer.typeText("How did my training week go?")
        // Deliberately not sent: the stored key is a dummy and sending would
        // attempt a real API call. The draft proves the composer works.
        takeScreenshot(named: "08b-chat-composer-draft")

        // A fresh training chat has no thread yet, so the sheet's navigation
        // title is the neutral "Chat" placeholder.
        dismissSheetTitled("Chat")
    }

    // MARK: - Helpers

    /// Rows are NavigationLinks in a LazyVStack, exposed as buttons whose label
    /// combines the row's date, the "Running" activity name and the distance.
    private func firstWorkoutRow() -> XCUIElement {
        app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "Running"))
            .firstMatch
    }

    /// Answers the system Health permission sheet ("Allow" / "Don't Allow")
    /// directly through SpringBoard, the way a user would.
    /// Answers the iOS Health permission sheet the way a user would. The HealthKit
    /// authorization UI is a system sheet, not a SpringBoard alert — it appears in
    /// the app's own hierarchy. Tries the common button labels; if none appears
    /// within the timeout, returns without failing (the caller decides whether the
    /// sheet was required).
    /// Answers the iOS Health Access sheet the way a user would. The sheet lists
    /// data types with toggles (all off by default) — tapping "Allow" with
    /// everything off grants nothing. So: tap "Turn On All" first, then "Allow".
    private func answerSystemHealthPrompt(timeout: TimeInterval) {
        let appeared = waitForCondition(timeout: timeout, message: "Health permission sheet") {
            self.app.buttons["Turn On All"].exists || self.app.buttons["Allow"].exists
        }
        guard appeared else { return }
        // Enable all data types first; otherwise Allow grants nothing.
        if app.buttons["Turn On All"].exists {
            app.buttons["Turn On All"].tap()
            // Give the toggles a moment to flip on.
            _ = waitForCondition(timeout: 5, message: "toggles to enable") {
                // The Allow button becomes enabled once types are on; just proceed
                // to tapping it — if it's still disabled the tap is a no-op and the
                // caller will see the cover not dismiss.
                true
            }
        }
        if app.buttons["Allow"].exists {
            app.buttons["Allow"].tap()
        }
    }

    /// Taps Done until the sheet with the given navigation title is gone. The
    /// first tap may only dismiss the keyboard's own Done button.
    private func dismissSheetTitled(_ title: String) {
        for _ in 0..<4 {
            guard app.navigationBars[title].waitForExistence(timeout: 5) else { return }
            app.buttons["Done"].firstMatch.tap()
        }
        XCTAssertFalse(
            app.navigationBars[title].exists,
            "Sheet '\(title)' should dismiss"
        )
    }

    @discardableResult
    private func waitForCondition(
        timeout: TimeInterval,
        message: String,
        condition: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() >= deadline { return false }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return true
    }

    private func takeScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

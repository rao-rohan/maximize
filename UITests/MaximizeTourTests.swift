// UITests/MaximizeTourTests.swift
//
// A hands-on simulator tour of the Maximize app, run on demand by
// `.github/workflows/simulator-tour.yml` (workflow_dispatch only).
//
// What it does, in order:
//   1. Seeds three sample runs (heart-rate series on each, a GPS route on one)
//      into the simulator's HealthKit store, answering the test runner's own
//      Health permission sheet the way a user would.
//   2. Launches the app and walks first run: cover -> Continue -> Health
//      permission sheet -> setup card.
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

import CoreLocation
import HealthKit
import XCTest

final class MaximizeTourTests: XCTestCase {
    private var app: XCUIApplication!
    private var seededWorkoutsVisible = false

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    // MARK: - The tour

    func testTour() {
        seedSampleWorkouts()
        app.launch()
        dismissFirstRunCover()
        takeScreenshot(named: "01-first-run-complete")
        authorFirstPlan()
        takeScreenshot(named: "02-plan-saved")
        storeDummyAPIKey()
        takeScreenshot(named: "03-key-stored")
        waitForSeededWorkouts()
        tourTabs()
        tourWorkoutDetail()
        tourChatSheet()
        takeScreenshot(named: "09-tour-complete")
    }

    // MARK: - Stage 0: seed HealthKit samples from the test runner

    /// Writes three runs into the simulator's HealthKit store from the test
    /// process, answering the runner's own permission sheet via SpringBoard.
    /// Best-effort: on failure the tour continues and documents the empty state.
    private func seedSampleWorkouts() {
        let box = ErrorBox()
        let done = DispatchSemaphore(value: 0)
        Task {
            do {
                try await SampleWorkoutSeeder.seed()
            } catch {
                box.error = error
            }
            done.signal()
        }
        answerSystemHealthPrompt(timeout: 20)
        _ = done.wait(timeout: .now() + 180)
        if let error = box.error {
            // Seeding failed; the tour continues and `waitForSeededWorkouts`
            // will document the empty state. The failure is in the test log.
            print("TOUR: seeding sample workouts failed: \(error)")
            takeScreenshot(named: "00-seeding-failed")
        }
    }

    // MARK: - Stage 1: first run

    private func dismissFirstRunCover() {
        let continueButton = app.buttons["Continue"]
        XCTAssertTrue(
            continueButton.waitForExistence(timeout: 15),
            "First-run cover should offer Continue"
        )
        continueButton.tap()
        // Tapping Continue triggers the app's Health read-authorization
        // request; the sheet is a system alert answered the way a user would.
        answerSystemHealthPrompt(timeout: 20)
        XCTAssertTrue(
            waitForCondition(timeout: 30, message: "first-run cover to dismiss") {
                !continueButton.exists
            },
            "Cover should dismiss after Health access is granted"
        )
    }

    // MARK: - Stage 2: author the first plan

    private func authorFirstPlan() {
        let authorButton = app.buttons["Author a plan"]
        XCTAssertTrue(
            authorButton.waitForExistence(timeout: 15),
            "Setup card should offer plan authoring"
        )
        authorButton.tap()

        // The screen proposes a default plan that is immediately saveable.
        let saveButton = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Save as plan"))
            .firstMatch
        XCTAssertTrue(
            saveButton.waitForExistence(timeout: 15),
            "Plan authoring should offer a save button for the default plan"
        )
        takeScreenshot(named: "02a-plan-authoring")
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
    private func answerSystemHealthPrompt(timeout: TimeInterval) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allowButton = springboard.alerts.firstMatch.buttons["Allow"]
        let appeared = waitForCondition(timeout: timeout, message: "Health permission sheet") {
            allowButton.exists
        }
        guard appeared else { return }
        allowButton.tap()
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

// MARK: - Sample data

/// Writes three deterministic runs into HealthKit: heart-rate series on each,
/// a GPS route on the most recent one. Runs on the test runner, not in the app —
/// the app itself never writes to HealthKit.
private enum SampleWorkoutSeeder {
    static func seed() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let store = HKHealthStore()
        let workoutType = HKObjectType.workoutType()
        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let routeType = HKSeriesType.workoutRoute()
        try await store.requestAuthorization(
            toShare: [workoutType, heartRateType, routeType],
            read: [workoutType, heartRateType, routeType]
        )

        let now = Date()
        // A loop in Central Park for the route, timestamps matching the run.
        let routeStart = now.addingTimeInterval(-86400 - 1800)
        try await seedRun(
            store: store,
            heartRateType: heartRateType,
            start: routeStart,
            duration: 1800,
            distanceMeters: 5000,
            baseBPM: 142,
            withRoute: true
        )
        try await seedRun(
            store: store,
            heartRateType: heartRateType,
            start: now.addingTimeInterval(-3 * 86400 - 1500),
            duration: 1500,
            distanceMeters: 5200,
            baseBPM: 158,
            withRoute: false
        )
        try await seedRun(
            store: store,
            heartRateType: heartRateType,
            start: now.addingTimeInterval(-6 * 86400 - 4500),
            duration: 4500,
            distanceMeters: 12000,
            baseBPM: 138,
            withRoute: false
        )
    }

    private static func seedRun(
        store: HKHealthStore,
        heartRateType: HKQuantityType,
        start: Date,
        duration: TimeInterval,
        distanceMeters: Double,
        baseBPM: Double,
        withRoute: Bool
    ) async throws {
        let end = start.addingTimeInterval(duration)

        // HKWorkoutBuilder, not the deprecated HKWorkout(activityType:start:end:)
        // initializer — the builder is the only supported way to create a workout
        // with associated samples since iOS 17.
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        let builder = try await HKWorkoutBuilder(
            healthStore: store,
            configuration: configuration,
            device: .local()
        )
        try await builder.beginCollection(at: start)

        let bpmUnit = HKUnit.count().unitDivided(by: .minute())
        let sampleCount = Int(duration / 10)
        let samples = (0..<sampleCount).map { index -> HKQuantitySample in
            let timestamp = start.addingTimeInterval(Double(index) * 10)
            let bpm = baseBPM + 12 * sin(Double(index) / 9) + Double(index % 5)
            return HKQuantitySample(
                type: heartRateType,
                quantity: HKQuantity(unit: bpmUnit, doubleValue: bpm),
                start: timestamp,
                end: timestamp
            )
        }
        // Samples go through the builder, not a separate save + add: the builder
        // owns the in-progress workout, and HKHealthStore.add(_:to:) has no async
        // variant.
        try await builder.add(samples)

        try await builder.endCollection(at: end)
        let workout = try await builder.finishWorkout()

        if withRoute {
            let builder = HKWorkoutRouteBuilder(healthStore: store, device: nil)
            let center = CLLocationCoordinate2D(latitude: 40.7812, longitude: -73.9665)
            let locations = (0..<120).map { index -> CLLocation in
                let angle = Double(index) / 120 * 2 * .pi
                return CLLocation(
                    coordinate: CLLocationCoordinate2D(
                        latitude: center.latitude + 0.004 * cos(angle),
                        longitude: center.longitude + 0.004 * sin(angle)
                    ),
                    altitude: 10,
                    horizontalAccuracy: 5,
                    verticalAccuracy: 5,
                    timestamp: start.addingTimeInterval(Double(index) * duration / 120)
                )
            }
            try await builder.insertRouteData(locations)
            try await builder.finishRoute(with: workout, metadata: nil)
        }
    }
}

/// A mutable box so the unstructured seeding Task can report its error back to
/// the synchronous test without tripping Swift 6's Sendable checks. Written
/// once by the Task, read once after the semaphore synchronizes the two.
private final class ErrorBox: @unchecked Sendable {
    var error: Error?
}

# Simulator tour plan

A hands-on XCUITest tour of the Maximize app, run on demand from
`.github/workflows/simulator-tour.yml` (workflow_dispatch only). It exists so a
human can *watch* the app work — screen recording plus a screenshot at every
major stage — rather than inferring it from unit tests.

## What the tour covers

The single test `MaximizeTourTests.testTour` (`UITests/MaximizeTourTests.swift`)
walks this path on a freshly booted iPhone simulator:

1. **Seed HealthKit samples** — the test runner (not the app) requests HealthKit
   authorization and writes three runs: yesterday's 30-minute 5K with a heart-rate
   series and a GPS loop in Central Park, a tempo run three days ago, and a
   75-minute long run six days ago. The runner's permission sheet is answered
   through SpringBoard, the way a user would.
2. **First run** — app launches, the cover ("Maximize scores your runs against
   your plan.") shows Continue, tapping it triggers the app's own Health
   read-authorization sheet, Allow is tapped, the cover dismisses.
3. **Plan authoring** — the setup card's "Author a plan" step is tapped, the
   default plan the screen proposes is saved ("Save as plan 1"), back to the list.
4. **API key** — the card's "Add a key in Settings" step opens Settings, the
   dummy key `sk-ant-tour-dummy-key` is typed into the Anthropic key field and
   saved. **The key is deliberately fake.**
5. **Ingestion** — the tour waits for the seeded runs to appear via the
   launch-time anchored ingestion pass, then screenshots the Workouts tab.
6. **Tabs** — Dashboard and Plan tabs are opened and screenshotted.
7. **Workout detail** — the first run is opened; heart-rate curve, splits,
   route map and verdict header render (scoring will fail against the dummy key
   — that failure UI is itself worth seeing).
8. **Chat sheet** — the Ask entry button opens the sheet, a draft
   ("How did my training week go?") is typed into the composer and **never sent**.
   The sheet is dismissed with Done.

Screenshots are attached with `.keepAlways` lifetime, so they survive in the
`.xcresult` even for passing runs, and the workflow also exports them as loose
files.

## Deliberate limits

- **No message is ever sent.** The stored key is a dummy and the chat assertions
  stop at the composer draft, so the tour never makes a network call and never
  needs a real secret in CI.
- **HealthKit background delivery is not exercised.** A simulator cannot prove
  the wake path; the seeded samples exercise the anchored fetch that also runs
  on every launch and every foregrounding.
- **The app under test is unchanged.** Seeding happens from the UI-test runner,
  which carries the only HealthKit write entitlement in the project
  (`Support/MaximizeUITests.entitlements`, generated from `project.yml` like the
  app's). The production target excludes `UITests/` from its sources, and the
  tour adds no launch arguments or test hooks to the app.
- **Simulator visuals are not device truth.** Layout, Liquid Glass rendering and
  HealthKit behavior on a physical iPhone can differ; the tour pressure-tests the
  flow, not the pixels.

## If a stage fails

The test uses `continueAfterFailure = false`: the first failure stops the tour,
and the screen recording plus the screenshots up to that point show exactly
where. One exception: if HealthKit seeding itself fails, the tour continues and
documents the empty state ("Set up. Nothing recorded yet.") instead of
aborting, so the plan/key/tabs/chat stages still get their coverage.

## Running it

Actions → "Simulator tour" → Run workflow. When it finishes, download the
`simulator-tour` artifact: `tour.mp4` for the full run, `attachments/` for the
stage screenshots, `Tour.xcresult` for the detailed test report.

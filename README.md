# Maximize

An iOS app that captures your runs from HealthKit without being asked, scores each one
against a training plan, and lets you ask Claude about them.

The point is the absence of data entry. A finished run is picked up in the background,
measured, classified, scored and stored before you open the app — PRD §2's north star is
"never hand-type a workout log row again."

---

## ⛔ This app must not be distributed

**The Anthropic API key lives in Keychain on the device.** That is a deliberate
weakening of the original design ([A5](./docs/PRD-AMENDMENTS.md)), accepted on exactly
one condition: this app is single-user and is never shipped to anyone else.

Anyone holding the binary can extract the key and spend against the account it belongs
to. **If this app is ever distributed — TestFlight, App Store, or sideloaded onto a
friend's phone — the key must move behind a server first.** That is a release blocker,
not a follow-up.

The same notice appears in [`docs/DEVICE-BUILD.md`](./docs/DEVICE-BUILD.md), which is
where you actually go to make a signed build.

---

## What it does

- **Zero-touch capture** — an `HKObserverQuery` with background delivery wakes the app
  when a run finishes; an anchored fetch pulls it in exactly once.
- **Scoring against a versioned plan** — thresholds, HR cap, cadence band and rubric all
  live in a versioned plan record, so a historical score stays reproducible after the
  plan changes.
- **A workout detail screen** — plan verdict, heart-rate curve against the cap, cadence
  against target, route map, splits and summary tiles.
- **Trends** — a score-coloured calendar, per-interval tallies, and a cross-run
  heart-rate drift overlay that normalises runs of different lengths onto one
  %-elapsed axis.
- **Chat** — ask Claude about a specific run, with the reply streaming in.

## How it is built

**Fully on-device.** SwiftData for storage, Claude called directly from the app, no
backend. The PRD as written specified FastAPI/Postgres/Redis; that was superseded — see
[`docs/PRD-AMENDMENTS.md`](./docs/PRD-AMENDMENTS.md).

**Thin shell, fat core.** All logic lives in `MaximizeCore`, a pure Swift package with no
platform imports; the iOS target is a shell that renders and forwards intent. This is
mechanical rather than aesthetic — CI runs `swift test` on every commit, so logic in the
core is verified continuously, while logic in a SwiftUI view is verified only when a
human opens Xcode. CI enforces the boundary by rejecting platform imports in the core.

```
Package.swift            MaximizeCore — pure domain logic
Sources/MaximizeCore/    metrics, scoring, plan, context builder, tallies
Tests/                   unit tests — the merge gate
App/                     SwiftUI app + platform adapters
docs/PRD.md              the spec, as received
docs/PRD-AMENDMENTS.md   where we deliberately deviate from it, and why
docs/DEVICE-BUILD.md     how to get a build onto a real iPhone
docs/SECURITY-REVIEW.md  what was audited, and what was not
PROJECT_TRACKER.md       every ticket, its status, and the reasoning behind it
```

## What CI proves, and what it doesn't

CI **proves**: the package compiles, the app target compiles, and 700+ unit tests pass.

CI **cannot prove**: that HealthKit background delivery works, that the UI looks right,
or that a Claude call succeeds. The Simulator cannot run background delivery at all,
which is why this repo never produces an installable build — a simulator artifact could
not verify the product's central claim. Those are device checks, and every PR touching
them lists what a human must tap.

## Building it

You need a Mac with Xcode 26 and an Apple ID. See
[`docs/DEVICE-BUILD.md`](./docs/DEVICE-BUILD.md) — about five minutes the first time.
Signing lives in a gitignored local file; no team ID or bundle identifier is ever
committed.

## Contributing

[`CLAUDE.md`](./CLAUDE.md) is the contract every contributor works under, human or agent.
Read it and [`docs/PRD.md`](./docs/PRD.md) before writing code.

# Maximize — Engineering Conventions

Automated workout capture, scoring, and analysis. See [docs/PRD.md](./docs/PRD.md)
for what we are building and why. This file is the contract every contributor —
human or agent — works under. Read both before writing code.

## Repository layout

```
Package.swift          MaximizeCore — pure domain logic, no frameworks
Sources/MaximizeCore/  metrics, scoring, plan, context builder, tallies
Tests/                 unit tests — the merge gate
App/                   SwiftUI app + platform adapters   (arrives in MAX-006)
docs/PRD.md            the spec, as received
docs/PRD-AMENDMENTS.md where we deliberately deviate from it, and why
```

**There is no backend.** The app is fully on-device: SwiftData for storage, CloudKit
for backup, Claude called directly from the app. See `docs/PRD-AMENDMENTS.md` — the
PRD as written specifies a FastAPI/Postgres/Redis backend, and that has been
superseded. Do not build server components.

## Architecture: thin shell, fat core

The single most important rule in this repo:

> **All logic lives in `MaximizeCore`. The iOS app target is a thin shell.**

The reason is mechanical, not aesthetic. CI runs on a macOS runner and gates every
merge on `swift test`. Logic inside `MaximizeCore` is therefore *verified* on every
commit. Logic inside a SwiftUI view is *not* — it is only verified when a human opens
Xcode, which is a slow and unreliable gate. Every line you move into the core is a
line the robots check for you.

Concretely:

- `MaximizeCore` **must not** import `SwiftUI`, `UIKit`, or `HealthKit`.
- Platform frameworks are reached through protocols defined in the core and
  implemented in the app layer. The core depends on the protocol; the app supplies
  the real thing; tests supply a fake.
- A view should read as: observe state, render it, forward user intent. If a view
  contains a calculation, a branch on business rules, or a date computation, that
  belongs in the core.
- "I can't test this, it needs a device" is usually a design smell. Push the logic
  down until the untestable part is a thin adapter with no decisions in it.

## Definition of done

A ticket is done when all of these hold:

1. The change is on its own branch, one logical change per commit.
2. New behavior has tests. Bug fixes have a test that fails without the fix.
3. `swift build` and `swift test` pass in CI. **Green CI is the merge gate.**
4. A code review has run and its findings are addressed or explicitly dismissed
   with a reason.
5. `PROJECT_TRACKER.md` reflects the new state.

## What CI can and cannot prove

Be honest about this in every PR description.

CI **can** prove: the package compiles, unit tests pass, business logic behaves.

CI **cannot** prove: the UI looks right, HealthKit permission flows work against a
real Health store, on-device performance, App Store entitlements, anything requiring
a signed build on hardware.

When a change touches the second category, say so plainly in the PR under a
**Needs device verification** heading, and list what a human should tap. Do not
claim a change "works" when what you mean is "it compiles and its unit tests pass."
State the latter.

## Health and privacy

Health data never leaves the device except as prompt context in a Claude call. That
is a strong default and it is worth keeping.

- **The Anthropic API key lives in Keychain, on-device.** This is a deliberate
  weakening of PRD §6, acceptable only because the app is single-user and never
  distributed. **Tripwire: if this app is ever shipped to anyone else, the key must
  move behind a server first.** Do not treat "it's already on-device" as precedent.
- **Health data is PII.** Rely on iOS file protection; do not copy workout data into
  logs, analytics, crash reports, or plaintext scratch files.
- **No secrets in the repo. Ever.** Not in source, not in `project.yml`, not in a
  test fixture. `.gitignore` covers the usual paths but is not a substitute for care.
- Only what the scorer or chat actually needs goes into a Claude prompt. The context
  builder (D3) is the single place that decides this — never assemble prompt context
  anywhere else.

Any PR touching Keychain, key handling, or what enters a Claude prompt gets a
`/security-review` before merge, no exceptions.

## Determinism rules from the PRD

Three locked decisions are load-bearing and easy to violate by accident. Treat them
as invariants:

- **D1 — the plan is versioned data, not code.** Thresholds, HR cap, cadence band,
  and the scoring rubric live in a versioned plan record. Changing a threshold is a
  new plan version, never a code change. Scoring reads the version in effect on the
  workout's date, so historical scores stay reproducible.
- **D2/D3 — derived metrics are computed once at ingestion and stored; one context
  builder feeds both scorer and chat.** Never recompute a metric at display time, and
  never build a second notion of "what Claude knows about this run." Both drift, and
  the drift is invisible until a number disagrees with itself on screen.
- **D8 — auto-scores are immutable.** Manual corrections are additive annotation
  records. The divergence between the two is the scorer-quality metric (PRD §2).
  Overwriting a score destroys exactly the telemetry we want.

## Style

- Swift API Design Guidelines. Clarity at the point of use beats brevity.
- Prefer `struct` and value semantics. Reach for `class` when identity or shared
  mutable state is genuinely required.
- Model illegal states as unrepresentable where the type system allows it.
- Comment *why*, not *what*. Match the density of the surrounding file.
- No force unwraps (`!`) in non-test code. If a value truly cannot be nil, encode
  that in the type.

## Commits and PRs

- One logical change per commit; a commit that "also fixes" something unrelated
  should have been two commits.
- Imperative subject line under ~70 chars: `Add set-volume calculation to core`.
- Reference the ticket ID: `MAX-012: Add set-volume calculation to core`.
- PRs stay small. A PR that touches thirty files is a PR nobody reviews properly.

## For agents working a ticket

You are being handed a scoped ticket, not the project. Stay inside it.

- Read `PROJECT_TRACKER.md` for your ticket's acceptance criteria before starting.
- If the ticket is underspecified or you believe it is wrong, say so in your report
  rather than silently redesigning it.
- If you discover work outside your ticket, report it — do not do it.
- Report honestly. "Tests pass" and "I believe this is correct but could not run it"
  are different sentences with different consequences. Use the accurate one.

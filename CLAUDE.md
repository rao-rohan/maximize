# Maximize — Engineering Conventions

iOS workout tracker with AI features. This file is the contract every contributor —
human or agent — works under. Read it before writing code.

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

Workout and biometric data is sensitive. Until the PRD says otherwise, assume:

- Health data stays on device by default.
- Anything sent to an AI backend is opt-in, minimized, and documented in the PR.
- No API keys, tokens, or secrets in the repo. Ever. They go in
  `.xcconfig.local` / environment, which `.gitignore` excludes.

Any PR that moves health data off device gets a `/security-review` before merge, no
exceptions.

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

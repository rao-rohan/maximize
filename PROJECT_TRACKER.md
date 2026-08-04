# Maximize — Project Tracker

**Last updated:** 2026-08-04
**Spec:** [docs/PRD.md](./docs/PRD.md) + [docs/PRD-AMENDMENTS.md](./docs/PRD-AMENDMENTS.md) (amendments win)
**Architecture:** Fully on-device. No backend.
**Pipeline status:** 🟢 CI green — 411+ tests. **Capture-to-score loop closed (MAX-033).** Core build/test, architecture guard, colour-token guard, unsigned iOS Simulator app build.

---

## How this document works

Single source of truth for what is left to build. Committed to the repo and updated in
the same PR as the work it describes — a ticket's status changing is part of the diff.

Every ticket traces to a PRD requirement. When the spec changes, this document is
re-derived and the delta called out explicitly rather than quietly merged.

The overseer owns decomposition, agent assignment, review, and integration. Subagents
get one scoped ticket with acceptance criteria — never an open-ended goal.

## Agent tiering policy

| Tier | Use for | Examples here |
|---|---|---|
| **Haiku** | Mechanical, fully specified, low blast radius. The answer is known; it needs typing. | *Currently unused — see below* |
| **Sonnet** | Standard feature work against a clear spec. Judgment within known patterns. | A screen, a chart, an adapter, a test suite |
| **Opus** | Architecture, numerically subtle, or expensive to get wrong. | Domain types, plan versioning, derived metrics, classification, scorer, streaming, drift overlay, HealthKit background delivery |

Escalation rule: a Haiku/Sonnet ticket that turns out to need a design decision gets
reported back, not decided unilaterally. The overseer re-tiers it.

**The Haiku tier is empty on purpose, and this is a revision of the original policy.**
Summary tiles (MAX-045), the interval selector (MAX-060), the settings screen (MAX-064)
and the fixture suite (MAX-071) were all tiered Haiku here on the reasoning that the
work was mechanical. The one that actually ran as Haiku, MAX-064, pushed a branch
without opening a PR — so CI never ran — and reported "compiles" for code that had
never been built; three real compile errors and a set of inert accessibility toggles
had to be repaired afterwards. The repair cost more than the tier saved.

The mistake in the original reasoning is that **no ticket in this repo is verified
locally.** There is no Swift toolchain in an agent's container, so every ticket ends in
"I could not build this; CI is the first compile" — which means the tier is not buying
typing speed against a compiler, it is buying the care to get code right *without* one,
plus the discipline to open the PR that runs CI at all. That is not mechanical work at
any tier. Scope is what keeps a thin ticket thin; the brief says so explicitly.

## Ticket lifecycle

`Backlog` → `Ready` → `In progress` → `In review` → `Merged`

**Ready** = acceptance criteria written and dependencies merged. **In review** = CI green
and a code review has run. Definition of done lives in [CLAUDE.md](./CLAUDE.md).

---

## Board

Status key: ✅ merged · 🔄 in progress · 🔲 ready · ⬜ blocked on dependencies

### Phase 0 — Foundation

| ID | Ticket | Spec | Tier | Status | Depends on |
|---|---|---|---|---|---|
| MAX-001 | Repo conventions, `.gitignore`, `CLAUDE.md` | — | — | ✅ | — |
| MAX-002 | `MaximizeCore` package skeleton + smoke test | — | — | ✅ | — |
| MAX-003 | CI: build, test, architecture guard | — | — | ✅ | — |
| MAX-004 | Project tracker | — | — | ✅ | — |
| MAX-005 | Vendor PRD, record amendments, revise conventions for on-device | A1–A7 | — | ✅ | — |
| MAX-006 | App shell: XcodeGen spec, iOS 26 SDK, simulator build in CI | §7.4 | Sonnet | ✅ | MAX-005 |

Phase 0 was done directly by the overseer — delegating a `.gitignore` costs more than
it saves.

### Phase 1 — Domain core

**All of this lives in `MaximizeCore` as pure Swift, and CI verifies every line of it.**
This is the payoff from going on-device: the logic most expensive to get wrong is now
the logic most thoroughly tested. Nothing here touches a framework, a database, or a
network.

| ID | Ticket | Spec | Tier | Status | Depends on |
|---|---|---|---|---|---|
| MAX-010 | Domain value types: Workout, HR series, route, Plan, PlanDay, Score, Annotation | §8 | **Opus** | ✅ | — |
| MAX-011 | Versioned plan + `PlanDay` calendar resolution | D1, §8 | **Opus** | ✅ | MAX-010 |
| MAX-012 | Derived metrics: time-above-cap, HR drift, avg cadence, grade-adjusted pace, zone splits | §9, D2 | **Opus** | ✅ | MAX-010 |
| MAX-013 | Workout classification (easy / hard / long / other) from type + HR profile | §10.2 | **Opus** | ✅ | MAX-012 |
| MAX-014 | Context builder — the single assembler of what Claude sees | D3 | **Opus** | ✅ | MAX-011, MAX-013 |
| MAX-015 | Scoring rubric application + effective threshold + rationale contract | §10, D1 | **Opus** | ✅ | MAX-014 |
| MAX-016 | Rest-day budget: automatic conversion of missed days | D9, A6 | Sonnet | ✅ | MAX-011 |
| MAX-017 | Tallies: workout-days, effective-days, avg score, streak, current week | FR-3.4, §8 | Sonnet | ✅ | MAX-015, MAX-016 |

MAX-013 is Opus despite looking small: PRD §13 names plan/actual misclassification as
a risk that "poisons the score," and every downstream number inherits its mistakes.

MAX-031 was **re-tiered from Sonnet to Opus** after MAX-030 landed. The original
estimate treated it as a routine fetch; R9 made it the thing standing between a failed
background wake and permanent silent data loss.

**Process note for parallel work.** MAX-012 was branched before MAX-030 and MAX-070
merged, so its PR diff showed both tickets' files as deletions — merging it unrebased
would have silently reverted them. Rebase every long-running agent branch onto `main`
before opening its PR, and check the diff is additions-only where it should be.
Related: dispatch briefs must be self-contained, because an agent's worktree only sees
`main` as it stood when the worktree was made.

### Phase 2 — Persistence & platform adapters

The seam between the pure core and iOS. Core defines value types and protocols; this
layer implements them and maps across the boundary.

| ID | Ticket | Spec | Tier | Status | Depends on |
|---|---|---|---|---|---|
| MAX-020 | SwiftData models + mapping to/from core types + repository implementations | §8, A1 | **Opus** | ✅ | MAX-006, MAX-010 |
| MAX-021 | CloudKit sync so history survives reinstall | D6, A1 | Sonnet | ✅ | MAX-020 |
| MAX-022 | Keychain-backed Anthropic key storage + settings entry point | A5, §11 | Sonnet 🔒 | ✅ | MAX-006 |
| MAX-023 | Claude client: scoring call | §10, §11 | Sonnet 🔒 | ✅ | MAX-022, MAX-015 |
| MAX-024 | Claude client: streaming chat transport | D10, FR-2.4 | **Opus** | ✅ | MAX-022, MAX-014 |

🔒 = requires `/security-review` before merge.

### Phase 3 — Ingestion (zero-touch capture)

Mostly *not* CI-verifiable — HealthKit needs a device. Mitigation: anchor management,
dedupe, and payload assembly live in `MaximizeCore` behind protocols and are unit
tested; the HealthKit adapter stays a thin, decision-free shim. Per direction, we do
not block on device runs — but every PR here states plainly what a human must tap.

| ID | Ticket | Spec | Tier | Status | Depends on |
|---|---|---|---|---|---|
| MAX-030 | `HKObserverQuery` + background delivery + entitlement | FR-0.1 | **Opus** | ✅ | MAX-006 |
| MAX-031 | Anchored incremental fetch with persisted anchor | FR-0.2 | **Opus** | ✅ | MAX-030 |
| MAX-032 | Full-fidelity extraction: HR series, route, cadence, energy; indoor runs first-class | FR-0.3, FR-0.6 | Sonnet | ✅ | MAX-031 |
| MAX-033 | Ingestion pipeline: dedupe on `workoutUUID`, compute + store derived metrics, trigger scoring | FR-0.5, D2, A2 | **Opus** | ✅ | MAX-032, MAX-020, MAX-023 |
| MAX-034 | Store captured samples independently of plan coverage | FR-0.3, D7 | Sonnet | ✅ | MAX-033 |

**MAX-034 fixed real data loss, found by MAX-042.** `WorkoutIngestionPipeline.enrich`
used to return as soon as no plan governed the workout's day — *before*
`WorkoutSampleExtractor` ran — so the heart-rate series, route and step count were
never fetched or stored. Sample extraction now runs unconditionally and first. Its
reasoning is sound for **derived metrics**, which are all measured against the plan's
cap, but the raw curve is a fact about the run rather than about the plan.

The loss is permanent in practice: the anchor advances past the workout, so nothing
revisits it. Every run predating the first plan version therefore keeps no curve at all
— and D7 stores whole curves precisely so the cross-run drift overlay (D5/FR-3.3,
MAX-062) can read them. PRD §1 calls that overlay the thing no other app can draw.

It also conflated two states downstream that MAX-042 correctly renders differently:
"no plan governed this day" and "this workout has no heart-rate data".

**Open, reported by MAX-034, not fixed by it:** a workout in the
`.workoutPredatesEveryPlan` state can never gain derived metrics. `completeIngestion`
re-resolves the plan calendar on every call, so `.noPlanAuthored` workouts *are*
recoverable — the first plan version an athlete authors may cover them retroactively —
but MAX-011's no-back-dating rule means that once any version exists, no later one can
open earlier. Those runs keep their curves (post-MAX-034) and stay permanently
unscored. No backfill mechanism exists; deciding whether one is wanted is its own
ticket, not a defect in the pipeline.

**MAX-033 must treat an already-recorded automatic score as success, not failure.**
MAX-020 flagged this: `automaticScoreAlreadyRecorded` is what D8 immutability looks
like on a replayed workout, and replays are normal here — dedupe absorbs them by
design. Treating it as an error would leave the anchor pinned forever, which is R11
arriving through the one path the pipeline is guaranteed to take.

**The pipeline is live.** MAX-033 replaced MAX-031's deliberately-throwing placeholder
sink, so a finished run is now captured, measured, classified, scored and stored with
nobody touching the phone — PRD §2's north star. Anything captured while the pipeline
was pinned drains on the first wake after that build reaches a device.

MAX-032 inherits two things from MAX-031: the sink hands over a domain `Workout` whose
`start`/`end` window is the predicate every sample query needs, and the route-existence
probe in `HealthKitWorkoutFetcher` (one extra query per outdoor workout, needed to fill
`Workout.hasRoute` truthfully) **should be subsumed** by the route fetch itself.

### Phase 4 — Design system & detail view

| ID | Ticket | Spec | Tier | Status | Depends on |
|---|---|---|---|---|---|
| MAX-040 | Design system: dark-first tokens, score bands, accent, Liquid Glass on chrome only, flat content surfaces | FR-4.1–4.4, A7 | **Opus** | ✅ | MAX-006 |
| MAX-041 | Detail view: plan-verdict header | FR-1.1 | Sonnet | ✅ | MAX-020, MAX-040 |
| MAX-042 | HR curve with cap line + time-above-cap shading | FR-1.2 | Sonnet | ✅ | MAX-040, MAX-012 |
| MAX-043 | Cadence vs target band | FR-1.3 | Sonnet | ✅ | MAX-042 |
| MAX-044 | Route map — outdoor only, omitted cleanly for treadmill | FR-1.4 | Sonnet | ✅ | MAX-040 |
| MAX-045 | Splits + summary tiles | FR-1.5 | Sonnet | ✅ | MAX-040 |
| MAX-046 | Per-split pace breakdown: compute at ingestion, store, display | FR-1.5, D2 | **Opus** | 🔲 | MAX-045, MAX-033 |
| MAX-047 | Make `AppSettings.distanceUnit` load-bearing, or delete it | FR-1.5, FR-4.5 | Sonnet | 🔲 | MAX-045 |

**MAX-045 delivers the summary tiles but not the splits, and that is not a shortfall in
the ticket — it is a missing data source.** FR-1.5 asks for a per-km/mile pace
breakdown; the only thing `DerivedMetrics` stores under that name is `zoneSplits`, which
is time per heart-rate zone, a different measurement entirely. MAX-045 correctly refused
to compute a split breakdown in the view or in a display-time helper: D2 says a metric is
computed once at ingestion and stored, and a second place that derives pace-per-kilometre
is exactly the drift D2 exists to prevent.

So **MAX-046 is an ingestion ticket wearing a display ticket's clothes**, which is why it
is tiered Opus rather than following MAX-045's Sonnet. It has to decide what a split
*is* against a route whose GPS fixes are irregular (and absent entirely on a treadmill),
compute it in the pipeline, add it to the stored schema under CloudKit's constraints, and
only then render it. The display is the last and smallest part.

**MAX-047 is a live inert control.** `AppSettings.distanceUnit` is persisted, has a
working Settings picker from MAX-064, and is read by nothing — every distance in the app,
including the pre-existing `WorkoutDisplayFormatting.distance(meters:)`, hardcodes
kilometres. MAX-045 matched that convention rather than making its own tile the single
unit-aware figure on the screen, which was the right call for its scope and leaves the
inconsistency in one place instead of two.

This is the same defect I removed from MAX-064's accessibility toggles: a switch that
persists a value nothing consumes is worse than no switch, because it looks like one.
The ticket is deliberately phrased as a choice — wire it through every display path, or
delete the field and its picker. Either is defensible; a persisted setting that silently
does nothing is not.

FR-1.5 is explicitly "thin — displayed because cheap, not lovingly built," which is why
MAX-045 was originally tiered Haiku. **Re-tiered to Sonnet before dispatch.** The tier
was chosen to keep the *ticket* thin, but the last Haiku ticket (MAX-064) pushed a
branch without opening a PR — so CI never ran — and reported "compiles" for code that
had never been built; three real compile errors surfaced afterwards. The saving was
smaller than the three rounds of repair it cost. Scope, not tier, is what keeps FR-1.5
thin, and the brief carries that instruction explicitly.

### Phase 5 — Contextual chat

| ID | Ticket | Spec | Tier | Status | Depends on |
|---|---|---|---|---|---|
| MAX-048 | Deterministic duplicate resolution for `ChatThreadRecord` | D6, A1 | Sonnet | 🔲 | MAX-020 |
| MAX-050 | Per-workout thread persistence | D6, FR-2.3 | Sonnet | ✅ | MAX-020 |
| MAX-051 | Chat UI with token-streaming reveal | FR-2.1–2.4, D10 | Sonnet | 🔲 | MAX-024, MAX-041, MAX-050 |

**MAX-050 was already built when it was dispatched, and that is a tracker failure, not
an agent one.** `ChatThread`/`ChatMessage` shipped with MAX-010, the
`ChatThreadRepository` protocol and `StoredChatThread` payload with MAX-020, and the
CloudKit-safe `ChatThreadRecord` plus its `MaximizeStore` conformance with MAX-020/021.
Every constraint the ticket listed — schema shape, thread identity keyed on the workout,
durable explicit ordering — was already satisfied on `main`. This board said 🔲 because
nobody re-derived it after those three merged.

The agent read the path first, found the work done, verified it was not a stale-worktree
artifact by rebasing onto the true `origin/main` and confirming the files were identical,
and reported that instead of rebuilding it. That is the behaviour the briefs ask for and
it is worth naming.

**The real gap it did close** is that the "one thread per workout" invariant lived only
in `MaximizeStore.swift` — App-layer code CI never executes, because this pipeline has no
simulator or device run. A `FakeChatThreadRepository` plus protocol-contract tests now
pin that behaviour where CI can see it, and give MAX-051 a seam it can drive end-to-end
with no SwiftData.

**MAX-048 is a latent bug in merged MAX-020 code**, found by MAX-050 and reported rather
than fixed. `MaximizeStore.threadRecord(for:)` fetches without a sort or tiebreak, unlike
`workoutRecords(for:)`, which sorts by `ingestedAt` precisely so duplicate resolution is
deterministic (see the CloudKit-constraints section above). `ChatThreadRecord` has no
equivalent field, so two records for one workout — which a CloudKit sync race can
produce, since the schema cannot carry a uniqueness constraint — resolve to whichever
row the store happens to return first. The thread a user sees would depend on fetch
order. Fixing it means giving the record a tiebreak field and sorting on it, which is a
schema change and therefore its own ticket.

### Phase 6 — Dashboard

| ID | Ticket | Spec | Tier | Status | Depends on |
|---|---|---|---|---|---|
| MAX-060 | Interval selector: week / month / custom | FR-3.1 | Haiku | 🔲 | MAX-020 |
| MAX-061 | Score-colored calendar, type glyph, auto-converted rest days | FR-3.2, D4, D9, A6 | Sonnet | 🔲 | MAX-017, MAX-060, MAX-040 |
| MAX-062 | **Cross-run HR-drift overlay** on %-elapsed axis | FR-3.3, D5 | **Opus** | 🔲 | MAX-060, MAX-040, MAX-012 |
| MAX-063 | Summary tiles: mileage vs arc, effective days, streak, avg score | FR-3.4 | Haiku | 🔲 | MAX-017, MAX-060 |
| MAX-064 | Settings: rest-days-per-week, display/accessibility prefs | §8 | Haiku | ✅ | MAX-020 |
| MAX-049 | Settings screen writes to a stub, not the store | §8, D9 | Sonnet | 🔲 | MAX-064, MAX-020 |

**MAX-049 is a live bug in merged MAX-064 code**, found by MAX-063 and reported rather
than fixed. `App/RootTabView.swift` constructs `SettingsView()` with no arguments, so
its `settingsRepository` parameter falls to its default —
`DefaultSettingsRepository.shared`, a no-op stub whose `settings()` returns `.standard`
and whose `store(_:)` does nothing. Nothing on that screen reaches
`PersistenceComposition.store`.

So every setting silently fails to persist, and the symptom is a screen that looks like
it works: a picker moves, the value shows, and it is gone on relaunch. The rest-day
budget is the one that matters beyond the settings screen itself — D9's budget feeds
rest-day conversion, which colours the calendar (MAX-061) and shifts effective-days in
the tallies (MAX-017), so the whole app is running on `.standard` regardless of what the
athlete chose.

Worth noting what did *not* catch this. The architecture guard checks imports; the
colour guard checks literals; `swift test` covers `MaximizeCore`, and this is App-layer
wiring that CI compiles and never executes. It took an agent reading the call chain for
an unrelated ticket. That is the shape of the gap R2 describes, arriving in the most
boring way available — a defaulted parameter.

MAX-064 rewrites `SettingsView`, which MAX-022 left with two cosmetic rough edges to
clean up then: `isCheckingStatus` is dead state (set and unset inside one synchronous
function, so its branch never renders), and `enteredKey` is not cleared on the
`save()` failure path.

### Phase 7 — Hardening

| ID | Ticket | Spec | Tier | Status | Depends on |
|---|---|---|---|---|---|
| MAX-070 | Accessibility: Reduce Transparency / Increase Contrast degrade to solid chrome | FR-4.5 | Sonnet | ✅ | MAX-040 |
| MAX-071 | Scoring fixture suite: known-good runs → expected score bands | R7 | Sonnet | 🔲 | MAX-015 |
| MAX-072 | Security review: Keychain handling, data at rest, prompt minimization, distribution tripwire | §11, A5 | **Opus** 🔒 | 🔲 | MAX-023, MAX-024 |

### Deliberately not built

Live coaching · manual entry/editing · strength analysis · HealthKit writes · multi-user ·
nutrition · Claude on the dashboard tab · **any server component** (A1). PRD §3, §12.
Listed so nobody helpfully adds one.

---

## Sequencing

Critical path: **MAX-006 → MAX-010 → 011/012 → 013 → 014 → 015**. Scoring is the
product; every screen is a window onto it.

Two streams parallelize once MAX-006 and MAX-010 land: the pure core (Phase 1, no
device needed, fully testable) and the platform layer (Phase 2–3). Phase 1 should run
ahead — it has no external dependencies and it is where correctness is cheapest to
establish.

**MAX-062 (drift overlay) is the ticket that justifies the project** — PRD §13 says so
directly, and §5's "no other app can draw this" is the actual differentiator. It is
tiered Opus and must not be starved by polish on splits or the route map. PRD §13 names
scope discipline as the top execution risk, above any technical unknown.

## Gaps in the plan model

D1 says every threshold is versioned plan data, never a constant in code. Implementing
tickets have found four places the `Plan` record cannot yet express what the code needs.
None is urgent; all are the same shape, and they should land together as one plan-model
change rather than four.

| # | Gap | Found by | Consequence today |
|---|---|---|---|
| P1 | `Plan` cannot express the *shape* of classification rules, so four dimensionless ratios live in `WorkoutClassificationPolicy` | MAX-013 | Real D1 leak, but bounded: they are ratios, never a bpm, metre or minute, so changing the cap or arc still moves the thresholds. A `classification` block on a future plan version fixes it |
| P2 | Same, for the cap-anchored zone multipliers in `HeartRateZoneModel` | MAX-012 | As P1 |
| P3 | `Plan` records **no durations at all**, so the "too short to classify" floor can only be distance-based | MAX-013 | A mis-started treadmill run with HR but no distance is not caught and reaches the scorer. Wants `minimumSessionDuration` |
| P4 | `ScheduledSession` cannot express interval structure (e.g. 6×800m) | MAX-013 | The scorer sees "hard" but not the prescribed shape, so it cannot judge whether the session was executed as written |

Separately, `CalendarDay` lacks day/week arithmetic — MAX-013 carried a private day
number to work around it. **MAX-011 owns that** now (`CalendarDayArithmetic`).

## Why the HealthKit anchor must never share a store with workouts

Recording this at length because the tracker previously said the opposite, and the
opposite is a data-loss bug rather than a missed optimisation.

An `HKQueryAnchor` is a position in **one device's** HealthKit change history. The
workout store is CloudKit-mirrored (A1, D6). Put the anchor in that store and it syncs
— so a second device picks up the first device's anchor and resumes *past* workouts it
never ingested. They are skipped silently and permanently, which is precisely the
failure the whole anchored design exists to prevent, arrived at through the back door.

The obvious escape does not help either: a second `ModelConfiguration` with
`cloudKitDatabase: .none` is a separate store file, hence a separate transaction, so it
would not close R12 anyway.

**The two stores are required, not incidental.** `FileWorkoutQueryAnchorStore` stays
where it is. R12's crash window is the accepted cost of that, and it fails to the safe
side: a re-delivered batch is absorbed by dedupe.

Found by MAX-020, which was explicitly told to close R12 and correctly declined.

## Constraints CloudKit imposes on the schema

Verified against Apple's documentation at MAX-020, and binding on **MAX-021**:

- **`@Attribute(.unique)` is unsupported.** So FR-0.5's dedupe on `workoutUUID` cannot
  be a schema constraint. It is a write-path invariant at a single upsert chokepoint,
  and reads tolerate a duplicate, resolving deterministically by oldest `ingestedAt`.
  The realistic path to a duplicate is two devices ingesting the same workout before
  either syncs — second-device setup, not an exotic case.
- Relationships must be optional and have an inverse; Deny delete is unsupported.
  MAX-020 dropped SwiftData relationships in favour of `workoutUUID` keys and pays for
  cascade delete with an enum the delete path switches over exhaustively, so a future
  per-workout record type cannot compile without handling deletion.
- **A promoted CloudKit schema is additive only** — after promotion you may add record
  types and fields, but never rename, retype or delete. MAX-021 must get the schema
  right *before* promoting it.

## Calling conventions a type cannot enforce

Obligations that live in a caller rather than in a signature. Each was found by the
ticket that could not close it, and each fails quietly rather than loudly.

| # | Obligation | Why the type can't enforce it |
|---|---|---|
| C1 | **Always resolve rest-day budgets over whole Monday-first weeks — never split one week across two calls.** | `RestDayBudgeting` (MAX-016) is a pure function over the days it is handed. Ranking is relative to the misses in a week, so the same day can rank differently in two partial slices of that week. A function taking a day-set cannot tell a partial week from a short one |
| C2 | **A `WorkoutIngestionSink` must not return before its write is durable.** | MAX-031's no-retry guarantee depends on it: acknowledging a wake whose data was not durably stored loses the workout permanently, and only the implementation knows when its write has landed |

## Open questions

| # | Question | Blocks | Status |
|---|---|---|---|
| Q1 | Accent color for the on-plan/effective state (PRD §14.2) | — | **Owner's call, open.** A placeholder violet `#8E7CFF` is in place — chosen to sit far from green/amber/red and from iOS system blue, ~5.9:1 on dark. Change the single `Color.accent` declaration in `ColorTokens.swift` to re-theme |

Resolved: backend architecture (→ A1, on-device) · existing-code question (greenfield) ·
rest-day conversion (→ A6, automatic) · **Q2 Xcode 26 availability** — yes, verified
against `actions/runner-images` at MAX-006; `macos-26` has been GA since 2026-02-26
and CI selects a 26.x toolchain explicitly rather than trusting the runner default.

## Risks

| # | Item | Impact | Status |
|---|---|---|---|
| R1 | No Swift toolchain in the dev container; `download.swift.org` blocked | CI is the only gate | Accepted — mitigated by fat-core architecture + macOS CI |
| R2 | No device/simulator in the loop | HealthKit flows, UI, on-device performance unverified until a human checks | Accepted per direction. PRs must list what needs device verification |
| R3 | Anthropic key on-device | Weakens PRD §6 | Accepted for single-user (A5). **Tripwire: blocks any distribution** |
| R5 | HealthKit background-delivery entitlement key | Wrong key means the wake silently never fires | **Resolved** at MAX-030 — `com.apple.developer.healthkit.background-delivery` confirmed against Apple docs; the PRD's guess was right. Base HealthKit entitlement and `NSHealthShareUsageDescription` also in place; all three fail the same silent way |
| R6 | Scoring correctness; auto-vs-manual divergence is the quality signal | Loop loses trust fast if scores disagree with judgment | D8 telemetry + MAX-071 fixtures; revisit rubric after real runs |
| R7 | Claude's *judgment* can't be unit-tested, only the rubric plumbing | Scoring regressions could pass CI green | MAX-071: fixture runs with known-good expected bands |
| R8 | Background-delivery wake windows are short; scoring makes a network call | Scoring may not finish in the wake window (PRD §2 p50 < 2 min) | MAX-033 to score lazily on first view if the wake budget is exceeded. Compounded: MAX-030 notes `.immediate` frequency is a *request* iOS may clamp, so the p50 target has a second uncontrolled factor |
| **R9** | **MAX-030 acknowledges every background wake, including failed ones — so iOS never retries.** This is only safe because a missed wake is recovered by the next anchored fetch | If MAX-031 lands a fetch that is not anchored or not idempotent, missed workouts are lost permanently and silently | **Constraint on MAX-031, not a risk to monitor.** The reasoning is documented in `WorkoutObservationCoordinator`; if the anchor guarantee changes, that decision must be revisited |
| **R11** | **A permanently unacceptable workout wedges the whole pipeline.** If the sink throws deterministically for one workout, the anchor never advances past it, so it is refetched and rethrown on every pass forever — and every later workout queues behind it | Zero-touch capture stops entirely, and the symptom is silence | **MAX-033 must handle this.** Found by MAX-031, which deliberately did not build a poison-pill escape: "give up on this workout" is a data decision belonging to whoever owns the store. The obligation is documented on `WorkoutIngestionSink` |
| R12 | The anchor write and the workout write are two separate stores, so the window between them exists by construction | A crash between them re-delivers the batch — absorbed by dedupe, so this is the safe side | **Accepted permanently. Do not "fix" this.** ~~MAX-020 can close it by moving the anchor into the same SwiftData transaction~~ — that earlier note was wrong and MAX-020 correctly refused it. See below |
| R10 | The app cannot know whether Health *read* access was granted — `authorizationStatus(for:)` reports share status only, by Apple's design | No UI can honestly display "Health connected"; a permission problem is indistinguishable from "no workouts recorded yet" | Accepted, Apple-imposed. Found at MAX-030. Any future settings or onboarding UI must not claim read access it cannot verify |

## Decision log

| Date | Decision | Rationale |
|---|---|---|
| 2026-08-04 | Logic lives in `MaximizeCore`; app target is a thin shell | Only way to get meaningful automated verification without Xcode in the loop |
| 2026-08-04 | CI on `macos-15` is the merge gate | Compiles the real toolchain; verified running tests, not a no-op check |
| 2026-08-04 | Do not block development on local Xcode runs | Per direction — tests are the gate; device issues handled when they surface |
| 2026-08-04 | CI mechanically rejects platform imports in the core | An architecture rule that isn't enforced is a suggestion |
| 2026-08-04 | `Package.resolved` is committed, not ignored | Ships an app, not a library — CI and dev machines must resolve identical versions |
| 2026-08-04 | **No backend; fully on-device** (A1) | Backend existed to keep the API key off-device; that buys little for a single-user app that is never distributed. Deletes a whole stack and makes the critical logic CI-testable |
| 2026-08-04 | API key in Keychain, with a distribution tripwire (A5) | Accepted cost of A1 — bounded by "never shipped to anyone else" |
| 2026-08-04 | Rest-day conversion is automatic (A6) | Consistent with the zero-touch north star; a conversion tap is the bookkeeping the product exists to remove |
| 2026-08-04 | PRD preserved verbatim; deltas recorded in a separate amendments file | Keeps the original reasoning legible and the deviations reviewable |
| 2026-08-04 | Xcode project generated from a checked-in XcodeGen `project.yml`; the `.xcodeproj` is gitignored | A hand-maintained `.xcodeproj` is an unreviewable blob; this repo's verification story depends on changes being readable in a diff |
| 2026-08-04 | CI selects Xcode 26 explicitly and fails loudly if absent | A silent fallback to an older SDK would build a non-Liquid-Glass app that still passes CI — the worst failure mode, because it looks green |
| 2026-08-04 | **iOS 26.0 deployment floor** — no back-compatibility to earlier iOS | PRD §7.4 is written around iOS 26 Liquid Glass. Supporting iOS 17+ with conditional enhancement would roughly double the design surface for zero benefit: this is a single-user app and the user controls the only device it runs on |
| 2026-08-04 | Bundle ID `com.example.maximize.app` is a deliberate placeholder | Must be replaced before any signed build; flagged in `project.yml` rather than inventing something that looks official |
| 2026-08-04 | `Security` added to the CI banned-import list for the core | MAX-022 put the key protocol in the core and Keychain in the app layer. Without the guard, a later ticket could call `SecItemCopyMatching` directly in the core and quietly make key handling untestable again |
| 2026-08-04 | `ScoreBand` lives in the core, with no `init(score:)` | It is domain vocabulary — produced by the scorer, aggregated by tallies, persisted beside the immutable auto-score. A parallel app-layer copy would drift. Refusing `init(score:)` is D1: only the scorer, reading the plan version in effect on the workout's date, may turn a number into a band |
| 2026-08-04 | Glass-over-data asserts in debug, degrades to opaque in release | FR-4.2 exists because translucency destroys chart legibility. A release fallback means a user never sees the illegible version; the debug assert catches it during development. The rejected alternative — render it wrong so someone notices — trades a real user-facing defect for a diagnostic |
| 2026-08-04 | CI rejects raw color literals outside `ColorTokens.swift` | Suggested by MAX-040 against its own work: the design system is only worth having if views name meaning, not appearance. A palette erodes quietly — nothing breaks, the colors just stop agreeing |
| 2026-08-04 | Palette values live in `MaximizeCore` as `DesignPalette`; `ColorTokens` consumes them | MAX-070 needed the values reachable without UIKit to compute WCAG contrast in a unit test. Colors are not domain, so this is a deliberate exception — bought because it turns "is this readable" from a thing nobody in this pipeline can see into a thing CI checks every commit |
| 2026-08-04 | The color-literal guard now admits **no** exceptions in `App/` | Consequence of the above: `App/` is entirely literal-free, so any color value there is one escaping the contrast suite that guards it. Verified the tightened guard catches a literal planted in `ColorTokens.swift` itself |
| 2026-08-04 | `Score` stores its band and validates it against the stored threshold, but does not compute it | Storing follows D2 (compute once). Refusing to compute follows D1 (the threshold is versioned). Rejecting a band that contradicts its threshold costs nothing and makes an incoherent score unrepresentable; the marginal/ineffective split stays the scorer's judgement |
| 2026-08-04 | Rubric carries `marginalThreshold` alongside `effectiveThreshold` | Three bands need two cut points. Since `ScoreBand` cannot compute itself, something must supply them, and D1 says that is versioned plan data rather than a constant in the scorer |
| 2026-08-04 | **MAX-034**: `WorkoutIngestionPipeline.enrich` extracts and stores samples (HR series, route) before resolving the plan, not after | Fixed a permanent-data-loss bug: `enrich` previously returned before `WorkoutSampleExtractor.extract` ran whenever no plan governed the workout's day, so every run predating the athlete's first plan version kept no HR curve — and MAX-031's advancing anchor never revisited it. The curve is a fact about the run, not the plan; only derived metrics (§9, measured against the plan's cap) stay gated on plan coverage. `IngestionPipelineDiagnostic.storedWithoutPlan` now documents that samples are stored either way. Found in the same pass: `.workoutPredatesEveryPlan` can never be completed later — MAX-011's version/`effectiveFrom` ordering forbids a plan from ever back-dating earlier than one that already exists — unlike `.noPlanAuthored`, which the lazy path does complete once a first plan is authored |

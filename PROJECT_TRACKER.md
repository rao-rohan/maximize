# Maximize — Project Tracker

**Last updated:** 2026-08-05
**Status: every PRD ticket is merged.** FR-0 through FR-4 are built and CI-green; the
capture-to-score loop is confirmed working on a real iPhone. What remains is device
verification of the surfaces nobody has looked at yet, and the post-PRD backlog below.
**Spec:** [docs/PRD.md](./docs/PRD.md) + [docs/PRD-AMENDMENTS.md](./docs/PRD-AMENDMENTS.md) (amendments win)
**Architecture:** Fully on-device. No backend.
**Pipeline status:** 🟢 CI green — 700+ tests, core suite on Linux. **Capture-to-score loop closed (MAX-033), and verified on a real iPhone: background delivery woke the app, the anchored fetch ran, and captured workouts render.** Core build/test, architecture guard, colour-token guard, unsigned iOS Simulator app build.

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
| MAX-021 | CloudKit sync so history survives reinstall | D6, A1 | Sonnet | ✅ ⏸️ | MAX-020 |
| MAX-022 | Keychain-backed Anthropic key storage + settings entry point | A5, §11 | Sonnet 🔒 | ✅ | MAX-006 |
| MAX-023 | Claude client: scoring call | §10, §11 | Sonnet 🔒 | ✅ | MAX-022, MAX-015 |
| MAX-024 | Claude client: streaming chat transport | D10, FR-2.4 | **Opus** | ✅ | MAX-022, MAX-014 |

🔒 = requires `/security-review` before merge. ⏸️ = merged but switched off.

**MAX-021 is merged and inert (A8).** The app is signed with a free personal team,
which does not grant the iCloud entitlements, so requesting them made the device build
unsignable — and the device build is the only one that can exercise zero-touch capture,
since the Simulator cannot run HealthKit background delivery. The entitlements are out
of `project.yml` and `makeOnDisk` now defaults to `cloudKitDatabase: .none`.

That default mattered more than it looks: `.automatic` against a build with no iCloud
entitlement fails container creation, which makes `PersistenceComposition.store` nil and
leaves the app running with **no storage at all** — capturing nothing while appearing to
work, because every failure on that path is deliberately survivable.

The code and the schema constraints stay exactly as MAX-021 left them. Re-enabling is
the entitlements block plus that one default; nothing here needs rewriting when a paid
membership arrives. **D6 is downgraded in the meantime:** threads survive relaunch, not
reinstall.

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
| MAX-046 | Per-split pace breakdown: compute at ingestion, store, display | FR-1.5, D2 | **Opus** | ✅ | MAX-045, MAX-033 |
| MAX-047 | Make `AppSettings.distanceUnit` load-bearing, or delete it | FR-1.5, FR-4.5 | Sonnet | ✅ | MAX-045 |

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
| MAX-048 | Deterministic duplicate resolution for `ChatThreadRecord` | D6, A1 | Sonnet | ✅ | MAX-020 |
| MAX-050 | Per-workout thread persistence | D6, FR-2.3 | Sonnet | ✅ | MAX-020 |
| MAX-051 | Chat UI with token-streaming reveal | FR-2.1–2.4, D10 | Sonnet | ✅ | MAX-024, MAX-041, MAX-050 |

**Chat is unavailable until a workout is scored, and that is a decision, not a gap.**
`WorkoutContextBuilder` needs a `WorkoutClassification`, which exists only as a stored
decision on `Score.actualClassification` (D2 — computed once by the scorer, never
re-derived). Re-classifying inside the chat model would be a second place that judgement
is made, which is exactly the drift D2 and D3 exist to prevent. An unscored run therefore
renders `.notYetScored` — an ordinary state with its own copy, not a failure and not a
disabled composer. In practice the wait is short: `WorkoutDetailView` already triggers
R8's lazy scoring before the chat section renders.

**The seed context is not stored as a `.system` thread message**, though `ChatRole` and
`ChatThread.visibleMessages` would allow it. `factSheet()` is re-rendered fresh on every
turn from the context built once per load — a pure function of immutable inputs — rather
than persisted as a second copy that could drift from the builder's output.

**`@Observable` compiles in the core.** MAX-051 is the first file in `MaximizeCore` to
`import Observation`, and the core job now builds on Linux rather than macOS, so this was
genuinely unverified when the PR opened — the agent flagged it as the first place to look
if CI went red. It went green. `Observation` is available cross-platform in `swift:6.0`,
and a core-resident view model is now a proven pattern rather than an assumed one.

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
| MAX-060 | Interval selector: week / month / custom | FR-3.1 | Sonnet | ✅ | MAX-020 |
| MAX-061 | Score-colored calendar, type glyph, auto-converted rest days | FR-3.2, D4, D9, A6 | Sonnet | ✅ | MAX-017, MAX-060, MAX-040 |
| MAX-062 | **Cross-run HR-drift overlay** on %-elapsed axis | FR-3.3, D5 | **Opus** | ✅ | MAX-060, MAX-040, MAX-012 |
| MAX-065 | Drift trendline over stored per-run figures | FR-3.3 | Sonnet | ✅ | MAX-062 |

**MAX-062 landed the overlay; MAX-065 is the half it reported rather than silently
dropping.** FR-3.3 says the drift comparison should *ideally* carry a trendline. That is
a second chart — one point per run, over `DerivedMetrics.heartRateDriftFraction` — not a
line fitted through the normalised curves, and conflating the two would produce a
trendline of a different quantity than the one labelled beside it. MAX-062 showed the
stored per-run figures in the legend instead and said so.

**Two MAX-062 decisions worth revisiting once it has been seen on a device**, neither a
defect:

- **Each normalised bucket is the time-weighted mean over its slice, not a point
  sample.** This is the one that makes the overlay honest: HealthKit sampling is
  irregular, so point sampling would make the drawn line a function of when the sensor
  fired rather than of the heart rate. A test pins it — the same ramp at 2 and at 11
  samples normalises identically. Do not "simplify" this.
- **Runs under 8m 20s (`bucketCount × 5s`) are excluded rather than stretched**, because
  a six-minute jog drawn at full width magnifies noise into apparent shape. Reversible in
  one constant if the exclusion turns out to hide runs worth seeing.

Also note the axis anchor: the %-elapsed axis spans the *curve's covered span*, not the
workout duration, because `heartRateDriftFraction` is defined over the covered span. Any
other anchor would put the 50% gridline at a different split from the one the number
beside it was computed at — D2's disagreement, drawn.
| MAX-063 | Summary tiles: mileage vs arc, effective days, streak, avg score | FR-3.4 | Sonnet | ✅ | MAX-017, MAX-060 |
| MAX-064 | Settings: rest-days-per-week, display/accessibility prefs | §8 | Haiku | ✅ | MAX-020 |
| MAX-049 | Settings screen writes to a stub, not the store | §8, D9 | Sonnet | ✅ | MAX-064, MAX-020 |

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
| MAX-071 | Scoring fixture suite: known-good runs → expected score bands | R7 | Sonnet | ✅ | MAX-015 |
| MAX-072 | Security review: Keychain handling, data at rest, prompt minimization, distribution tripwire | §11, A5 | **Opus** 🔒 | ✅ | MAX-023, MAX-024 |

### Phase 8 — Chat-first pivot (MAX-090, in flight)

MAX-090's product spec and amendments A9–A15 are drafted (`docs/CHAT-FIRST-SPEC.md`,
tracker branch `claude/max-090-chat-first-spec`) but **not yet merged to `main`** as of
this entry — this ticket's own branch could not see them and worked from the spec
content directly. Whoever merges MAX-090 should reconcile this row into that phase's
own table rather than leaving two entries for MAX-102.

| ID | Ticket | Spec | Tier | Status | Depends on |
|---|---|---|---|---|---|
| MAX-102 | Read-only plan screen, with version history, as its own tab | A15, CHAT-FIRST-SPEC §5 | Sonnet | ✅ | — |

**MAX-102 shipped as a tab, not a Dashboard push.** The spec's §5.3 recommended pushing
from the Dashboard's navigation bar; the owner changed this mid-ticket to a top-level
tab so the plan sits beside Workouts and Dashboard rather than a level under either.
`RootTabView.swift` is deliberately untouched — mounting the tab (suggested label
"Plan", SF Symbol `list.bullet.clipboard`) is left to whichever ticket owns the tab bar,
to avoid three tickets converging on that one file. The spec also described the screen
as read-only with no path to editing; the owner added one mid-ticket — an "Author a
revision" affordance that hands off to the existing `PlanAuthoringView` (MAX-080) rather
than editing in place, keeping D1's single door intact. See the PR for the full
rationale on both changes.

`PlanDisplayData` (new, `Sources/MaximizeCore/Plan/PlanDisplayData.swift`) is the
prepared value: version labelling, current-vs-historical, the arc's current week, and
the no-plan-authored case, all under test (`PlanDisplayDataTests.swift`). The app layer
(`App/Plan/PlanView.swift`, `PlanVersionDetailView.swift`, `PlanViewModel.swift`,
`PlanFormatting.swift`, `PlanDetailSections.swift`) only lays those values out — CI
compiles it but does not run it; see the PR's **Needs device verification** section.

### Deliberately not built

Live coaching · **manual entry/editing** · ~~strength analysis~~ · HealthKit writes ·
multi-user · nutrition · ~~Claude on the dashboard tab~~ · **any server component** (A1).
PRD §3, §12. Listed so nobody helpfully adds one.

**Strength analysis is struck, on purpose (A16).** The owner asked that plans account for
lifting goals as well as running goals, and MAX-109 spends the non-goal deliberately rather
than letting it arrive as a side effect of somebody adding a `.lift` case. The spend is
narrow: PRD §3 protects strength *analysis* and manual entry in the same breath, and
**only the first is spent**. Manual entry is now bolded above because A20 reaffirms it
against exactly the pressure A16 creates — HealthKit carries no sets, reps or load, so
"lifting needs volume tracking" is the obvious next request and it is refused on A20's
authority, not admitted on A16's.

**Claude on the dashboard tab is struck, on purpose (A10).** The chat-first pivot puts a
persistent Ask button on every screen, and on the dashboard it opens a thread about an
interval of training — which *is* the deferred `summarize my month` feature. It is
superseded on the record rather than allowed to arrive as a side effect of where a button
was placed, because that is exactly the failure this list exists to catch. The rest of the
list stands, and **live coaching in particular is now load-bearing**: A14 makes "no
unattended chat call" an invariant, so a proactive coach is not a small extension of the
chat work but a decision against a written rule.

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
| P3 | ~~`Plan` records **no durations at all**~~ **Closed by MAX-131**: `ScheduledSession.durationSeconds` is the plan's first duration, and `RubricReference.scheduledDuration(fraction:)` is how a band names it | MAX-013 | The rubric half is closed. **The classifier half is not**: `WorkoutClassifier.isFragment` still tests distance only, so a mis-started treadmill run with HR but no distance still reaches the scorer. The plan can now express the floor it wants — a `minimumSessionDuration`, or the ask's own duration — and the ticket that changes the classifier is a behaviour change nobody has picked up |
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
| C3 | **A caller that knows what day it is must tell `RestDayBudgeting`, via `outcomesUnknownFrom`.** | MAX-105. Forgiving a day that has not happened spends a small weekly budget on a non-event and leaves a real miss earlier in the same week unforgiven — but `RestDayBudgeting` is a pure function of the days it is handed, and a day-set carries no clock. `ScoreCalendar` and `TalliesCalculator` (MAX-110) both pass it now |

## Open questions

| # | Question | Blocks | Status |
|---|---|---|---|
| Q1 | Accent color for the on-plan/effective state (PRD §14.2) | — | **Owner's call, open.** A placeholder violet `#8E7CFF` is in place — chosen to sit far from green/amber/red and from iOS system blue, ~5.9:1 on dark. Change the single `Color.accent` declaration in `ColorTokens.swift` to re-theme |

Resolved: backend architecture (→ A1, on-device) · existing-code question (greenfield) ·
rest-day conversion (→ A6, automatic) · **Q2 Xcode 26 availability** — yes, verified
against `actions/runner-images` at MAX-006; `macos-26` has been GA since 2026-02-26
and CI selects a 26.x toolchain explicitly rather than trusting the runner default.

## Post-PRD backlog

Every ticket tracing to the PRD as written is merged. Most of what follows came out of
the work itself — reported by the agents that found them rather than fixed in place, per
the standing instruction. Two other sources appear here now that the app runs on a phone:
**the owner**, reporting from the device or asking for a change of direction, and **the
overseer**, where decomposition missed something the PRD implied but never spelled out
(MAX-080 is the clearest case — nothing in the app ever wrote a plan, so every downstream
feature was governed by a plan that could not exist).

| ID | Ticket | Source | Tier |
|---|---|---|---|
| MAX-066 | Treadmill splits from a distance-sample series | MAX-046 | Sonnet ✅ |
| MAX-067 | Backfill splits for runs ingested before MAX-046 | MAX-046 | Sonnet ✅ |
| MAX-068 | Decide whether splits enter the Claude prompt | MAX-046 | **Opus** 🔒 ✅ |
| MAX-069 | Extend file protection over Core Data's external-storage directory | MAX-072 R1 | Sonnet 🔒 ✅ |
| MAX-080 | Plan authoring — seed a plan, revise as a new version | Overseer, D1 gap | **Opus** ✅ |
| MAX-081 | Move Settings out of the tab bar; fix keyboard handling | Device report | Sonnet ✅ |
| MAX-082 | Design review of the whole app | Device report | **Opus** ✅ |
| MAX-083 | Week / month / year intervals, each with a fitting representation | Owner | **Opus** ✅ |
| MAX-084 | Fix score-band and chart contrast; resolve A7 | MAX-082 | Sonnet ✅ |
| MAX-085 | **The tab bar, once**: Plan becomes a third tab, iOS 26 `Tab` builder, `.tint()`, surface elevation, Liquid Glass chrome | MAX-082, Owner | **Opus** ✅ |
| MAX-086 | Wire `AppearancePreference` — a setting that silently does nothing | MAX-082 | Sonnet ✅ |
| MAX-087 | A non-hue channel for the year heatmap's 6pt cells | MAX-084 | Sonnet ✅ |
| MAX-127 | **Widen the surface fill ramp and re-tune the chart palette against it, together** — the finding MAX-085 left | MAX-085 | Sonnet ✅ |
| MAX-105 | **The plan on the dashboard calendar** — scheduled beneath actual | Owner | **Opus** ✅ |
| MAX-106 | The UI standard, written into `CLAUDE.md` | Owner | Sonnet ✅ |
| MAX-107 | Chat stream framing: close a frame without a blank line | Device report | Sonnet 🔒 ✅ |
| MAX-108 | Tap a calendar day → its workouts; swipe between two on one day | Owner | Sonnet ✅ |
| MAX-109 | **Plans cover lifting as well as running** — spec first | Owner | **Opus** ✅ |
| MAX-110 | **Tallies count future scheduled days as missed** — the streak tile reads 0 for most of every month | MAX-105 | Sonnet ✅ |
| MAX-111 | **Stop scoring lifts against the running rubric** — stop-gap ahead of MAX-109 | MAX-109 (spec) | Sonnet ✅ |
| MAX-090 | Chat-first product spec: plan generation and Q&A through chat | Owner | **Opus** 🔒 ✅ |
| MAX-091 | Run both Claude clients on the Sonnet tier at `medium` effort | Owner, cost | Sonnet 🔒 ✅ |
| MAX-092 … MAX-104 | The chat-first build, decomposed from MAX-090 | MAX-090 | see below ✅ |
| MAX-109 | Lifting product spec: plans account for lifting and running | Owner | **Opus** ✅ |
| MAX-128 … MAX-143 | The lifting build, decomposed from MAX-109 | MAX-109 | see below ✅ |
| MAX-126 | **"No verdict by design" is a state** — a lift stops being drawn and spoken as a run awaiting a score | MAX-111 | **Opus** ✅ |

**MAX-066.** Splits currently need a GPS track, so a treadmill run has none — correctly
rendered as an absence rather than fabricated. `distanceWalkingRunning` is already
authorised, and a distance *sample series* would give an indoor run a real
time-against-distance relation. It needs a new `WorkoutSampleFetching` requirement, an
extractor path and a HealthKit adapter, which is why MAX-046 reported it instead.

**MAX-067.** Every run already on the device predates MAX-046 and shows "no splits
recorded". A backfill does not fall out for free: `completeIngestion(forWorkout:)`
returns immediately for any workout that already has a score, which all of them do. The
ticket has to decide whether re-running enrichment is compatible with D8's immutable
auto-score, and whether it runs in the foreground or on demand.

**MAX-068 is the one worth thinking about.** Splits are stored but do not enter the
Claude prompt — `WorkoutContextBuilder` and `WorkoutFactSheet` are unchanged. FR-2's own
worked example is *"why did my HR drift at mile 3"*, which is a question the model
currently cannot answer well, because the fact sheet has no per-split structure to ground
it in. Adding them is a D3 decision about what Claude sees, so it belongs to whoever owns
the context builder and gets a `/security-review` — more data in a prompt is more health
data leaving the device.

**MAX-069.** From the security review's R1. Three `.externalStorage` blobs — the HR curve,
the GPS track and the chat transcript — are protected by the *directory* attribute set in
`prepareStoreURL`, not by `applyFileProtection`'s explicit list. The bytes are protected
today; the gap is that a future edit removing the directory attribute as redundant would
silently uncover them. Belt-and-braces parity means walking Core Data's support
directory, which depends on an implementation detail and should be verified on a device.

**MAX-081.** From the owner, off the device, and the first ticket sourced that way rather
than from another agent. Two chrome changes. Settings gave up its tab for a toolbar
button present on both remaining tabs — `settingsToolbarItem()` — and `DashboardView`
grew the `NavigationStack` it needed to have a bar at all. The keyboard half found four
distinct defects behind "the keyboard is very buggy": no dismiss affordance anywhere in
the app; a chat composer nested inside the detail screen's outer `ScrollView`, where
keyboard avoidance, a growing field and streaming text all fought over one scroll offset;
`.onSubmit` on an `axis: .vertical` field, which never fires; and a composer disabled
while streaming, which silently resigned focus and dropped the keyboard on every send.
Chat moved to its own sheet with the composer as a bottom `safeAreaInset`. **None of it
is verified** — CI has no simulator and cannot observe an interaction; see the PR's device
list.

**MAX-087.** The design review's T6, and MAX-084's own doc comments predicted it: the
corner pip MAX-084 added to close `.effective`/`.marginal` at 1.02:1 needs a cell large
enough to hold a corner, and the year heatmap's mark is ~6pt with a ~1.5pt gap to its
neighbour — no corner to spare. `ScoreBand.heatmapMark` (new, beside `ScoreBand.mark` in
`Sources/MaximizeCore/Accessibility/`) gives each band a size instead of a shape: a
scored day's fill draws at a fraction of the mark's footprint rather than always edge to
edge, `.effective` full, `.marginal` and `.ineffective` progressively smaller. Chosen
over a lightness/saturation channel because that one is a colour value and Increase
Contrast is specifically the thing this ticket has to survive; chosen over a shape
channel (rounded square vs. circle) because a corner-radius difference is expected to
erode faster than an area difference once anti-aliasing gets involved at this size —
though nobody working the ticket had a device to confirm either judgement.
`WCAGContrastTests.testNoTwoScoreBandsAreDistinguishedByHueAlone` was extended, not
duplicated: it now checks both `ScoreBandMark` (day grid) and `ScoreBandHeatmapMark`
(year heatmap) as two representations of the same rule. **Needs device verification** —
see the PR: whether a ~2.4pt inset mark actually reads as smaller rather than as noise
is the one thing here only a phone can answer.

**MAX-107 — the chat stream's framing. Merged, and it was a real bug.** From the device:
chat failed on every turn with *"The response was not a recognizable streaming reply"*. A
transcript captured against the live API showed the request and the stream were both fine,
which located the fault in how the app reads the socket rather than in what it sends.

The decoder closed a frame only on a blank line. SSE does specify that — but
`URLSession.AsyncBytes.lines` is a line sequence, not an SSE parser, and makes no promise
to deliver the blank separators. Without them every payload accumulated into one buffer,
and several JSON objects separated by newlines is not a JSON object. Every turn, every
model. **It predates the tier change and was not caused by it.**

**The reason the suite could not catch it is the part worth keeping.** Every existing
decoder test built its frames through a helper that appended the blank line itself, so the
decoder was only ever asked to parse input that already carried the boundary it depended
on. The fake transport and the real one disagreed on exactly one property, and only the
fake was ever tested. CI never opens a socket, so nothing mechanical could see it. Where a
test constructs the input a real adapter would produce, that construction is part of the
contract and deserves the same scrutiny as the code.

**MAX-108 — the calendar's days should be doors. Shipped.** From the owner. Tapping a day in
the week or month view goes to that day's workouts; where a day holds two, a swipe moves
between them rather than making the athlete go back and re-enter. Blocked until MAX-105
landed, since both are in `ScoreCalendarView.swift`; now dispatchable. The two-workout case
is the interesting half — a day with two runs is exactly the day you most want to compare,
and back-out-and-re-enter is what makes comparison not worth doing. A day with **no**
workout still needs an answer rather than a dead tap.

**Which days are doors is a core decision.** `ScoreCalendarDay.destination`
(`Sources/MaximizeCore/Dashboard/ScoreCalendar.swift`) is a new `ScoreCalendarDayDestination`
— `.workouts([UUID])`, `.notYetDue`, `.nothingRecorded` — resolved in `ScoreCalendar.resolve`
alongside `state` and `agreement`, and unit tested there rather than left for a view to
infer from `state`'s case. That distinction turned out to matter: five of
`ScoreCalendarDayState`'s cases share "nothing recorded" (`.missed`, `.convertedRest`,
`.scheduledRest`, `.forthcoming`, `.unplanned`), and only `.forthcoming` names its own
tense — `.scheduledRest` and `.unplanned` read identically whether the day is behind the
athlete or still ahead. `destination` is decided against `today` instead, independent of
which of the five a day landed in, so a future scheduled-rest or future-unplanned day
correctly reads `.notYetDue` rather than a dead end. New tests pin both directions for
each ambiguous state, plus the ordinary one/two/three-workout cases.

**The transition.** `App/Dashboard/ScoreCalendarView.swift` turns the core's decision into
one of three things, all sharing the exact cell visual MAX-105/MAX-084/MAX-087 already
drew — no restyling, per the brief: a single workout pushes `WorkoutDetailView` directly on
`DashboardView`'s existing `NavigationStack` (registered via a `ScoreCalendarDoorRoute`
`navigationDestination` declared beside the cells, so `DashboardView.swift` — and, per the
brief, `RootTabView.swift`, which MAX-085 now owns — needed no changes at all); two or more
pushes the new `App/Workouts/DayWorkoutsView.swift`, a `TabView(.page)` over
`WorkoutDetailView` with explicit previous/next buttons in a `.bottomBar` toolbar group (not
the swipe alone — the accessibility brief requires the move be reachable without a gesture)
and no page dots, since the "N of M" numeral already carries that; an empty destination
shows a `.alert` carrying the *exact* sentence `ScoreCalendarFormatting.accessibilityLabel`
already speaks to VoiceOver, so a sighted tap and a VoiceOver swipe learn the same fact
instead of the tap reading as broken.

**Every day-grid cell is a real `Button`/`NavigationLink` now**, `.buttonStyle(.plain)` to
keep the default press/tint chrome from leaking onto MAX-105's fill and ring, with a
`LayoutMetrics.minimumTapTarget` (44pt, Apple's own minimum) floored via
`.frame(minWidth:minHeight:)` + `.contentShape` — sized independently of the drawn cell so a
future ticket that shrinks the visual square still clears 44pt without this one having grown
it. The year heatmap is explicitly untouched — its ~6pt marks are nowhere near a real tap
target, and pretending otherwise would be worse than leaving it read-only, per the brief.

**Needs device verification**, and the PR leads with it: the two-workout swipe (both the
physical gesture and the previous/next buttons), the empty-day alert's wording, and a
VoiceOver pass over a one-workout day, a two-workout day, and each of the three
no-workout states.

**MAX-109 — plans cover lifting as well as running. Spec first.** From the owner, and
bigger than one sentence suggests: §10.2's classification reads a heart-rate profile
against pace, the derived metrics are drift, cadence and grade-adjusted pace, the plan
prescribes a **distance** arc, and the rubric scores against a distance and an HR cap. A
lifting session has none of those. So it gets the MAX-090 treatment — an Opus spec that
answers the load-bearing questions before code moves, including the one that decides the
rest: **what is an *effective day* when the two disciplines disagree?** D9's rest-day
budget, the streak, and D4's day colour all need one answer.

**MAX-110 — the tallies still think the future is missed, and this one is visible today.**
Found by MAX-105 while fixing the calendar's half. `TalliesCalculator` has no notion of
`today`, so future scheduled days inflate the eligible-day count — and worse,
`Tallies.currentStreak` walks back from the interval's end and **breaks on the first future
scheduled day**. On the "this month" interval that means the streak tile reads **0 for most
of every month**. The calendar half is closed (C3); the tallies half needs `today` on
`TalliesInput` and changes numbers on a surface MAX-063 owns, which is why it was reported
rather than fixed in place.

**MAX-111 — lifts were being scored against the running rubric. Merged; it is a tourniquet,
not the lifting feature.** Nothing filtered non-runs out of the pipeline, so a strength
session was stored, enriched against the running HR cap, classified `.other` and then
**scored**. The mechanism is worth writing down because it is not obvious: `RubricEvaluator`
filters bands by the **scheduled** session kind and then tests their conditions against what
actually happened — deliberately, since that is how "ran hard on an easy day" works — so a
lift on an easy day inherited the `.easy` bands. `StandardPlanSeed`'s `easy.wellOverCap` has
one condition (average HR above cap + 8) and **none on what was performed**, which a lift
clears trivially: **20–45, "Well above the easy cap for the whole run."** On a day with no
matching band it fell to `fallback.recorded` at 40–69. **D8 made every one of them
permanent.** Separately, `DerivedMetricsCalculator.averageCadence` had no discipline gate, so
a lift stored a fabricated cadence and `WorkoutFactSheet` sent it to Claude as fact.

The fix is one predicate, `Workout.activityType.isRun`, applied at two points in the core —
the same predicate `WorkoutClassifier` already short-circuits on, deliberately not a second
notion of "is this a run". A non-run is left unscored through the pipeline's existing
first-class state, `.leftUnscored(reason: .workoutIsNotARun)`, which **returns** rather than
throws, so R11's poison pill cannot form and capture is untouched. Cadence, grade-adjusted
pace and distance splits are absent for a non-run — absent, never zero. Heart-rate readings
are kept: they are true measurements, and choosing a cap for lifting is a plan-model
question, not a metrics one.

**What a lift looks like on the dashboard now, and the honest gap.** The existing states
already say the right thing on the tallies: `TalliesCalculator` counts an unscored workout
toward `workoutDays` (the athlete showed up), drops it from **both** sides of
`EffectiveDayTally` (no verdict either way), and treats it as **neutral** in the streak —
neither extending nor breaking it. That is the honest answer and it needed no change. The
calendar renders it `.awaitingScore(activityType:)` with no agreement, which is honest about
today and **wrong about tomorrow**: "awaiting" means *not yet*, and for a lift it is now
*never*. Same for the detail view, which shows a spinner and "Scoring runs automatically once
the run is captured." Distinguishing "waiting" from "has no verdict by design" is a new state,
and **MAX-109's spec owns that decision** — reported, not invented. **Closed by MAX-126**,
below.

**MAX-126 — "no verdict by design" is now a state, and it cost the calendar nothing.**
MAX-111's escalation, taken. `ScoreCalendarDayState` gains `.noVerdict(activityType:)` and
`WorkoutVerdict.Scoring` gains `.noVerdict` (its `.unscored` is renamed `.awaitingScore`, so
the pair reads as the tense difference it is). Both split on `Workout.activityType.isRun` —
the same predicate the pipeline declines to score on, not a third notion of "is this a run".

**One state, not two.** "Not a run, so no rubric" and "a run whose rubric could not be
applied" are different facts, but `UnscoredReason` is a diagnostic that is deliberately never
stored, so the activity type is the only durable input either surface has — and a run left
unscored by `noBandMatched` is genuinely still waiting, because D1 makes a new band a new
plan version. `.awaitingScore` stays truthful for it.

**No new colour, and no new mark.** The two scoreless states can never carry the same
activity type, so the activity glyph the cell already draws separates them for free; a
lifting day is the same neutral fill every no-verdict day sits on, told apart the way
`.scheduledRest` and `.convertedRest` already are. MAX-084/MAX-087's contrast budget and
MAX-105's ring are untouched. On a day holding a run and a lift, **a pending answer outranks
a settled absence**: the day is `.awaitingScore`, because the cell really is about to change.
Whether an unmet *running* obligation should recolour such a day is LIFTING-SPEC §7.2's
roll-up — MAX-116/MAX-117's, and it needs the lifting plan model first.

**No stored score is touched** (D8): a lift ingested before MAX-111 still shows the band it
was given, and A21/MAX-125 remains the owner's call. The detail header drops the spinner and
says "Recorded, not scored — the plan scores runs, so there's no score for this workout."
The chat gate's "chat opens once it has a score" was a third false promise on the same path
and is fixed alongside.

**Reported by MAX-126, not fixed by it — the drift overlay says the same untrue thing.**
`DriftOverlayModel` does not pre-filter its candidates, so a lift in the selected interval
becomes a `HeartRateDriftOverlayData.Candidate`, is excluded as `.notYetScored`, and is
narrated under the chart as **"1 run isn't scored yet, so nothing has decided whether it was
an easy or long run."** Three things wrong in one sentence: it calls a lift a run, it implies
a score is coming, and it counts a session the overlay was never going to draw. The fix is
not a string — `HeartRateDriftOverlayData` and `DriftFigureSelection` each need an exclusion
reason and a note of their own, or the candidate set needs filtering before it reaches them,
and which of those is right is a product question about whether a lift should be *counted* as
an omission at all. Out of MAX-126's scope; needs a ticket.

**Scores already written for lifts are untouched and still on the device.** D8 is absolute
and the gate only stops new ones; correcting the existing ones is MAX-109's A21 and the owner
has not made that call.

**MAX-086 is split, and what remains is a real defect rather than polish.** It was filed
off the design review as "absence-string voice; wire `AppearancePreference`" — two
unrelated jobs sharing a row. The absence-voice half moves to **MAX-104**, because the new
chat and plan surfaces it should cover do not exist yet and doing that pass twice is worse
than doing it once, late.

What is left is not polish. `AppearancePreference` is a stored setting with three cases, a
working picker in Settings, and a persistence path — and **nothing in the app applies it**.
`.preferredColorScheme` occurs exactly twice in the codebase and both are previews in
`DesignSystemGallery.swift`. An athlete chooses Light, the value saves correctly, and the
app stays dark. That is worse than not offering the setting, because it reads as a bug in
the app rather than a missing feature — and it is the same class of failure as R13, where
app-layer wiring compiled fine and did nothing. Re-tiered to Sonnet: the mapping has to
express "impose nothing" for `.system` distinctly from picking a scheme, and the
preference has to take effect without a relaunch, which needs the existing settings
observation path rather than a second one.

**MAX-086 landed.** `MaximizeCore` gained `AppearancePreference.resolvedColorScheme:
ResolvedColorScheme?` — `.system` maps to `nil`, so it reads as "impose nothing," not as
a default the mapping quietly picked. `SettingsModel` gained a `.shared` instance;
`SettingsView` and `MaximizeApp` now read and write that one object instead of each
loading its own copy of `AppSettings`, so a save in the settings sheet is visible to the
app root immediately — no relaunch, and no second notion of "the current appearance" to
drift from the first. `MaximizeApp` is the sole place `ResolvedColorScheme?` becomes
`.preferredColorScheme`. Compiles and its unit tests pass; not verified on a device —
see the PR's "Needs device verification."

**MAX-106 — the UI standard, written into `CLAUDE.md`.** The owner set a bar for the
redesign; until this landed it lived only in individual agent briefs, so every ticket
depended on the overseer restating it. Rules that live in a dispatch message decay. The
section is deliberately concrete enough to review against — platform chrome, current
components, numerals doing the hierarchy work, accessibility as part of the ticket rather
than a follow-up, absence as a designed state, tokens for colour and spacing — and it ends
by saying none of it is verifiable by CI, which is what keeps the rest honest.

**MAX-085 is now the tab bar's only owner, and it is re-tiered to Opus.** It was filed off
the design review as chrome polish — surface elevation, `.tint()`, Liquid Glass. The owner
then asked for **the plan to become a tab**, and that lands in `App/RootTabView.swift`,
which design review T2 already wanted (the iOS 26 `Tab` builder, `.tint(.accent)`,
`.tabBarMinimizeBehavior`) and which MAX-098's persistent chat accessory needs after that.
Three tickets converging on one 28-line file is three conflicting diffs of it, so the file
gets one owner and does the work once.

The tier moved because the ticket is no longer polish. A tab bar is the app's claim about
what its parallel modes *are*, and MAX-081 already spent that reasoning once when it took
Settings **out** — settings is somewhere you go to change a thing and leave, not a mode. A
plan is the opposite: it is a place you look at, the reference every score on every other
screen is measured against, and today it is legible only while you are editing it. It earns
the slot on the same argument that denied Settings one, which is the sort of decision worth
making deliberately rather than as a side effect of a `Tab` being easy to add.

MAX-102 delivers the tab's *content* as a tab root and is explicitly barred from
`RootTabView.swift`; MAX-085 mounts it. Sequence: 102 → 085 → 098.

**MAX-085 landed.** Four things, and one of them is a finding rather than a change.

- **`RootTab` is in the core** (`Sources/MaximizeCore/Navigation/RootTab.swift`), holding
  the order, labels and SF Symbols, with `RootTabTests` pinning them — including a test
  named for the fact that Settings is not a tab, so putting it back fails with MAX-081's
  reason attached. `RootTabView` is left with nothing to decide.
- **The bar is current.** iOS 26 `Tab` builder, `.tabBarMinimizeBehavior(.onScrollDown)`
  (all three tabs are long scrolling columns, so scrolling down should give the height
  back), and `.tint(.accent)` at the root — the one line that finally connects MAX-084's
  settled violet to everything the *system* draws. No `glassChrome(.tabBar)`: the system
  bar brings its own, and re-applying it is the mistake `SettingsToolbar` documents.
- **Cards have an edge.** New `surfaceBorder` token, hairline, on `ContentSurface.card`
  only — not tiles (a grid of outlines is a wire mesh), not insets (a second line 16pt
  inside the first). Increase Contrast strengthens it to a genuine 3:1 graphical object
  against the screen instead of flattening it.
- **The finding: the fill ramp cannot be widened by this ticket.** The design review's
  preferred fix (§2.1a, lift `surfaceElevated` and `surfaceInset`) is blocked, because
  `surfaceInset` is the surface every chart plots on and MAX-084 tuned every chart mark
  against it to within hundredths of its floor — `chartGridline` sits at 1.43:1 against a
  1.4 floor. Lifting the plot surface re-opens the whole chart palette, which is a chart
  ticket. The edge carries the boundary instead; the reasoning and the four measured
  values are in `DesignPalette.surfaceBorder`.

Nothing here is provable by CI, and the PR says so at length. The open device questions
are whether the bar reads as current-generation iOS, whether the violet looks right in
place rather than in a swatch, and whether an edged card next to an unedged tile grid
reads as deliberate or as unfinished.

**MAX-127 — the fill ramp, widened, and the chart palette re-tuned against it.** The
finding MAX-085 left on purpose: it could not widen `surfaceInset` without re-tuning
every chart mark plotted on it, and that was ruled out of a chrome ticket. This is the
ticket that does both together, because MAX-085's own invariant test
(`testACardSeparatesFromTheScreenBySomething`, "a card separates by its fill step *or*
its edge") only holds if the two land as one change.

- **The widen is real but smaller than MAX-085's `surfaceBorder` comment guessed.**
  `surfaceInset` carries `accent` and `textTertiary` at 4.5:1 against it — neither
  moved, the accent because A7 is settled and `textTertiary` because retuning it is a
  different ticket's call — and that turned out to bound the ramp much more tightly in
  **dark** than in light, the opposite of what the design review's §2.1(a) expected.
  `surfaceElevated` on `surface` moved from **1.09:1 to ~1.16:1** in both appearances;
  `DesignPalette.surfaceInset`'s doc comment carries the exact window and why it is
  asymmetric.
- **`chartGridline`, `chartExcursion` and `chartSeriesMuted` are re-tuned against the
  wider `surfaceInset`, with real margin above their floors this time** — MAX-084's
  values cleared 1.4:1 / 2.0:1 / 3.0:1 by hundredths, which is why they broke the
  moment the plot surface moved. The new values clear by at least 0.14–0.28:1 in every
  appearance, and a new test (`testChartGridlineAndExcursionClearTheirFloorsWithReal-
  Margin`) asserts the buffer itself, not just the floor, so a future edit can't
  quietly walk it back down.
- **`chartThreshold` moved too, though the ticket only named the other two.** Widening
  `surfaceInset` shrinks the room between it and the fixed cap-line colour that the
  "Cap N bpm" label needs 4.5:1 against, drawn directly over `chartExcursion`'s fill —
  there was no value of `chartExcursion` alone that cleared its own floor with margin
  *and* kept the label legible against a stationary `chartThreshold`. `DesignPalette.
  chartExcursion`'s comment carries the algebra.
- **`surfaceBorder` stays — it is not redundant.** The fill step alone (~1.16:1) is
  real but still short of Apple's own ~1.23:1 dark step, so the edge is still doing
  work, not resting on top of a solved problem. Its light value is retuned darker
  (`0xC9C9D3` → `0xBEBEC8`) because the wider `surfaceElevated` had pulled its margin
  down to the same "hundredths" problem the ramp itself had; dark is unchanged.
- **Found, not fixed: `CadenceBandView`'s target-band shading still writes
  `Color.chartThreshold.opacity(0.2)` at the call site** — the exact anti-pattern
  MAX-084 eliminated from `HRCurveView` via `chartExcursion`, just at a call site that
  ticket didn't touch. Unaffected by this ticket's `chartThreshold` retune (still
  measures better than before, checked by hand), but it remains an unmeasured literal
  and a candidate for the same treatment.

**Needs device verification**, same as MAX-085: whether cards now read as cards at a
glance, and — the risk unique to this ticket — whether the chart gridlines still read
as quiet on a visibly lighter plot surface rather than becoming noise.

**MAX-105 — the plan on the dashboard calendar.** The owner's ask, and the most interesting
design problem currently open, so it is Opus and it should be argued rather than assumed.

Today a calendar cell shows what *happened*: a date, a state glyph, and MAX-084's score-band
mark. The plan is what was *prescribed*. Putting both in a ~42pt cell without it turning to
mush is the whole ticket, and the shape most likely to be right is that **the plan is the
substrate and the actual is the mark on top of it** — you ran *against* a prescription, so
the prescription is the ground and the result is the figure. A cell then reads in one glance
as agreement or divergence, which is the question the calendar exists to answer and cannot
currently answer at all.

Two consequences that make this more than decoration:

- **Future days become meaningful for the first time.** The calendar today shows only the
  past, because a score is the only thing it draws. A plan tells you what is coming, so the
  same grid starts answering "what am I doing Thursday" — and the empty-vs-scheduled-vs-rest
  distinction on a future day is a new state that has to read as *not yet* rather than as
  *missed*. Getting that wrong turns the whole forward half of the month into failure.
- **D4 and MAX-084's rule both still bind.** The score still colours the day, and no two
  bands may be distinguished by hue alone. A plan layer that eats the contrast budget
  breaks a rule the project already paid to establish — and MAX-087 is spending that budget
  at the year span right now, so the two must be read together.

D1 and D2 are untouched: the plan layer reads the versioned record in effect on each day
through `PlanCalendar`, never a literal and never a recomputation.

**MAX-105 must not be dispatched until its brief carries MAX-109's §2.** A17 makes a day's
prescription **two** sessions — one per discipline — and a substrate designed around one
prescription is the wrong design for the hardest visual in the app. This is the single most
expensive collision on the board: either MAX-105 waits for MAX-111 and is designed once, or
MAX-117 redesigns a ~42pt cell whose contrast budget MAX-084 and MAX-087 already spent.
Sequence: **111 → 105 → 117**.

**Shipped. What it decided, and what it found.**

*The encoding.* The prescription is a ring at the cell's own edge (`Color.accent`, the
token already reserved for the on-plan state); the state fill is inset inside it. One bit
— asked, or not asked — so no legend is needed. A cell reads as ring + band (trained when
asked), ring + red × (asked, didn't), ring + nothing inside (asked, not yet due), or band
with no ring (trained off-plan, the divergence nothing previously showed). The ring never
touches a band fill, which is why it costs nothing from the contrast budget MAX-084 and
MAX-087 spent: `accent` on `surfaceElevated` is the only pairing it has to survive, and
`WCAGContrastTests` now pins it in all four appearances. **Not drawn at year density** —
`ScoreCalendarRepresentation.drawsThePlanLayer` carries that decision and the argument for
it, which is that a ring around a 6pt mark would be paid for out of MAX-087's channel.

*Kind-level divergence is modelled and spoken, not drawn.* `ScoreCalendarDay.agreement`
compares the prescription against `Score.actualClassification` — both already stored, so
no new reads and no re-derivation (D2) — and VoiceOver says "planned a long run; ran
easy". It is deliberately not a fourth visual distinction in a cell that already carries
three; the verdict header is where a single day's scheduled-versus-actual has room.

*The future/missed defect was real and was on the device.* `resolve` had no notion of
today, so the remainder of the current month rendered red. Fixed as a state
(`.forthcoming`) reached before `.missed` can be, not as a filter in a view — and
`today` is now a parameter, so the distinction is testable.

**The tallies still think the future is missed.** Found while fixing the calendar,
reported rather than fixed. `TalliesCalculator` has no `today`, so a future scheduled day
enters `EffectiveDayTally.eligibleCount` and drags the rate down, and worse,
`Tallies.currentStreak` walks back from `input.through` and breaks on the first future
scheduled day it meets — which for the "this month" interval is usually the 31st, so the
streak tile reads 0 for most of every month. The calendar half is closed by passing
`RestDayBudgeting`'s new `outcomesUnknownFrom` (now **C3**); the tallies half needs
`today` on `TalliesInput` and changes numbers on a surface MAX-063 owns. → **MAX-110**.

**MAX-110 closed the tallies half.** `TalliesInput` gained a required `today`
(never a clock read, matching `ScoreCalendar.resolve`'s own parameter), threaded into
both places that depend on whether a day's outcome is in yet: `effectiveDayTally` now
withholds any day on or after `today` from `eligibleCount`, and `resolveRestDayConversions`
passes `today` through as C3's `outcomesUnknownFrom`.

The streak walk's start point needed a real decision, and the first draft got only half
of it right. Walking back from `through` silently assumed `through` was decided, which
is false whenever it reaches into the future — but stopping the walk at `today - 1`
(the first draft's fix) is a *second*, smaller version of the same bug: it treats a
workout already run and scored *this morning* as absent until tomorrow. Review caught
it before merge. The asymmetry that was missing — **a miss is unknowable until the day
ends, but a hit is knowable the instant it happens** — is not new to this ticket;
`ScoreCalendar.resolve` already embodies it (a workout on `today` resolves to `.scored`,
checked before the forthcoming guard, never to `.forthcoming`). The walk now matches
that ordering instead of inventing a second rule: it visits `today` itself, an empty
`today` is neutral (the day might not be over), but a workout already recorded and
scored today extends or breaks the streak exactly like any other decided day. Tested at
all three interval shapes (wholly past, wholly future, spanning `today`) plus the two
`today`-specific cases (already a hit, already a below-threshold miss) that are the
direct regression tests for the two drafts' respective bugs. A test derives its
expected `EffectiveDayTally` from `ScoreCalendar.resolve`'s own output over the same
interval rather than a second hand-worked number, and a sibling test does the same for
the streak — both fail if the calendar and the tallies ever drift apart, even if either
suite's hardcoded numbers still happen to look right.

`TrendTilesModel` resolves `today` once at init, the same way `ScoreCalendarModel` does.


*Also noticed, not acted on.* `docs/DESIGN-REVIEW.md` §5.4 proposed "a 1pt accent ring on
the current day" for the missing today-marker. MAX-105 has spent exactly that device on
the plan, so whoever takes §5.4 needs a different one — and may not need one at all: the
boundary between filled cells and unfilled forthcoming ones now *is* today.

**MAX-091.** Both Claude clients moved from the Opus tier to the Sonnet tier at `medium`
effort, on the owner's cost instruction. Three things came with the model that are not
optional and are easy to get wrong later, so they are recorded here rather than only in
the diff:

- **Effort is nested.** It is `output_config: {"effort": "medium"}`, not a top-level
  request field, and it is an *output* control rather than a thinking budget — which is
  why both clients can keep `thinking: {"type": "disabled"}` alongside it. Disabling
  thinking is accepted only at `high` effort or below, so raising either client to
  `xhigh` or `max` without also deleting its `Thinking` block is a 400. Both files say so
  at the call site.
- **The cacheable minimum went up**, from 512 tokens on the previous tier to 1024 on this
  one. Neither client's system blocks reach it today, so both `cache_control` markers are
  currently inert — no error, no saving. They stay because a multi-workout context
  (MAX-090) plausibly crosses the line on its own.
- **The tokenizer produces roughly 30% more tokens** for the same text. The chat client's
  `max_tokens` went 2048 → 2560 to buy the same length of answer it was originally sized
  for; the scoring client's 512 was already far past what an integer and a 140-character
  rationale need, so it did not move.

**Not verified.** Neither client is exercised by CI — no toolchain, no key, and no network
request in the suite (see R1 and the files' own doc comments). What CI proves here is that
the app target still compiles. That the request shape is accepted, and that a Sonnet-tier
score is as good as an Opus-tier one, are both device checks against a real key.

**MAX-090** is the chat-first product spec, and it is **delivered**:
[`docs/CHAT-FIRST-SPEC.md`](./docs/CHAT-FIRST-SPEC.md) plus amendments **A9–A15**. Nothing
in it is built. Two constraints were settled by the owner up front and the spec did not
re-open them: the detailed dashboard and workout-detail screens **stay** — chat is additive
— and the subject a chat is opened with must be a structured value the core understands,
not a free-text hint, because a free-text hint would be a second unvalidated way of saying
what context to assemble, which D3 forbids.

The two decisions worth knowing without reading all of it:

- **D3 is generalised, not weakened.** One context module keeps one entry point,
  `build(for subject:)`, over a closed subject set. A training thread gets a **roll-up** —
  plan in effect, tallies, one line per run, scope stated — not a stack of fact sheets. No
  HR curves, no splits, no coordinates, no rationales. The rule with teeth is that every
  aggregate comes from the same core function the corresponding screen reads, with a test
  asserting a context and a tile agree over the same interval. Chat and a tile now describe
  the same number to the same person, so a divergence is a visible defect.
- **D1 is untouched.** The model emits a **proposal**, never a plan. It becomes a version
  only through `PlanAuthoringSession`, the door MAX-080 built. The near-miss to watch for
  in review is a helper that applies a proposal *and stores it*.

Its §11 proposed thirteen tickets as MAX-091–103; they are renumbered **MAX-092–104** here
and in the document, because MAX-091 was taken by the tier change that landed while the
spec was being written. MAX-101 (the read-only plan screen) is independent of the other
twelve and is dispatchable immediately.

| ID | Ticket | Depends on | Tier |
|---|---|---|---|
| MAX-092 | `ChatSubject` and thread identity | — | **Opus** ✅ |
| MAX-093 | The stored record: additive fields, no migration | 092 | Sonnet ✅ |
| MAX-094 | Shared fact-sheet formatting — pure extraction | — | Sonnet ✅ |
| MAX-095 | `TrainingContext` + one context entry point | 092, 094 | **Opus** 🔒 ✅ |
| MAX-096 | `ChatModel` generalised; transcript cap; training task text | 095 | **Opus** 🔒 ✅ |
| MAX-097 | Thread list, derived titles, new chat, scope subtitle | 093, 096 | Sonnet ✅ |
| MAX-098 | The persistent glass button | 097 | Sonnet ✅ |
| MAX-099 | `PlanProposal` — type, parse, schema derived from core enums | 095 | **Opus** 🔒 ✅ |
| MAX-100 | The Anthropic client for plan proposals | 099 | Sonnet 🔒 ✅ |
| MAX-101 | Conversational plan authoring; proposal card; handoff | 098, 100 | **Opus** ✅ |
| MAX-102 | **The read-only plan screen with version history** | — | Sonnet ✅ |
| MAX-103 | "Runs in this conversation" strip | 098 | Sonnet ✅ |
| MAX-104 | Copy and absence voice, **app-wide** — absorbs MAX-086's other half | 098, 102 | Sonnet |

Three collisions the spec calls out and the overseer must respect: **094 lands before 095**
(both touch `WorkoutFactSheet.swift`, and 094 is the extraction 095 builds on); **MAX-102
then MAX-085 then MAX-098**, the single owner chain for `RootTabView.swift`; **MAX-087
before MAX-105**, both being in the calendar's contrast budget; and — the original note —
**MAX-085
lands before 098** (both touch `RootTabView.swift`, and the button should be built against
the migrated tab bar rather than merged into it afterwards); and **102 before 101** (both
touch `App/Plan/`, and 102 is the smaller, independent one).

**MAX-092 landed the identity change.** `ChatThread` is keyed on its own `id` and carries
a `ChatSubject` — `.workout(UUID)` or `.training(TrainingScope)` — plus a
`lastActivityAt`. Four things are worth carrying forward:

- **Freezing is enforced by the type, not by a convention.** `TrainingScope` holds two
  `CalendarDay`s and its only door in from a `TrendInterval` is `init(resolving:)`. There
  is deliberately **no way back out**: nothing can hand you the interval a scope came
  from, because a caller holding one could re-resolve it (§3.4, A11).
- **MAX-048's determinism is preserved and promoted.** Its `(createdAt, threadUUID)` sort
  in `MaximizeStore` is untouched and still picks the same row. What changed is that
  "which thread does a subject resolve to" is now an explicit protocol contract —
  `mostRecentThread(for:)`, newest activity with the identifier breaking a tie — and
  `FakeChatThreadRepository` makes CI check it on every commit, which MAX-048's own
  version of the rule never was.
- **One thread per workout is now a repository policy, not a shape.** §12's question 3 is
  therefore reversible in one method, as the spec says it should be. Training subjects are
  deliberately not deduplicated: "New chat" over a newer window is the product.
- **It had to touch one App file, and that is a decomposition miss worth recording.**
  `MaximizeStore` conforms to `ChatThreadRepository`, so growing the protocol broke the
  `ios-app` job. The ticket said core-only; the alternative was a knowingly red merge
  gate. The change is the minimum that compiles — no column, no schema version, no
  migration — and MAX-093 replaces the two derivations it leans on. **The lesson for
  future decomposition: a ticket that grows a protocol owns every conformer of it, and
  the brief should say so.**

**MAX-095 landed the one context entry point, and with it the privacy boundary.**
`ContextBuilder.build(for:from:)` is now the only assembler of prompt context, returning a
`PromptContext` that is either the existing `WorkoutContext` or a new `TrainingContext`,
both rendered by `factSheet()`. `WorkoutContextBuilder` is untouched and is called *by* it,
so the scorer keeps receiving byte-identical context — pinned by a test that renders both
paths and compares the strings. Six things are worth carrying forward:

- **What now leaves the device that did not before.** A training turn sends the plan in
  effect, the tallies for the window, and one line per session: day, weekday, discipline,
  classification, the plan's ask for that day, distance, duration, average heart rate,
  drift, score and band. It sends **no** splits, **no** heart-rate curve, **no**
  coordinates, **no** scoring rationales and **no** workout identifiers, and
  `ContextBuilderTests.testTheRollUpCarriesNoSplitsNoCurveNoRouteAndNoRationale` asserts
  each of those rather than trusting them. That is a real widening of the privacy posture
  and is recorded as one (A12, §3.3).
- **§3.6(a)'s agreement property is a test, not a claim.** `TrainingContextAgreementTests`
  builds a `TrainingContext` and a `TrendTileData` from **one** set of stored records and
  asserts the tallies are identical and the rendered figures are the tiles' own strings —
  including the cases where both must agree about *absence* (nothing scored, nothing
  eligible) and about MAX-110's not-yet-known days. `TrainingContext` contains no
  arithmetic over more than one workout; the only number it derives is how many lines it
  holds.
- **One line per session, not per day** (LIFTING-SPEC §10.2), so a Tuesday holding a run
  and a lift produces two lines. A session with no score reads *"no verdict"* in words, and
  the wording distinguishes a run scoring has not reached from a non-run MAX-111 leaves
  unscored **by design**.
- **`maximumRenderedSessions = 200`, and it is reachable.** A week (~14) and a month (~62)
  cannot reach it; a year of running and lifting (~400) does. So an annual thread answers
  from the plan and the tallies, and the "state the count, list none" branch is a real
  product state rather than dead code. See the constant's own documentation for the
  argument.
- **The shared renderer grew two more formatters.** `weekdayName` and the scheduled-session
  formatter moved from `WorkoutFactSheet` into `FactSheetFormatting` the moment the roll-up
  became their second caller, and `FactSheetFormattingAgreementTests` gained the training
  renderer as one entry in its array. The scheduled-session formatter kept its `%.1f`
  deliberately: it is what the scorer's prompt has always printed, and D3 forbids changing
  that as a side effect.
- **`ContextInputs` inherits C1.** For a training subject its `records` must cover the whole
  Monday-first weeks touching the scope, because `TalliesCalculator` cannot widen the
  workouts it is handed. Supplying more is harmless — the session list filters to the scope
  itself rather than trusting the caller.

**Two things MAX-095 could not do, and neither is a defect in it.** The plan block renders
the whole stored `WeeklyTemplate`, so LIFTING-SPEC §10.2's requirement that it carry the
**lift slot** arrives for free the moment the template grows one (MAX-113/114) — there is
nothing to carry today. And the training thread's `ChatInstruction.task` text (§3.5) is
**MAX-096's**, not this ticket's; nothing here touches `Chat/`.

**MAX-099 landed the proposal boundary, and D1 is where it was.** `PlanProposal` is a
validated value describing a proposed plan — goals, weekly template, distance arc, HR cap,
cadence band — with `parse`, a derived `schemaDescription`, `PlanProposalInstruction` and
`PlanProposalModelInvoking`. Core-only, three new files under `Plan/`, nothing under `App/`.
Five things are worth carrying forward:

- **The proposal has no path to storage, and the near-miss A13 names has no half in this
  PR to be built from.** Nothing in the three files returns a `Plan`, builds a `PlanDraft`,
  or mentions a repository. `PlanDraft.applying(_:)` is deliberately **not** here; it is
  MAX-101's, and `PlanProposalTests` builds that mapping in *test* code precisely so this
  ticket can assert the door accepts its output without shipping the door a second key.
- **A proposal that parses is one `PlanAuthoringSession` accepts** — a constraint, not a
  convenience, because a proposal that parsed and then failed at the door would be a card
  the athlete can tap and get nowhere with. Field-value rules are reported in the door's own
  vocabulary (`PlanProposalError.rejectedByAuthoring(PlanAuthoringError)`) rather than
  restated, and a test runs a parsed proposal through a real session.
- **Three rules exist here that the door has no case for** — a complete week, an empty rest
  day, a non-empty ascending arc. Each is something `PlanDraft` makes *unrepresentable*
  (its initializer fills all seven weekdays; `setKind` clears a rest day's distance), so
  enforcing them at the model boundary is agreement with the door, not divergence from it.
  A proposal arrives whole and can break all three.
- **§4.4's exclusions are refused, not ignored.** A reply carrying `version`,
  `effectiveFrom`, or rubric bands is rejected by name. Dropping `effectiveFrom` silently
  would keep an arc indexed from a date the app will not use — a plan wrong in a way nothing
  on screen shows.
- **The schema is generated from `ScheduledSessionKind.allCases`, `Weekday.allCases`,
  `HeartRateSample.plausibleBPM` and `ScoreValue.permittedRange`**, with two guards: a
  compiler-exhaustive `switch` for the per-kind gloss, and tests asserting every enum case
  appears in the rendered text. Adding a session kind and forgetting the prompt now fails
  CI instead of silently producing a model that cannot propose it.

**One thing MAX-099 deliberately did not do.** `PlanProposal.parse` and `ScoreProposal.parse`
now hold two copies of the same code-fence handling. Extracting a shared envelope helper
means editing `Scoring/`, which this ticket does not own; a test pins that the two tolerate
the same formatting, so the duplication cannot drift unnoticed. **Worth a small follow-up.**

**MAX-097 gave the sheet a past.** `ChatSheet` now owns one `NavigationStack` holding the
open conversation and, pushed on top of it, the thread list — `WorkoutChatSectionView`'s
"Open chat" button presents `ChatSheet(subject: .workout(workoutID))` in place of the bare
transcript screen it opened before, and the workout path renders identically once inside it.
Four things worth carrying forward:

- **The title and subtitle are read off `ChatModel`, never re-derived.** `ChatModel` gained
  two computed properties, `title` and `subtitle` — the first calls `ChatThreadTitle.derive`
  against the loaded thread (falling back to "Chat" before one exists, matching this
  screen's title before this ticket); the second calls a new `ChatThreadSubtitle.text(for:)`
  (core, beside `ChatThreadTitle`) and needs no load at all, since a subject's scope is
  known immediately. `ChatModel` also grew a public `workoutFacts`, resolved the moment the
  workout is (even through `.notYetScored`/`.noVerdict`), so the title can name the run in
  every state that has one.
- **The scope-mismatch note is one pure function.** `ChatScopeNotice.text(for:currentInterval:)`
  (core) is nil for a workout subject unconditionally and nil for a training subject whose
  frozen scope still matches the resolved current interval; otherwise it names both windows.
  `ChatConversationView` renders it as a quiet banner above the transcript, tappable through
  to the same **New chat** action the toolbar button performs.
- **Subject-dependent copy for the conversation surface moved to core too.**
  `ChatConversationCopy` (failed-to-load, the empty-transcript invitation, the composer
  placeholder) mirrors `ChatModel.userFacingMessage(for:)`'s established "worded from the
  subject" pattern; the workout strings are pinned byte-for-byte to what shipped before this
  ticket.
- **"New chat" resolves the *current* interval, not a stored one.** `ChatSheet` freezes a
  fresh `TrainingScope` from `currentInterval` (defaulting to "this week" when no live
  dashboard selection is handed in — today's only caller, the workout entry point, has
  none) and reassigns its active subject; `ChatThreadRepository.mostRecentThread(for:)`
  is what decides whether that resumes an existing thread or starts a genuinely new one,
  unchanged. Selecting a row in the thread list does the same reassignment and pops back to
  the conversation.

**What MAX-098 inherits.** The persistent Ask button presents `ChatSheet(subject:
currentInterval:)` exactly as `WorkoutChatSectionView` does — `ChatSheet`'s own doc comment
gives the call. `App/RootTabView.swift` is untouched, per this ticket's brief.

**One thing this ticket deliberately left alone.** The "runs in this conversation" strip
(§2.2, MAX-103's board) is not built — the sheet has no runs strip yet.

**Review found a real defect in the first pass, and it is fixed.** Selecting a thread-list
row originally reassigned the sheet's *subject* rather than opening the tapped thread by
identity — harmless for a workout thread (one thread per run, by policy) but wrong for
training: two training threads can legitimately share an identical frozen `TrainingScope`
(`ChatThreadRepository` deliberately does not deduplicate them — **New chat** over an
unchanged window is still a real action), and resolving by subject after a tap would
silently reopen whichever of the two is newest, not the one shown. `ChatModel` now has two
entry points — `init(subject:...)`, unchanged, for the Ask button and **New chat**; and a
new `init(threadID:...)` for the thread list, which reads the subject off the *stored*
thread rather than trusting a caller-supplied one, so a row tap can never open a different
thread than the one tapped. A thread id that no longer resolves (deleted from another
screen) is `ChatModel.LoadState.threadNotFound` — ordinary, not a failure.
`ChatModelTests.testOpeningByIDReturnsExactlyThatThreadEvenWhenAnotherSharesItsScope` is
the regression test: it reproduces the ambiguity (asserting subject-based resolution really
does pick the wrong one), then asserts opening by id picks the right one anyway.

**MAX-098 built the door.** Chat now has one entry point, on every screen, in the same
place — the plumbing MAX-092–097 landed is reachable for the first time. Five things worth
carrying forward:

- **It is the `TabView`'s bottom accessory, not an overlay** — §12's open question 6,
  answered. `tabViewBottomAccessory` exists on the iOS 26 SDK and is what this ships. The
  argument is not only idiom: the system insets the tab content's safe area around the
  accessory and moves it with the tab bar as `.tabBarMinimizeBehavior(.onScrollDown)`
  minimises it, so §7.3's "it never disappears; it may move" is the platform's behaviour
  rather than something `RootTabView` hand-writes. An overlay would have given neither, and
  would sit permanently over the bottom-trailing corner of three dense scrolling screens.
  **The cost, stated:** the accessory is a full-width bar, so this is *not* §2.1's
  bottom-trailing capsule, and `glassChrome(.floatingControl)` still has no call site — the
  system draws the accessory's container in Liquid Glass and re-applying it would be the
  mistake `RootTabView` and `SettingsToolbar.swift` already argue against for the tab bar
  and the sheet. **Whether the full-width shape reads well is the first item on the device
  list**, and reverting to an overlay is a change to one modifier in one file.
- **The subject is a core decision, with tests.** `ChatEntryPoint.resolve(focus:currentInterval:)`
  (`MaximizeCore/Chat/ChatEntryPoint.swift`) turns "a run is on screen, or none is" into the
  `ChatSubject`, the visible label, a compact label, and what VoiceOver says. No view asks
  itself whether it is a workout screen. `ChatEntryPointFocus` carries the other half: it
  **matches the identifier on release**, because `onAppear`/`onDisappear` are not ordered
  across a screen change and `DayWorkoutsView` pages between two detail screens (MAX-108) —
  clearing unconditionally would leave the button reading "Ask" on a screen showing a run.
  Both orderings are pinned by tests.
- **`RootTabView` owns the interval model now.** §3.4 makes the interval selector the app's
  single notion of "what period are we talking about", and the Ask button needs it on every
  tab; `DashboardView` is handed the same instance it used to own and is otherwise
  unchanged. A consequence worth knowing: a training thread opened from the Workouts or Plan
  tab is about whatever window the dashboard is *currently* on, not always "this week". The
  sheet states its window either way (§2.2, §3.6(b)).
- **`WorkoutChatSectionView` lost its button and gained a preview.** Two chat buttons on one
  screen opening the same conversation is worse than either alone (§2.1). The card is now
  design review §4.4's ask: the last exchange when there is one, the invitation copy when
  there is not, and `ChatConversationCopy`'s wording for both rather than a literal. Its
  preview text comes from `ChatThreadSummary`, so the card and the thread-list row shorten
  the same message identically.
- **A14 holds.** The button presents a sheet and nothing else — no pre-warm, no pre-fetch,
  no speculative call. `ChatSheet` is constructed only on presentation and `ChatModel.load()`
  reads stored records; the model is reached when the athlete sends.

**MAX-101 closed the owner's original ask.** A plan can now be generated through the chat
interface: a training thread carries a **Draft a plan from this conversation** action, the
reply becomes a reviewable proposal card in the transcript, and accepting it opens
`PlanAuthoringView` prefilled. Seven things are worth carrying forward:

- **`PlanDraft.applying(_:)` applies and does not store**, which is A13's named near-miss
  and is asserted rather than described: `PlanProposalApplyingTests` runs the mapping
  against a `PlanRepository` whose `store` calls `XCTFail`, and
  `ChatPlanDraftingTests.testNoPlanIsEverStoredByTheProposalPath` drafts, discards and
  drafts again against a store that counts writes (`InMemoryWorkoutStore.planWriteCount`, new).
  There is no repository parameter on the mapping to pass one; the tests are what fail if a
  future edit adds one.
- **It is an instance method for one reason: lifts.** `PlanProposal`'s vocabulary derives
  from `ScheduledSessionKind.prescribable`, which excludes `.lift` until MAX-141, so a
  proposal describes the run slot and says nothing about lift days. Applying *onto* the
  draft being revised carries them through untouched — including the `liftNote` MAX-137
  deliberately left uneditable — and the card states that in words on **every** card
  (`PlanProposalReview.liftNote`, never optional), so an athlete who wrote "and lift on
  Tuesdays" is not told yes by omission.
- **The diff is a core value with tests, not a view.** `PlanProposalReview` builds the whole
  card — headline, summary, four sections of labelled rows, each row's `Change`
  (`stated`/`unchanged`/`changed(from:)`/`added`), the lift sentence and what accept and
  discard each promise — from the same `PlanAuthoringSession` the handoff will use, so the
  card cannot describe a plan different from the one the form is about to show.
  `PlanProposalReviewTests` pins §4.6's worked example directly: a proposal that drops
  Thursday to 6 km *and* moves the cap to 148 is exactly two changed rows. **Rows diff the
  rendered strings, not the raw doubles** — 148.0 and 148.2 read identically and flagging
  that would train an athlete to ignore the highlight.
- **A dropped arc week is still a row** ("No longer in the arc"), because a sixteen-week
  block quietly becoming twelve is the edit the diff exists to surface.
- **The one retry lives in `PlanProposalDrafting`**, under test, and is uniform: parse or
  validation failure → one corrected re-ask carrying the rejection's own `description`;
  a second failure → the athlete reads the error and nothing changes. A **transport**
  failure is not retried at all — it is not a failure of the proposal's content, and A14
  bounds plan drafting to one call per tap. Empty transcript, or one not opening with the
  athlete, costs zero calls.
- **Failure is a state, four ways.** No key points at Settings in chat's own existing
  wording; network, refusal and two failed parses each get one honest sentence appended as a
  `.notice` — never written to the thread, exactly like a dropped stream's.
- **A proposal is not a turn.** It lives on `ChatModel.planDrafting`, is never persisted,
  and is cleared by a reload. `canDraftPlan` is training-subject-only and requires the
  *thread* to hold a user turn (not merely the screen), so an enabled button can never
  produce "there is nothing to draft from".

**Two edits MAX-101 made outside its own new files, both to remove a duplicate rather than
add one.** `PlanAuthoring.currentVersion(of:)` is now public and `PlanDisplayData` calls it
instead of repeating its `max(by:)` — three readers of "which version is in force" needed to
be one. And the plan's athlete-facing vocabulary (weekday, session kind, muscle group,
distance, a day's one-line ask) moved into `MaximizeCore.PlanCopy`, with
`PlanAuthoringFormatting` calling through; the card and the form it hands off to must not
spell "Long run · 18.0 km" two ways. No call site changed.

**What MAX-101 did not do.** §4.7 Phase B — a proposal emerging mid-stream — is still
deferred; this is Phase A, a separate one-shot call behind a button. `PlanProposal` still
cannot prescribe a lift (MAX-141). And the card's copy is not yet through MAX-104's
app-wide absence-voice pass.

**MAX-103 filled the gap MAX-097 named — "the sheet has no runs strip yet."** A training
thread's sheet now renders §2.2's runs strip, below the transcript and above the
composer: one chip per session in *this exact thread's* `TrainingContext`, tapping one
pushes that session's own detail screen. Four things worth carrying forward:

- **The chip's content is core, under test — `RunsStripData`
  (`Sources/MaximizeCore/Chat/RunsStripData.swift`), `RunsStripDataTests.swift`.** Label,
  ordering, the empty case and the cap are all decided there, the same split
  `PlanDisplayData` draws: a chip carries a `workoutID` to push with and a label —
  `"3 Aug 2026 · Running"`, the same date form and separator
  `ChatThreadTitle.workout` already names a run's own thread by — and nothing measured
  (no distance, no score, no band). **The band omission is deliberate, not an oversight**:
  `Color.scoreBand(_:)`'s own documentation confines the three saturated score colours to
  the calendar and the verdict header (FR-4.3), and §6.3 already forbids a chat surface
  from rendering a metric; a coloured pip on a chip would have broken both rules at once
  for a fact the destination screen already states in full.
- **Built from the thread's own context, never a second read.** `ChatModel.runsStripData`
  is a computed property reading the `PromptContext` `load()` already assembled — nil for
  a workout subject (`ChatSubject.workout`, where the sheet already sits on the run's own
  screen, §6.1) and nil before a context exists. No repository is opened a second time,
  so the strip cannot show a session the prompt did not.
- **Two caps, kept distinct.** `TrainingContext.sessionsWereWithheldByTheCap` (its own
  200-session bound) reports as `RunsStripData.EmptyReason.withheldByCap` — the strip
  must not list what the fact sheet itself withheld. `RunsStripData.maximumChips` (62,
  sized at `TrainingContext`'s own "a month is at most ~62" figure) is a second, smaller
  bound of the strip's own, for a horizontal scroll rather than a prompt; beyond it the
  remainder folds into a trailing, non-interactive "+N more".
- **The navigation is one more `ChatSheet.Route` case**, pushed on top of the
  conversation exactly as the plan-proposal handoff already is — `WorkoutDetailView` gets
  a third caller, reachable from inside the sheet's own `NavigationStack` for the first
  time. `App/Chat/RunsStripView.swift` only lays out `RunsStripData` and forwards a tap;
  it decides nothing CI cannot see.

**Rejected: colouring a chip by score band, and reordering newest-first.** Both were
considered and both would have been a second, silently different notion of "the runs in
this conversation" from the one the fact sheet states — colour for the FR-4.3 reason
above, and order because `TrainingContext.sessions` (and therefore the fact sheet) is
already chronological, oldest first; a strip that read the other way would disagree with
its own prompt about what "the runs in this conversation" means.

**What this ticket did not do.** The strip's header ("Runs in this conversation") is a
fixed string with no data dependency, so — like `WorkoutChatSectionView`'s "Chat"
heading — it stays a literal in the view rather than moving to `MaximizeCore`; only the
copy that varies with `RunsStripData` (`RunsStripCopy`) is core. The name is the spec's
own (§6.2), unchanged even though the strip now names lift sessions too, since
`TrainingContext.sessions` already carries both disciplines (LIFTING-SPEC §10.2) — a
copy pass over that naming, if wanted, belongs to MAX-104, not this ticket. And this PR
does not verify tap-target comfort or how the strip reads against Dynamic Type on a
device — see its **Needs device verification** heading.

### Phase 9 — Lifting (MAX-109)

**MAX-144 is decided, by the owner: A22.** *"You can set the muscle group in the detail view
of the workout if it is strength training."* That is the first of the three costed options —
the athlete confirms afterwards — and the only one that makes a lift's prescription a
**standard** rather than documentation. The manual-entry non-goal is spent deliberately and
narrowly, the way A10 was: one field, one kind of workout, on the screen where you are
already looking at that session.

**MAX-145 builds it, and the interesting part is not the picker.** Two consequences fall out
that a ticket written as "add a muscle-group control" would miss:

- **A lift cannot be scored at ingestion any more.** D2 computes metrics once when a workout
  arrives and D8 makes an auto-score immutable — but the groups arrive *later*, whenever the
  athlete opens the screen. A lift scored at ingestion would have been judged against
  information nobody had yet, and revising it afterwards is exactly what D8 forbids. So a
  lift waits: not awaiting a model, not permanently unscoreable, but **awaiting the athlete**.
  A third state beside MAX-126's `noVerdict`, and a better one, because it is the app asking
  a question rather than guessing an answer. It is also the feature's own onboarding — a lift
  on the calendar saying *"tell me what you trained"* is how the field gets discovered.
- **The entry does not belong on `Workout`.** That record mirrors what HealthKit reported and
  nothing else writes to it. This is athlete-supplied truth *about* a session, which is the
  shape `ScoreAnnotation` already has: additive, timestamped, never overwriting what was
  captured. And "I have not told you yet" must stay distinct from "I trained nothing" — only
  the first should prompt.

It also unblocks the rubric half. MAX-131 was told its vocabulary must not *require* muscle
groups, because nothing could supply them; that still holds, since a lift the athlete never
annotates has to score somehow. But MAX-132's seed bands can now judge
prescribed-versus-actual, which is what A20's adherence was always reaching for.



**MAX-109 is the lifting product spec, and it is delivered:**
[`docs/LIFTING-SPEC.md`](./docs/LIFTING-SPEC.md) plus amendments **A16–A21**. Nothing in it
is built. It came from one sentence from the owner — *"Plans should account for both
lifting goals and running goals"* — and the first thing it found is that the ticket is not
what it looks like.

**Strength workouts are already captured, already enriched, and already scored.** Nothing
in the pipeline filters by activity type: `HealthKitWorkoutObserver` watches
`HKWorkoutType`, the fetcher maps `.traditionalStrengthTraining` to a first-class
`ActivityType`, `WorkoutIngestionPipeline` has no activity branch, and MAX-034 made sample
extraction unconditional. So every lift since MAX-033 has been stored with its heart-rate
curve, given derived metrics measured against the *running* cap, classified `.other`, and
scored — at 40–69 by `StandardPlanSeed`'s unconditional `fallback.recorded` band against a
threshold of 70, or at **20–45 by `easy.wellOverCap`**, which carries no
`.actualClassification` condition and therefore fires on any workout whose average heart
rate clears cap + 8, with the rationale *"Well above the easy cap for the whole run."*
Those scores are immutable (D8). This phase is a correction of behaviour already in
production, not the addition of a feature.

Two more findings worth carrying without reading all of it:

- **`DerivedMetricsCalculator` fabricates a cadence for lifts.** Average cadence is derived
  from step count over duration with no discipline gate, so a lifting session yields ~20
  steps/min — walking between racks — drawn against a 165–170 band and printed to Claude as
  "Average cadence". A18 draws the line the code is missing: a number that *can* be computed
  and describes nothing is not the same as an honest absence, and this codebase's
  absence-is-first-class stance is an argument for **not computing it**, not for rendering
  it as a dash.
- **The classifier is the least damaged part**, contrary to the dispatch brief's reading.
  It does not read pace at all (its own doc comment refuses cadence, pace and energy), and
  it short-circuits on `activityType.isRun` before touching a heart rate. A lift already
  classifies `.other` and there is a test pinning it.

The three decisions worth knowing without reading all of it:

- **The prescription is indexed by discipline (A17).** `Discipline` is closed at `.run` and
  `.lift`; the weekly template prescribes one session per **(weekday, discipline)** pair,
  rest explicit on both, so resolution stays a total function; and a workout is only ever
  evaluated against its own discipline's ask. One plan record, one version, one
  `effectiveFrom` — two plan records would make `Score.planVersion` ambiguous and split
  every D1 guard in the codebase. **No migration:** the plan is a JSON blob and the lift
  slot decodes with `decodeIfPresent` defaulting to rest, so a plan authored before lifting
  decodes to "prescribed no lifting", which is what it meant.
- **Effective days count obligations, not days (A19).** A Tuesday asking for a run and a
  lift is two obligations; meeting one is not meeting the day. Two *attempts at one*
  obligation still resolve generously (the warm-up-jog reasoning is untouched). The
  landable property is that on a day prescribing at most one session the two countings are
  identical — so **no historical figure moves**, and that is an acceptance criterion with
  fixtures behind it.
- **Lifting is scored on adherence, not volume (A20).** HealthKit has no sets, reps or
  load, so the alternative is manual entry — PRD §3's *"the thing being killed"*. The
  non-goal is **not** spent. The honest cost is stated: adherence cannot tell a hard
  session from a token one.

**One escalation, and it is not a ticket's to make.** §11.4 / A21: the lift scores already
written are wrong, D8 forbids overwriting them, and they are not scorer misjudgements —
counting them as such corrupts the correction-rate signal D8 exists to protect. The
recorded lean is to label them; the decision is the owner's, tracked as MAX-143.

**The spec's numbering collides with shipped work.** LIFTING-SPEC §14 was written while
MAX-110 (the tallies' future-days fix) and MAX-129 (the stop-gap scoring gate) were in
flight, so its MAX-110 … MAX-143 sequence reuses two IDs that are already taken. Its
MAX-110 has been renumbered **MAX-128** and is built; **the rest of the sequence has not
been renumbered**, and 129 in particular still names two different tickets. Resolving that
is the overseer's, not a ticket's — flagged here rather than done.

| ID | Ticket | Depends on | Tier |
|---|---|---|---|
| MAX-128 | `Discipline`, and `.lift` on both classification enums (spec's MAX-110) | — | **Opus** ✅ |
| MAX-129 | The per-discipline prescription; the no-op decode test | 128 | **Opus** ✅ |
| MAX-130 | Discipline-gated derived metrics; stop fabricating cadence | 128 | **Opus** ✅ |
| MAX-131 | Rubric vocabulary for lifts — **closes gap P3** | 128 | **Opus** ✅ |
| MAX-132 | Seed bands for lift days; the `easy.wellOverCap` shadow | 131 | Sonnet |
| MAX-133 | Match a workout to its own discipline's ask | 129, 131 | **Opus** |
| MAX-134 | Obligations, not days: tallies, streak, rest-day budget | 129, 133 | **Opus** |
| MAX-135 | The calendar's mixed day | 134, **105** | **Opus** |
| MAX-136 | Context and fact sheet learn discipline | 129, 130 | **Opus** 🔒 |
| MAX-137 | Plan authoring for two slots | 129 | Sonnet ✅ |
| MAX-138 | The plan screen shows both | 129 | Sonnet ✅ |
| MAX-139 | Workout detail for a lift | 130, 133 | Sonnet |
| MAX-140 | Trend tiles, honestly ("days run", the effective denominator) | 134 | Sonnet |
| MAX-141 | `PlanProposal` covers lift days | 129, **099** | Sonnet 🔒 |
| MAX-142 | `TrainingContext` is per-session, not per-run | 129, **095** | **Opus** 🔒 |
| MAX-143 | **Decide what to do with lifts already scored as runs** | 128 | Owner / overseer |
| MAX-144 | ~~How adherence to a muscle-group prescription is judged~~ — **decided (A22)** | 129 | Owner ✅ |
| MAX-145 | **Enter muscle groups on a strength workout's detail screen** (A22) | 129, 144 | **Opus** ✅ |

**Four collisions the overseer must respect.**

1. **MAX-105 before MAX-135, and MAX-105's brief must carry A17** — see the MAX-105 note
   above. Sequence 129 → 105 → 135.
2. ~~**MAX-095's brief must carry LIFTING-SPEC §10.2 before it is written.**~~ **Done —
   MAX-095 landed briefed, so MAX-142 is not needed.** Its roll-up is one line per
   *session*, discipline-tagged, with fields that do not apply omitted rather than
   nil-rendered, and the cap counts sessions. The plan block renders the whole stored
   `WeeklyTemplate`, so the lift slot appears there the moment MAX-131/132 adds one — no
   further edit to `Context/` is required for it.
3. ~~**MAX-110 adds `.lift` to `RestDayBudgeting.costTier` without reordering the existing
   cases.**~~ **Respected — MAX-128 inserted `.lift` between `.easy` and `.hard` and
   renumbered nothing else**, so every existing comparison is unchanged and no historical
   day converts differently. `Domain/ScheduledSession.swift` is still touched by 129 and
   131 and they are in dependency order.
4. **MAX-104 runs after 135–140.** It already absorbs MAX-086's absence-voice half; it
   should absorb the lifting surfaces in the same pass rather than spawning a follow-up.

Suggested order: **105 (briefed) → 128 → 129 → (130 ‖ 131) → 132 → 133 → 134 → 135**, with
136 parallel after 130, 138 then 137 parallel after 129, and 139/140 last.

**MAX-128 — the vocabulary, and nothing else.** `Discipline` is a closed two-case enum
(`.run` / `.lift`) with the one mapping from `ActivityType` beside `isRun`, and both
classification enums carry `.lift`. **No behaviour changes**: nothing produces a `.lift`
classification (the classifier still answers `.other` for every non-run), nothing can
prescribe one (the weekly template has one slot until MAX-129, and
`ScheduledSessionKind.prescribable` keeps the authoring picker offering exactly the five
kinds it offered before), and no stored record moves — both enums are `String`-backed and
decoded by raw value, so a case nothing has written is additive on the wire and the plan
blob needs no migration.

`isRun` is now expressed *through* `discipline` — `guard discipline == .run` before the
existing comparison — which is what stops them becoming two notions of the same thing. They
are deliberately not the same predicate: `discipline` says which slot judges a workout, and
a ride is `.run` by slot without being a run, so the containment is one-way and pinned by a
test over every named activity type.

**Left alone and reported: `WorkoutClassifier`'s residual.** MAX-126's finding — that "not a
run" and "a run whose curve could not be read" share `.other` — is only half-addressed by
having a `.lift` word for it. A ride and an unreadable run would still collapse, so
separating them is a rework of what the classifier's residual *means*, not a case added to
its vocabulary. Also not taken: mapping HealthKit's `.functionalStrengthTraining` to a
first-class `ActivityType` (LIFTING-SPEC §14 puts it in this ticket). It changes the
activity type a real workout is stored under, which is behaviour, and this ticket's brief
forbade any. It is a one-line fetcher change plus one row in `ActivityType.discipline`,
and it wants the ticket that is already opening `App/HealthKitWorkoutFetcher.swift`.

**MAX-129 — the prescription is indexed by discipline.** `WeeklyTemplate.Entry` carries a
run ask and a lift ask; `PlanDay` carries both and answers `scheduledSession(for:)`, which
is total in the discipline because `Discipline` is closed at two cases and rest is an
answer on each. One plan record, one version, one `effectiveFrom` — D1 untouched.

- **No behaviour changes for a run.** Every existing reader of `PlanDay.scheduledSession`
  and `WeeklyTemplate.Entry.session` means the *run* ask, so after this change each is
  still correct rather than merely still compiling. `canBeMissed` is likewise still the run
  obligation's predicate; widening it to count obligations is A19, and MAX-134's ticket.
- **No migration, proven twice.** `liftSession` and `muscleGroups` decode with
  `decodeIfPresent` and are *omitted on encode* when they carry nothing, because rest and
  absent are the same statement (A17). So a lift-free plan encodes to the bytes it encoded
  to before the ticket, and a `Score`'s stored `ScheduledSession` (immutable under D8) does
  not move either. Pinned by a hand-written pre-MAX-129 payload that decodes to a template
  with every lift slot at rest and re-encodes to the same bytes, and by a same-band
  assertion through `RubricEvaluator` — LIFTING-SPEC §2.3's two acceptance criteria.
- **Authoring carries the lift slot forward verbatim.** `PlanDraft.DayDraft.liftSession` is
  carried but not editable: `PlanDraft.init(_:)` is documented as lossless, and this was
  the first field that could have made it untrue — a revision that dropped it would delete
  a lifting prescription the next time the athlete changed their HR cap. A17 leans on that
  carry-forward when it argues one plan record rather than two. **MAX-137 gives the screen
  its editor**, and with it the loose-input validation `PlanAuthoringError` will need.

**Downstream types that now need updating, in dependency order.** None of these are broken
today — the run half of each is unchanged, and every plan on disk prescribes rest on every
lift slot — but each currently answers about the day's *run* while calling it the day:

| Reader | What it reads | Ticket |
|---|---|---|
| `RubricEvaluator.evaluate` | `planDay.scheduledSession.kind` picks the bands | MAX-133 |
| `RestDayBudgeting` / `TalliesCalculator` | `PlanDay.canBeMissed`, `costTier` | MAX-134 |
| `ScoreCalendar.dayState` / `agreement` | the day's single prescribed kind | MAX-135 |
| `TrainingFactSheet` / `WorkoutFactSheet` | `entry.session`, `planDay.scheduledSession` | MAX-136 |
| `PlanDraft` setters, `PlanAuthoringError` | ~~the run slot only~~ **both, as of MAX-137** | MAX-137 ✅ |
| `PlanDisplayData.WeekdayRow` | ~~one kind/distance/note per weekday~~ **both slots, as of MAX-138** | MAX-138 ✅ |
| `TrendTileData` planned mileage | sums `planDay.scheduledSession.distanceMeters` | MAX-140 |
| `PlanProposal` (MAX-099) | validates the same shape `PlanAuthoringSession` does | MAX-141 |

**MAX-141 does need updating, and its brief should say so.** `PlanProposal` validates
against `PlanAuthoringSession`'s rules; those rules did not change for the run slot, so it
still compiles and still produces valid plans — but a proposal it accepts can only ever
prescribe rest on every lift slot, which is now a silently incomplete plan rather than the
only expressible one. Since the owner has reaffirmed that **the plan is configured through
chat**, that ticket is the real authoring path, not MAX-137's form.

**Scope taken mid-ticket: the lift slot names its muscle groups.** Owner's ask. `MuscleGroup`
is a closed six-case core vocabulary — chest, back, shoulders, arms, legs, core — chosen so
that push/pull/legs, upper/lower and a five-day split are all expressible without a residual
case; "full body" is the whole set rather than a seventh case, because an overlapping case
gives one Tuesday two spellings. `ScheduledSession.muscleGroups` is a `Set`, encoded in
`CaseIterable` order so a set's arbitrary iteration order never reaches the bytes, and only
a `.lift` may carry one — the same shape of rule, for the same reason, as a rest day being
unable to carry a distance. **Rest and "a lift with no groups named" stay distinct**, which
is what keeps the lift slot's totality meaningful.

> **⚠️ Open, needs an amendment and the owner's call: nothing can verify a muscle-group
> prescription.** HealthKit reports `traditionalStrengthTraining` and says nothing about what
> was worked — the same wall A20 hit on sets, reps and load when it chose adherence over
> volume. So the plan can say "Tuesday is chest and shoulders" and the app cannot check that
> it happened. **This ticket made no scoring, tallies or adherence decision about it**, and
> nothing on those paths reads `muscleGroups`. The options, with what each costs:
>
> 1. **The athlete confirms after the fact.** The only option that actually verifies. Spends
>    PRD §3's manual-entry non-goal, which A16 was deliberately written narrowly to avoid
>    spending, and adds a per-session prompt to a product whose whole claim is that capture
>    is automatic.
> 2. **The plan states intent; scoring never checks it.** Costs nothing and changes nothing:
>    muscle groups become prescription copy that reaches the athlete, the plan screen and
>    Claude's context, and adherence stays "did a lift happen on a lift day" (A20). The gap
>    is that a week of chest-only lifting scores identically to a balanced one.
> 3. **Chat asks.** Claude already has the prescription in context (D3/A12) and can ask "did
>    you get to legs?" in the daily conversation. Cheap, conversational, and *not* a record —
>    an answer in a chat bubble is not a stored fact anything can count, so it informs the
>    athlete without becoming telemetry.
>
> Recommended lean: **2 now, 3 as it costs nothing extra, and 1 only if the owner decides the
> signal is worth the non-goal.** Recorded, not taken — flagged for the overseer to dispatch.

**MAX-137 — plan authoring for two slots.** `PlanDraft.DayDraft` decomposes the lift slot
the same way the run slot already was — `liftKind` / `liftMuscleGroups`, `private(set)` and
mutated through `setLiftKind`, `setLiftMuscleGroups`/`toggleLiftMuscleGroup` — rather than
carrying it as an opaque `ScheduledSession` with no editor. `liftNote` stays carried but
unedited: a lift's duration is still only expressible as free text until a future ticket
gives `ScheduledSession` a structured duration field, and this ticket did not widen its own
scope to build that.

- **The lift slot gets its own picker vocabulary, not the run slot's.**
  `ScheduledSessionKind.liftPrescribable = [.rest, .lift]` — a genuinely smaller set, not
  `prescribable` with one case swapped, because the rubric has no easy/long/hard gradient
  for a lift (LIFTING-SPEC §3.5): a lift day is either prescribed or it is not. Handing the
  run slot's five-case vocabulary to the lift picker would let a plan write a run-shaped ask
  into the lift slot — the same cross-discipline confusion `prescribable` exists to keep out
  of the run slot, arriving from the other direction.
- **The two empty states are a core type, not a view switch.** `LiftPrescriptionSummary`
  (`.rest` / `.unstatedGroups` / `.groups(Set<MuscleGroup>)`) is the one place "no lift" and
  "a lift with no groups named" are decided apart; `PlanDraft.DayDraft.liftSummary` and
  `ScheduledSession.liftPrescriptionSummary` both read it, so the editable week and the
  resolved preview can never describe the same day two different ways. Copy
  ("Rest" / "Lift · groups not stated" / "Lift · Chest, Back") lives in
  `PlanAuthoringFormatting`, same split as everywhere else in this app.
- **How a weekday's two asks summarise is also core.** `DayDraft.ObligationSummary`
  (rest/runOnly/liftOnly/both) is the caption a scanning eye reads above each day's two
  pickers — "checking seven days of two slots" per the ticket's brief — computed once, under
  test, rather than a view re-deriving "does this day have anything" from two kinds.
  **MAX-138 moved the enum itself out of `DayDraft` to a top-level `ObligationSummary` in
  `Domain/ScheduledSession.swift`** — `PlanDisplayData.WeekdayRow` needed the identical
  decision off the identical two `ScheduledSessionKind` values, and a second enum with the
  same four cases is exactly the drift this file's `MuscleGroup`/`LiftPrescriptionSummary`
  entries keep warning about. `DayDraft.obligationSummary` is unchanged at the call site —
  it now returns the shared type rather than a nested one.
- **The preview section shows both slots per day**, `describeBothSessions(_:unit:)`, so "the
  first week this version governs" is seven rows again, not fourteen.
- **A run-only plan is unaffected.** Every lift setter clears itself back to `.rest` /
  no-groups the same way the run slot's `setKind(.rest)` already did, and a draft that never
  touches the lift slot authors byte-for-byte what it did before this ticket —
  `testARunOnlyPlanAuthorsExactlyAsBefore` pins it.
- **`PlanAuthoringError` gained one belt-and-braces case**, `liftSessionInvalid`, for the
  combination the new setters cannot actually produce — the same reasoning
  `wouldRewriteHistory` already documents for why a real case beats a `try!`.

**MAX-138 — the read-only plan screen shows both slots.** `PlanDisplayData.WeekdayRow`
carries the lift slot's full `ScheduledSession` alongside the run fields it already had, plus
`obligationSummary` (the shared `ObligationSummary` — see the MAX-137 note above on why it
moved out of `DayDraft`). `PlanDetailSections`' weekly-template card stays **one row per
weekday**, not fourteen: this was the ticket's judgement call to make, and the reasoning is
inline on `weekCard`'s own doc comment. A day's *value* text grows a second line only when it
actually carries two asks (`PlanFormatting.weekdayLines`, switching on `obligationSummary`);
rest-on-both — the common case — stays the one short line it always was, so a busy week reads
visibly busier than a quiet one without a fourth visual channel. `.accessibilityElement(children:
.combine)` makes a two-line day one VoiceOver stop, not two disconnected fragments.

- **A run-only plan reads exactly as before, byte for byte.** `PlanFormatting.runAsk` is the
  same kind/distance/note string `weekdayValue` computed before this ticket, moved rather than
  rewritten, and `weekdayLines` returns exactly that one string for `.rest` and `.runOnly` —
  the two cases every plan on disk today falls into.
- **A pre-MAX-129 plan and a plan that deliberately schedules no lifting are indistinguishable
  on disk** — `WeeklyTemplate.Entry`'s own decoding makes "absent" and "rest" the same bytes
  (A17 §2.3), so there is no bit anywhere in a stored `Plan` recording which one happened. This
  ticket's brief asked for the pre-lifting case to read as "predates lifting" rather than
  "every day is rest"; given the two are provably the same fact on disk, the screen renders
  both the one honest way available — the lift line is simply absent, never a second "Rest" —
  rather than fabricating a distinction the type system cannot support. Recorded here rather
  than silently decided: if the owner wants the two cases to read differently, that needs a new
  signal written at authoring time (e.g. a plan-level flag), not something this ticket could
  infer from an existing stored plan.
- **`describeLiftSession` and `describeBothSessions` are unchanged, reused as-is.** No second
  copy of "what a lift session says" or "how a two-slot day joins" was written — the read-only
  row calls `PlanAuthoringFormatting.describeLiftSession` directly for its lift line, and
  `describe(_ summary: ObligationSummary)` picked up the shared type without any call site
  needing to change (the property `obligationSummary` still just returns *a* value; nothing
  spells out the type name at the call site).
- **Rest-day-budget caption (LIFTING-SPEC §6.4/§15 Q9, "what does the budget count now") was
  not taken.** It is not in this ticket's brief, and MAX-104 already owns the app's
  absence/copy pass; flagged here rather than done, per CLAUDE.md's rule for out-of-scope
  work found mid-ticket.

**MAX-130 — a lift's metrics are decided, not merely withheld.** MAX-111 put `if isRun` in
front of three expressions in `DerivedMetricsCalculator`. That fixed the three metrics that
existed and did nothing about the fourth, so the decision moved into `DerivedMetricKind` —
one case per figure `DerivedMetrics` carries, one exhaustive `switch` answering what a
workout must be before that figure describes anything, and `DerivedMetricKindTests` walking
the record's stored properties by reflection so a *field* added without a case fails CI too.
A new metric cannot now reach a discipline it says nothing about by default.

- **A lift's stored record is: average and maximum heart rate, and zone splits.** Nothing
  else. Cadence, grade-adjusted pace and distance splits stay absent (MAX-111, unchanged);
  drift stays absent; and **`timeAboveCapSeconds` is now absent too** — LIFTING-SPEC §3.3(a),
  the one behaviour change. `Plan.heartRateCapBPM` is the easy-run ceiling, so on a lift the
  figure keeps its name and heading while changing meaning from "did you hold the plan's
  discipline" to "how hard did you work". §15 q2 records this as the owner's to overrule;
  the lean it implements is the spec's own.
- **No new stored figure, and no schema change.** §8's honest list of what HealthKit gives
  for a strength session is duration, active energy and the heart-rate series — and
  `Workout` already stores the first two. Adding a derived copy of either would be a second
  source of truth for a number the record already holds, which is exactly what D2 forbids.
  So `StoredWorkoutRecords` and `MaximizeSchema` were not touched, against the spec's ticket
  table, which anticipated new columns.
- **The gate reads `Discipline`, and `isRun` survives where it is the narrower question.**
  Three requirement cases, not two: `.anyDiscipline`, `.runDiscipline` (the figure is
  anchored to a *run field of the plan*), and `.runningActivity` (the figure models running
  gait or the metabolic cost of running a grade). A ride and a hike are `.run` by slot and
  have no running form, so a gate written as `discipline == .run` would hand cadence and
  Minetti pace straight back to them — the second half of what MAX-111 actually fixed. The
  containment `isRun ⇒ .run` is already pinned by `DisciplineTests`.
- **No backfill, and no stored score touched** (D2, D8). Metrics are still computed once, at
  ingestion, at the same moment as before; already-ingested lifts keep the metrics they
  have, including the cap figure. Re-deriving them is a separate ticket with MAX-067's
  question attached, and the scores those figures fed are A21/MAX-143's.
- **Reported, not done: `HKQuantityTypeIdentifier.workoutEffortScore`.** §15 q1 asks the
  implementer to check whether a strength-relevant quantity type has appeared. As far as can
  be established without an SDK in this container: **no sets, reps or external load** — the
  finding §8.1 rests on holds. The one lift-relevant quantity HealthKit does have and this
  app does not request is the iOS 18-era `workoutEffortScore` / `estimatedWorkoutEffortScore`
  pair, a 1–10 session-effort rating. It is a fetcher change plus an authorisation change in
  the App layer, and it is the closest thing to an intensity signal a lift can carry — see
  §8.3's stated cost ("adherence scoring cannot tell a hard session from a token one").
  Worth its own ticket; deliberately not taken here.

**MAX-131 — two words, and the argument for not adding a third.** A20 scores a lift on
adherence, not volume: whether the session the plan asked for happened, on the day, for
roughly the prescribed length. Two thirds of that were already expressible — the day is
the day the band is evaluated on, and "it happened" is a band with no metric condition.
The two that were not are now `RubricCondition.actualDiscipline(oneOf:)` and
`RubricReference.scheduledDuration(fraction:)`, the latter resting on
`ScheduledSession.durationSeconds`, **which closes the rubric half of gap P3**.

- **`activeEnergyKilocalories` was considered and declined**, against LIFTING-SPEC §3.5's
  three-item list. A20's own sentence is "no rubric band references a load or a volume",
  and energy burned is the one number in a lift's record that answers *how much work* —
  the question A20 says the app cannot honestly ask. It also has no plan-relative anchor,
  so a band using it would carry a `.constant`: a per-athlete physiological threshold
  frozen into the rubric, which is the shape `RubricReference` exists to avoid. Under D1 a
  case is permanent, so it should be added by the band that needs it, not in advance.
- **`.actualDiscipline`, not `.discipline`, and it reads the workout rather than the
  classification.** Named for the split it sits on: `RubricBand.appliesTo` is the
  *scheduled* side, and this is the *actual* side alongside `.actualClassification`. It
  reads `workout.activityType.discipline` — a fact HealthKit recorded — because the
  classifier is a judgement, and because it short-circuits every non-run to `.other`, so a
  band conditioned on `.actualClassification(oneOf: [.lift])` would silently never fire.
- **The `easy.wellOverCap` shadow is now avoidable, and is not yet avoided.** A test pins
  both halves: the seed's band as written matches a lift on an easy-run day (the defect
  A21 records), and the identical band plus `.actualDiscipline(oneOf: [.run])` cannot.
  **Writing that condition into `StandardPlanSeed` is MAX-132** — the vocabulary is a
  type-level decision the whole rubric inherits, the seed is one plan's opinion.
- **No behaviour change, and a lift is still left unscored** by MAX-111's ingestion gate.
  Nothing added here is reachable until MAX-133 matches a workout to its own discipline's
  ask; `RubricEvaluator` still reads `planDay.scheduledSession` for every workout.
- **Nothing stored moves, pinned in MAX-129's shape.** A hand-written pre-change rubric
  payload decodes to identical bands with identical conditions, six §10.3 rows match the
  identical band under it and under the in-code fixture, and a `ScheduledSession` with no
  duration writes no key — so every stored plan and every stored `Score`'s prescription
  (immutable under D8) keeps its bytes.
- **Muscle groups are deliberately not a condition** (MAX-144 is the owner's open call).
  A plan may prescribe them and nothing can verify one, so no band can require one; adding
  the case later is additive on the wire and costs no stored rubric anything.
- **Two carry-forwards taken because the new field would otherwise be silently dropped.**
  `PlanDraft.DayDraft` carries `durationSeconds` on the run slot — `PlanDraft.init(_:)` is
  documented as lossless and the run slot is the half that decomposes — and
  `PlanCalendar`'s arc substitution rebuilds a long-run session, so it carries it too.
  Neither is editable: **MAX-137 gives the screen its editor**, and **MAX-141** is what
  lets a chat-authored proposal state one. Until then nothing authors a duration, which is
  why this ticket adds none to `StandardPlanSeed`.
- **Reported, not done: the classifier half of P3.** `WorkoutClassifier.isFragment` still
  tests distance only, so an HR-only treadmill fragment still reaches the scorer.
  LIFTING-SPEC §9.2 wants a duration floor there; the plan can now express one, and
  changing the classifier is a behaviour change this ticket's brief forbade.

**MAX-145 — the athlete says what a lift worked, and the app learns to wait for it.**
A22 built. The picker is the small half; the two consequences the amendment named are the
change:

- **A lift's absent score has a third name now.** `WorkoutVerdict.Scoring
  .awaitingMuscleGroups` sits beside `.awaitingScore` (awaiting a *model*) and MAX-126's
  `.noVerdict` (no verdict is coming). The verdict header renders it with no spinner and no
  future tense — a spinner would announce the app as busy with something it has not been
  given — and with the same question the section below it asks, in the same words, from one
  core copy type. **Nothing scores a lift yet either way** (that is MAX-131/132); what
  changed is that the app now knows *what it is waiting for*, and says so.
- **The entry is a record beside the workout, not a field on it.** `MuscleGroupEntry` is
  `ScoreAnnotation`'s shape applied to an input: its own identifier, timestamped, additive.
  Changing an answer appends; `MuscleGroupLog` resolves the latest as the one in force and
  keeps the rest. `Workout` was not touched, which is what stops A22's narrow manual-entry
  permission leaking into "the app can edit a captured session."
- **"I have not told you yet" is unrepresentable as "I trained nothing."** An entry with an
  empty group set throws at the initializer, at decode, and at the picker's Save button —
  absence is the *absence of an entry*, and only that prompts.
- **A run is untouched, and no stored score moved (D8).** No run is ever asked the
  question; a ride, hike or walk still lands on `.noVerdict`; and a lift already carrying an
  auto-score from the running rubric (A21/MAX-143) still reports it, because the ledger
  branch is read before any of this. `WorkoutVerdictTests` pins all four.
- **`WorkoutVerdict`'s new parameter distinguishes "not looked" from "not told".** It takes
  a `MuscleGroupLog?`, where nil means the caller did not read one — so `ContextBuilder`,
  which does not, resolves byte-identically to before A22 rather than asserting a state it
  never read. The single compiler-forced line in `Context/TrainingFactSheet` is the new
  case's switch arm, unreachable today.
- **No migration.** `MuscleGroupEntryRecord` is a *new* record type: SwiftData creates its
  table and no existing row is read, rewritten or re-typed. Every property is non-optional
  with a default, no `@Attribute(.unique)`, no relationship (A8's rules kept), and
  `MaximizeSchemaV1`'s version does not move — `distanceSplitsJSON`'s reasoning. Deletion
  cascades via a new `WorkoutAttachedRecord.muscleGroupEntries`, which is how the compiler
  made this ticket decide.
- **Not verified by CI beyond compilation.** The picker, the sheet and the persistence are
  App-layer (tracker R2, R13). See the PR's **Needs device verification** section — set
  groups, force-quit, reopen.

**MAX-093 landed the stored record.** `StoredChatThread` is columnar —
`subjectKindRawValue`, `workoutUUID` (a fixed sentinel for a training row),
`scopeFromISO8601`/`scopeThroughISO8601`, and a real `lastActivityAt` column — following
`ChatSubject`'s own `Codable` key names, which already named these as the columns this
ticket would split it into. `MaximizeStore`'s `ChatThreadRepository` conformance is a
genuine implementation now, not the MAX-092 stub: `store(_:)` is keyed on the thread's own
`id` and evicts other rows for a workout subject at the door (§12 q3), and
`mostRecentThread(for:)` implements the training-subject query — exact match on the frozen
scope, newest `lastActivityAt` with `id` breaking a tie, the same rule
`FakeChatThreadRepository` and `ChatThreadSummary.sortedByActivity(_:)` already run under
`swift test`.

- **No migration, proven as behaviour.** Every added column is either non-optional with a
  default (`subjectKindRawValue` defaults to `"workout"`, `lastActivityAt` defaults to
  `Date.distantPast` as an "unset" sentinel) or optional with none (`scopeFromISO8601`,
  `scopeThroughISO8601`) — `DerivedMetricsRecord.distanceSplitsComputed`'s and
  `.distanceSplitsJSON`'s precedent exactly. `StoredChatThread.toDomain()` detects the
  `lastActivityAt` sentinel and falls back to MAX-092's derivation (last turn's timestamp,
  or `createdAt`), so a pre-MAX-093 row reads back identically to how it read before this
  ticket. `MaximizeSchemaV1`'s version number does not move, for the reason
  `distanceSplitsJSON`'s doc comment already gives: this schema has never been promoted to
  CloudKit production (A8), so the additive-only immutability rule has not started
  applying.
- **CloudKit's restrictions were kept, not cleaned up.** No new `@Attribute(.unique)`, and
  every new non-optional column carries a default.
- **Not verified by CI beyond compilation.** `MaximizeStore.swift` is App-layer and CI
  never executes it (tracker R2, R13) — the SwiftData predicate logic (the
  `subjectKindRawValue`/`workoutUUID` compound predicates, the training-scope equality
  query) is reviewed by eye against `FakeChatThreadRepository`'s CI-checked behaviour, not
  run. See the PR's **Needs device verification** section.

---

## Risks

| # | Item | Impact | Status |
|---|---|---|---|
| R1 | No Swift toolchain in the dev container; `download.swift.org` blocked | CI is the only gate | Accepted — mitigated by fat-core architecture + macOS CI |
| R2 | No device/simulator in the loop | HealthKit flows, UI, on-device performance unverified until a human checks | Accepted per direction. PRs must list what needs device verification |
| R13 | App-layer wiring is compiled but never executed | A defaulted parameter silently selected a no-op store — in **two** files, the second added the same hour the first was found; nothing in CI could see either | The stub is deleted, so there is nothing to default to. No production call site may default to a repository that can resolve to a no-op |
| R14 | CI is a hosted-minutes dependency | The whole merge gate vanished mid-session when the Actions allowance ran out — every job, including Ubuntu, failed in 2s with no runner | Repo is public, so standard runners are free and uncapped. Core suite moved to Linux (1x) so only `xcodebuild` needs macOS |
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
| 2026-08-05 | **MAX-109**: a day's prescription is indexed by discipline — one plan record, one version, two slots per weekday (A17) | Two plan records would make `Score.planVersion` ambiguous and split `PlanCalendar`, the context builder's coherence guard and MAX-011's no-back-dating rule in half, to buy the ability to revise lifting without restating running — a cost every other plan field already pays for free via `PlanAuthoringSession`. Two slots keep `WeeklyTemplate`'s totality (rest explicit on both sides), and because the plan is a JSON blob the lift slot decodes with `decodeIfPresent` to rest, so no stored prescription changes and no historical score becomes irreproducible |
| 2026-08-05 | **MAX-109**: effective days count obligations, not days (A19) | Extending `contains(where: \.isEffective)` to two disciplines says "a day with two obligations is satisfied by meeting either one", which makes lifting decorative — the opposite of what "the plan should account for both" asks. Two *attempts at one* obligation still resolve best-of; the warm-up-jog reasoning is untouched. Landable because on a one-session day the two countings are identical, so no historical figure moves |
| 2026-08-05 | **MAX-109**: lifting is scored on adherence, not volume; manual entry stays a non-goal (A20) | HealthKit carries no sets, reps or load, so the only alternative is the athlete typing them — PRD §3's "the thing being killed" and the direct negation of §2's north star. Adherence delivers what the ask actually needs (skipping the lift costs something) with zero taps; a volume rubric obliges the app to become a lifting logger, which §13 names as the top execution risk. The cost is stated rather than hidden: adherence cannot tell a hard session from a token one |
| 2026-08-04 | **MAX-034**: `WorkoutIngestionPipeline.enrich` extracts and stores samples (HR series, route) before resolving the plan, not after | Fixed a permanent-data-loss bug: `enrich` previously returned before `WorkoutSampleExtractor.extract` ran whenever no plan governed the workout's day, so every run predating the athlete's first plan version kept no HR curve — and MAX-031's advancing anchor never revisited it. The curve is a fact about the run, not the plan; only derived metrics (§9, measured against the plan's cap) stay gated on plan coverage. `IngestionPipelineDiagnostic.storedWithoutPlan` now documents that samples are stored either way. Found in the same pass: `.workoutPredatesEveryPlan` can never be completed later — MAX-011's version/`effectiveFrom` ordering forbids a plan from ever back-dating earlier than one that already exists — unlike `.noPlanAuthored`, which the lazy path does complete once a first plan is authored |

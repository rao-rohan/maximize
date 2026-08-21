# Maximize — Project Tracker

**Last updated:** 2026-08-06
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
| P3 | ~~`Plan` records **no durations at all**~~ **Closed.** MAX-131 gave the plan `ScheduledSession.durationSeconds` and `RubricReference.scheduledDuration(fraction:)` (the rubric half); MAX-149 gave `Plan.minimumSessionDurationSeconds` and taught `WorkoutClassifier.isFragment` to read it (the classifier half); **MAX-151 authors it** — `StandardPlanSeed` states 600 s, the authoring screen edits it, `PlanProposal` can propose it | MAX-013 | **Genuinely closed, not only expressible.** A first-time athlete's app now seeds a floor, an athlete can edit or clear it, and a mis-started HR-only treadmill run under the seeded plan classifies as a fragment end to end (`FragmentDurationFloorTests`). Every plan already on disk still keeps `nil` (D1, no migration) — a stored plan authored before MAX-151 states no opinion until its athlete revises it |
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
| MAX-111 | ~~**Stop scoring lifts against the running rubric**~~ — stop-gap ahead of MAX-109. **Removed by MAX-168**, which replaced the blanket `isRun` refusal with `ActivityType.isScoreable` plus two conditions read off the plan and the record. What it was protecting is still protected, from further down the path: a lift is scored only when the band that matched it *names* `.lift`. A ride, a hike and a walk stay permanently unscored | MAX-109 (spec) | Sonnet ✅ → superseded by 168 |
| MAX-090 | Chat-first product spec: plan generation and Q&A through chat | Owner | **Opus** 🔒 ✅ |
| MAX-091 | Run both Claude clients on the Sonnet tier at `medium` effort | Owner, cost | Sonnet 🔒 ✅ |
| MAX-092 … MAX-104 | The chat-first build, decomposed from MAX-090 | MAX-090 | see below ✅ |
| MAX-109 | Lifting product spec: plans account for lifting and running | Owner | **Opus** ✅ |
| MAX-128 … MAX-143 | The lifting build, decomposed from MAX-109 | MAX-109 | see below ✅ |
| MAX-126 | **"No verdict by design" is a state** — a lift stops being drawn and spoken as a run awaiting a score | MAX-111 | **Opus** ✅ |
| MAX-150 | **Copy and absence voice: the chat and dashboard surfaces** — split from MAX-104 so the finished half does not wait behind the lifting build | MAX-104, split | Sonnet ✅ |
| MAX-152 | **The chat's waiting and streaming states** — the full ladder between "sent" and "answered", and every stream failure as a designed state with words | Owner | **Opus** ✅ |
| MAX-154 | **Error handling, audited app-wide** — every failure path outside chat swept as a set, the failure-to-copy mapping moved into the core, and the inventory recorded below | Owner | **Opus** ✅ |
| MAX-155 | **An HTTP status code reaches the athlete's screen** — `PlanDraftingFailure.description` interpolates `PlanProposalModelError.description` in `ChatModel.noteDraftingFailure`, so "…returned an unexpected status (400)." renders on the plan proposal card. Fixed with a sibling to `ChatFailureNotice` (`PlanDraftingNotice`) rather than a case added to it — see write-up below | MAX-154 | Sonnet ✅ |
| MAX-156 | **`ScoringError.description` interpolates a workout identifier and a date** — latent, not leaking today, and one `.public` log line away from being a real one. Fixed: the two payloads are gone from `description`; the enum's own associated values are the deliberate channel a caller reaches for instead — see write-up below | MAX-154 | Sonnet ✅ |
| MAX-153 | **The chat shell** — composer, thread list, sheet chrome. The design pass the chat's *shell* never had | Owner | **Opus** ✅ |
| MAX-157 | **The fact sheet tells Claude "days" over a count of obligations** — `TrainingFactSheet`'s "Effective days" line is the same MAX-134 caption bug one layer into the prompt, not just on screen | MAX-140 | Sonnet ✅ |
| MAX-161 | **First-run experience spec** — there is no first-run path in the app at all; a fresh install has no Health request, no plan, no key, and nothing pointing at any of them. Spec + A23/A24, decomposed into MAX-162…167 below | Owner | **Opus** ✅ |
| MAX-162 … MAX-167 | The first-run build, decomposed from MAX-161 | MAX-161 | see below ✅ |
| MAX-169 | **A store that will not open is a designed state, not a brick** — the whole-store failure is named once, at the root, instead of nine screens each reporting their own; a retry where one could work and none where it could not; the additive-schema migration question settled. **Closes the store half of R15** | MAX-154 | **Opus** ✅ — see the MAX-169 section below |

**MAX-161.** [docs/FIRST-RUN-SPEC.md](./docs/FIRST-RUN-SPEC.md). Verified by search: no
onboarding, welcome or first-run surface exists anywhere under `App/`. The spec argues
*against* building an onboarding flow and proposes one new screen, one new card and two
edits instead — see its §11. Two findings are defects rather than gaps, and both are
recorded here because they are cheap to lose:

- **The first plan's default effective date silently strands the 90-day backfill.**
  `AnchoredIngestionPolicy.standard` fetches 90 days on the first pass; `.firstPlan`
  suggests `startOfTrainingWeek()`; a workout on a day no plan governs can never acquire
  derived metrics, because MAX-011 forbids a later version reaching back. So the default
  permanently strands nearly everything the first pass captured, and nothing on screen says
  how many runs that is. **MAX-165 is the one ticket in the set that prevents permanent data
  loss, and it is pure core logic CI proves end to end.** Amendment A23.
- **`requestReadAuthorization()` has exactly one call site**, in the Settings *sheet*, behind
  a toolbar button. The iOS Health sheet is one-shot: a fresh install can register the
  observer query, receive nothing forever, and show an empty list whose copy is about a
  permission never requested. MAX-163.

Reported and deliberately **not taken**: a workout that syncs *after* the first plan is saved
but is dated before its effective date is permanently unscorable, and nothing tells anyone
(spec §7.4). A late Watch sync or a Health import from another app does this. Its own ticket.

| ID | Ticket | Source | Tier |
|---|---|---|---|
| MAX-162 | `FirstRunChecklist` + `FirstRunCopy` in core — four facts in, ordered steps and one next action out; extends the R10 banned-phrase test | MAX-161 | **Opus** 🔒 ✅ — see the MAX-162 section below for the seam MAX-163 and MAX-164 read |
| MAX-163 | The first-launch cover — one action, presents the Health sheet, claims no result | MAX-161 | Sonnet ✅ — see the MAX-163 section below for the gate and the recording |
| MAX-164 | The setup card on the Workouts tab, including the "set up, nothing recorded yet" window | MAX-161 | Sonnet ✅ — see the MAX-164 section below, including how it now reads MAX-163's device-lifetime recording |
| MAX-165 | **The first plan's effective date** — default covers what is captured; the excluded-workout count on screen. Revisions unchanged | MAX-161 | **Opus** ✅ **built ahead of the rest of this set** — see the MAX-165 section below |
| MAX-166 | The conversational route to a first plan, offered from the authoring screen. Droppable | MAX-161 | Sonnet ✅ — see the MAX-166 section below |
| MAX-167 | The API key section's purpose footer — what the key is for, what it costs, where it lives | MAX-161 | Sonnet 🔒 ✅ |
| MAX-172 | **The consolidated device-verification checklist** — every *Needs device verification* item from #101–#157, reordered into the sequence a person would actually run them in and ranked by risk, instead of thirty scattered PR sections | Owner | Sonnet ✅ |

Order: **165 alone first**, then 162 → (163 ‖ 164). 167 parallelises with everything; 166
last or never. **164 was built and first opened for review before 163 merged**; it has
since been updated to read 163's device-lifetime recording — see the MAX-164 section
below.

**MAX-172.** [docs/DEVICE-CHECKS.md](./docs/DEVICE-CHECKS.md). 92 checks gathered from 32
merged PRs (#101–#157), cross-checked against this document's own per-ticket sections.
Organised by the order a person actually works through them — first launch, ingestion and
scoring, chat, the screens, accessibility, then relaunch behaviour — rather than by ticket
number, and led by an eight-item "Run these first" section ranked against what the
tickets themselves flagged as highest-risk: R13 (app-layer wiring that compiles but never
executes, already responsible for two real defects), the every-launch Health nag three
separate tickets warned about, the store opening against two new SwiftData record types
for the first time, `tabViewBottomAccessory`'s first real use, chat's stall indicator (which
may not be reachable at all — see below), R16's silent-data-loss default, plan drafting's
storage boundary, and the mixed-day calendar glyph's own author calling its legibility "a
judgement nobody without a phone can make." A closing section records what a device visit
will not settle regardless of how carefully it's done: R10 (HealthKit read access can
never be confirmed), background-delivery timing, whether the Anthropic API emits `ping`
frames during a stall, prompt-cache engagement, and Keychain retention across a reinstall.
No source was changed — this is a document only.

**MAX-167.** One sentence, `FailureCopy.apiKeyPurpose`, shown as a footer under Settings'
existing "Anthropic API key" section — no new entry point, no test-the-key button, no
wizard step, per spec §6. It is a fixed literal with no data dependency, but it lives in
`MaximizeCore` rather than as a view literal anyway: `FailureCopy` is already the one
place this screen's copy lives, and a sentence about key handling is exactly the kind of
thing CI should be able to pin against the A5 tripwire rather than trust a reviewer to
reread on every future edit.

> Maximize calls Claude to score each workout and to answer questions in chat, using a
> key of your own — usage is billed to your Anthropic account, not Maximize's. Workouts
> are captured and stored without one; they are simply not scored until a key is added,
> and everything already recorded is scored once it is. The key stays on this device and
> is sent only to Anthropic. Create one at console.anthropic.com.

Four things it says, each the ticket's own requirement:

- **What the key is for** — scoring and chat, named plainly, plus the reassuring true
  fact that a workout captured with no key is not lost, only unscored, and is scored once
  a key exists (`WorkoutIngestionPipeline.completeIngestion(forWorkout:)`, MAX-033).
- **What it costs** — a payer (the athlete's own Anthropic account), never a figure. The
  model and effort are configurable elsewhere and any price quoted here would go stale.
- **Where it lives** — "on this device," not "in Keychain." No user-facing string
  anywhere else in this app names that framework — `AnthropicAPIKeyError`'s
  Keychain-referencing cases are `description`s written for a developer, never copy a
  screen shows — and this sentence keeps that pattern rather than starting a second one.
- **Nothing that would survive distribution unchanged.** No "secure," "safe," or
  "private" — words that would read exactly as reassuring in a shipped, multi-user app,
  which is the drift CLAUDE.md's A5 tripwire exists to catch. What replaces them is
  checkable fact only: who calls Claude, who pays, and where the key sits today.

Tested in `FailureCopyTests`: the whole-set properties every `FailureCopy` string
already keeps (unique, ends in a full stop, no digit, no framework/diagnostic name), plus
three tests scoped to this sentence — that it states the three required facts, that it
never uses the banned-after-distribution vocabulary, and that it never names Keychain.
`/security-review` run before merge (required — this PR touches key-handling copy); no
key material is read, logged, or rendered by this change. **Needs no device
verification**: the change is a `Text` view over a fixed string, nothing interactive.

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
| MAX-104 | Copy and absence voice, **app-wide** — absorbs MAX-086's other half | 098, 102 | Sonnet ✅ |
| MAX-104 | Copy and absence voice, **app-wide** — absorbs MAX-086's other half. Split: MAX-150 took chat+dashboard, MAX-104 took plan+workout | 098, 102 | Sonnet ✅ |
| MAX-150 | **Split from MAX-104**: the chat and dashboard half, taken now because those two surfaces are finished and drifting while lifting is still being built | 098, 102, 103 | Sonnet ✅ |

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
  Tuesdays" is not told yes by omission. **Superseded by MAX-141**: the lift slot is now
  a field a proposal sets, so the fixed sentence became a diffable "Lifts" section instead
  — see that row below. The instance-method shape stays, for a narrower reason (the run
  and lift slots' uneditable `durationSeconds`/`note`).
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

**MAX-150 took that copy pass, over the chat and dashboard surfaces only.** MAX-104 was
sequenced after the lifting build (135–140) so one pass could cover the lifting surfaces
alongside everything else, but chat and dashboard are finished and were drifting *now* —
the "Runs in this conversation" strip naming lift sessions with a header and an absence
sentence that both still said "runs" (the MAX-103 note above names it directly) is one
instance of several the inventory below turned up. MAX-104 keeps the lifting surfaces,
`App/Workouts/*` and `App/Plan/*`.

**The voice, stated once so MAX-104 can follow it rather than re-derive it:**

> Say what's true, in one plain sentence, using the noun the underlying data actually
> counts — "session" when a lift could be one of them, "run" only where the surface is
> run-only by construction (the drift charts, a workout thread scoped to a run). Absence
> gets a real sentence naming what's missing and why, never a blank or a generic
> placeholder, and two facts that are actually different — "nothing in this window" versus
> "too many to list", "not yet scored" versus "will never be scored" — stay two sentences.
> Never restate a fact the surface already stated in different words a few lines away.

**What the inventory found, and what moved.** Every string was traced to whether its
content depends on data — which case a state is in, or what it names — following
`RunsStripCopy`/`ChatConversationCopy`/`PlanCopy`'s own split, established as an actual
rule this ticket writes down for the first time: a string whose selection is driven by a
case of a **core-declared** type (`ChatModel.LoadState`, `RunsStripData.EmptyReason`,
`PlanProposalReview`'s own fields) belongs beside that type; a string tied only to an
App-layer load-state enum with no core type behind it (`ChatThreadListModel.LoadState`,
`ScoreCalendarModel`/`TrendTilesModel`/`DriftOverlayModel`/`TrendIntervalSelectionModel`'s
own `.failed` cases) is left as a view literal, because there is no core fact for CI to
pin it against — moving it would be relocating chrome, not closing a drift risk. Six
findings moved on that basis:

1. **`RunsStripCopy.text(for: .noSessionsInWindow)`** — "No runs recorded in this window
   yet." → "No sessions recorded in this window yet." The concrete instance named in this
   ticket's brief. `RunsStripView`'s own header ("Runs in this conversation" → "Sessions
   in this conversation") and its chip's accessibility hint ("Opens this run" → "Opens
   this session") are the same drift; the header stays a view literal per MAX-103's own
   rule (no data dependency), but its wording was wrong regardless of which layer it
   lives in. The omitted-count accessibility label *does* carry a data dependency
   (`omittedCount`'s pluralisation) and moved into `RunsStripCopy` alongside it.
2. **`TrendTileData.workoutDays`'s caption**, "days run" → "days trained".
   `Tallies.workoutDays` counts "at least one recorded workout, scored or not" — no
   discipline filter — so a lift-only day was already silently counted as a "day run"
   before this ticket. Same class of bug as (1), found by tracing every core string that
   interpolates or is chosen from a `Tallies`/`TrainingContext` fact against what that
   fact actually counts now, not what it counted when the sentence was written.
3. **`ChatModel.LoadState.notYetScored`/`.noVerdict`** and **`DisplayMessage
   .wasTruncated`/`.wasInterruptedByFailure`**'s captions — four strings in
   `ChatConversationView` chosen by a core-declared state, sitting beside two sibling
   cases of that same switch (`.failed`, `.threadNotFound`) that were already in
   `ChatConversationCopy`. Moved the remaining four in, closing the inconsistency rather
   than leaving half a state machine's copy in each layer.
4. **`PlanProposalCardView`'s "This proposal matches the plan already in force, field for
   field."** and its disclosure toggle's title (which interpolates `review.rowCount`) —
   the one and only literal on a card whose own doc comment says "this view decides
   nothing"; every other string it draws already reads off `PlanProposalReview`. Moved
   both in as `PlanProposalReview.noChangesInDiffText` and
   `.disclosureTitle(showingEveryRow:rowCount:)`.
5. **`DriftOverlayView` had the same sentence typed out twice, twice.** The "no runs /
   no curve" empty-state text and the "not enough points for a trend line" text were each
   hand-copied into two call sites reading the same core state
   (`HeartRateDriftOverlayData`/`DriftFigureSelection`'s `candidateCount`,
   `HeartRateDriftTrendlineData`'s `fit`/`points`) — a duplication risk regardless of the
   core/view question, and CLAUDE.md's "one consistent voice" is exactly what a
   hand-copied literal breaks first. Consolidated into one computed property per core
   type (`emptyStateText` ×2, `noFitExplanation`) plus the two accessibility labels that
   were interpolating a count inline (`chartAccessibilityLabel` ×2), so each sentence has
   exactly one place it is spelled.
6. **`ChatThreadListView`'s "No messages yet"** was hand-typed twice in one file — the
   row's visible caption and its VoiceOver label — for the same `preview == nil` fact.
   Consolidated into `ChatThreadListCopy.noMessagesYetPreview` (core), the smallest of
   the six findings but the same shape: two spellings of one absence that had no way to
   notice they had drifted apart, because nothing compared them.

**Reviewed and left alone, on purpose:**

- **`ChatEntryPoint`'s "Ask about this run"** and **`ChatThreadSubtitle.text(for:
  .workout)`'s "This run"** — checked against whether a lift can ever reach a workout
  thread. It cannot: `ContextBuilder.workoutContext(for:from:)` requires a stored
  `ledger` (a score), MAX-111 stopped lifts being scored, and `ChatModel` resolves to
  `.noVerdict` before a workout thread ever reaches `.ready`. "This run" is true for
  every workout subject a thread can actually reach today. Not a finding — verified and
  recorded so the next ticket does not re-open it.
- **Every screen's own `.failed` literal** ("Couldn't load the calendar.", "Couldn't load
  the summary for this interval.", "Couldn't load the runs in this interval.",
  "Couldn't resolve today's date.", "Conversations could not be loaded.") — each tied to
  an App-layer model's own load-state enum with no core type behind the case, the same
  shape `ChatThreadListModel.LoadState` already was. Left as view literals per the rule
  stated above; moving them would not close a drift risk CI could otherwise catch.
- **`ScoreCalendarFormatting.swift` (`App/Dashboard/`)** is a large, heavily
  data-dependent VoiceOver-sentence builder living in the App layer — every branch reads
  a `ScoreCalendarDayState`/`ScoreCalendarDay` (core types) and would, by this ticket's
  own stated rule, belong in `MaximizeCore`. **Not moved.** It predates this ticket, is
  extensively tested by device-adjacent review already (MAX-084, MAX-087, MAX-108's own
  notes), and relocating it is an architecture change touching a file this size, not a
  copy pass — flagged here as a real, pre-existing exception to the thin-shell rule
  rather than silently left for the next reader to rediscover.
- **The MAX-126 drift-overlay bug** — a lift counted as `DriftFigureSelection
  .ExclusionReason.notYetScored` and narrated as "1 run isn't scored yet, so nothing has
  decided whether it was an easy or long run" — is a **logic** bug (the exclusion
  category is wrong for a lift, not merely its wording), already reported and explicitly
  deferred to its own ticket by the report that found it. Read, confirmed still present,
  not touched.

**Strings not touched because another ticket owns their file — MAX-104's accurate
remainder:**

- **`App/Workouts/*`** in full (`WorkoutChatSectionView.swift`'s "Chat"/"Open chat" card
  copy, `WorkoutDetailView.swift`, `VerdictHeaderView.swift`, `HRCurveView.swift`,
  `CadenceBandView.swift`, `RouteMapView.swift`, `SplitsView.swift`,
  `SummaryTilesView.swift`, `MuscleGroupEntryView.swift`, `WorkoutDisplayFormatting.swift`)
  — explicitly out of this ticket's scope, and the lifting build still landing inside it.
- **`App/Plan/*`** in full (`PlanAuthoringView` and its formatting) — same reasoning,
  explicitly out of scope.
- **`ChatEntryPoint`'s workout-subject strings**, reviewed above and left alone on their
  merits rather than out of scope, but worth MAX-104 knowing they were checked: the
  moment a lift can open a workout thread (a lifting-build decision, not this ticket's),
  "this run" needs re-checking against that new fact.
- **`Domain/Tallies.swift`, `Domain/RestDayBudgeting.swift`, `Tallies/`** — MAX-134's.
  Not read for copy beyond confirming `workoutDays`'s counting rule for finding 2 above.
- **`Metrics/SummaryTileData.swift`, `Domain/WorkoutVerdict.swift`** — MAX-139's. Not
  opened.
- **`Plan/StandardPlanSeed.swift`, `Plan/PlanDraft.swift`, `Plan/PlanProposal.swift`,
  `Plan/PlanAuthoring.swift`** — MAX-146/MAX-148's. Not opened; `Plan/PlanProposalReview.swift`
  (this ticket's finding 4) is a different, unowned file.
- **`Scoring/WorkoutScorer.swift`, `Domain/WorkoutClassifier.swift`** — MAX-147/MAX-149's.
  Not opened.

**Done means, stated honestly.** `swift build`/`swift test` were not run — there is no
Swift toolchain in this container, and CI is the actual compiler. Every change here is a
string relocation or a wording fix with no branch or control-flow change, each new
core-side string carries a test, and every touched view still compiles to the same calls
it made before (a rename of the argument, not the call site's shape) as far as a
line-by-line read can confirm. **This is "it compiles and its tests pass, as far as
reading the diff can tell" — not a claim CI has confirmed**, per CLAUDE.md's own
distinction between the two sentences.

**MAX-152 — the chat's waiting and streaming states, and what a failure says.** The owner
asked for a loading state on a par with Claude's own, and — mid-ticket — for error
handling good enough that "the app should be good to use". Those turn out to be one
ticket, because both are the same question: between pressing send and reading an answer,
what does the app actually know, and does it say so.

**Before: one bit, three states, and a diagnostic.** `ChatModel.isStreaming` was asked to
mean "the request is open and nothing has come back", "text is arriving" and "text stopped
arriving but the connection is alive" simultaneously, and `WorkoutChatStreamingBubble`
drew the only thing available from a bit and a string — an ellipsis — for all three. On
the failure side, every `ChatStreamError` but one reached the transcript as
`ChatStreamError.description`: a `CustomStringConvertible` written for a developer reading
a value, complete with `(401)`, `stop_reason: refusal`, and the sentence the owner
actually hit on a device, *"The response was not a recognizable streaming reply"*.

**`ChatReplyPhase` is the ladder and `ChatReplyProgress` the only thing that moves it** —
eight rungs, in the core, decided from stream events and nothing else. The view branches
on the rung it is handed; it reads no timing and inspects no stream internals, which is
CLAUDE.md's central rule applied to a loading state rather than to a calculation.
`isStreaming` survives as a computed `replyPhase.isLive`, because two flags describing one
request are two flags that can disagree, and this one gates the composer.

**How a stall is detected, and the alternative that was rejected.** The obvious design is
a wall-clock watchdog: start a `Task.sleep`, call it stalled after N seconds of silence.
It was rejected because it puts the decision behind a task racing a stream, which is the
one shape this repo's CI cannot verify honestly — a test either sleeps (slow, flaky) or
injects a fake clock and proves only that the fake was called. The Messages API already
sends `ping` frames on an open stream, and a ping *is* the transport saying "I am here and
I have nothing for you" — the exact fact that separates a stalled reply from a working
one, delivered as an event rather than inferred from elapsed time. So `ChatStreamDecoder`
forwards it (it was dropped before), `ChatStreamEvent` gains a payload-free `.heartbeat`,
and `ChatReplyProgress.heartbeatsBeforeStall` — **two** consecutive beats with no token
between them, because the API may legitimately ping mid-reply and one beat would flag a
healthy stream — turns them into `.stalled`. The whole rule is a pure function tested to
the beat. **The cost is stated rather than hidden:** a connection that hangs and sends no
pings stays `.streaming` until the client's own idle timeout turns it into
`.failed(.interrupted)`, and whether real pings arrive during a real stall is a device
question, in the PR.

**A beat before the first token is not a stall.** "The model has not started speaking" is
what waiting already says truthfully, and calling that stalled would invent a fault out of
a model that is thinking — the state the indicator exists for. A stall is specifically a
reply that started and stopped.

**Why the animation is a shimmer, what was taken from Claude, and where it differs.**
Claude marks thinking with a gradient sweep travelling through text rather than with
pulsing dots or three bouncing ones, and that is the choice worth taking — for a reason
that is structural rather than aesthetic. **A shimmer needs words underneath it to travel
across.** Dots say "something is happening" and nothing else; a sweep over
`ChatConversationCopy.awaitingFirstReply` carries the state in copy first and motion
second, which is CLAUDE.md's "no information carried by hue alone" one channel over — a
state carried only by an animation vanishes the moment somebody turns animation off. It is
also ambient rather than metronomic: a pulse has a beat, and a beat in the corner of the
eye is what makes a loader nag. **Where it deliberately differs:** there is a live
accessibility complaint against Claude's own shimmer for being distracting
(anthropics/claude-code#6038), so this one runs slower than the usual implementations of
the technique (`Motion.waitingSweep`, 1.4s linear, no autoreverse), is **withheld
entirely** under both Reduce Motion and Reduce Transparency rather than shortened, and
ends hard — the instant the first token lands the indicator is gone, replaced by the
words, because an indicator that keeps shimmering beside arriving text is an app talking
over its own answer. **Rejected: staggered dots at 100–150ms**, which is the generic
loader this is deliberately not, and which fails the "words underneath" test outright.
**Rejected: `markiv/SwiftUI-Shimmer` as a dependency** — read for the technique (gradient,
mask, offset animated across the width), not added; this package has none.

`App/DesignSystem/Motion.swift` gains the `Motion` ramp alongside MAX-070's
`accessibleAnimation` seam, for the reason `Spacing` and the colour tokens exist: a call
site should say which motion it is, not how many milliseconds. Four entries, one per job.

**Every failure is now a designed state with words, and no case falls through.**
`ChatFailureNotice` is the single mapping from `ChatStreamError` to a sentence, exhaustive
with no `default`, plus three notices for the failures that are not stream failures (an
empty reply, a reply that could not be saved, a message that could not be sent). The copy
rules are tested mechanically: no numerals anywhere (the two cases carrying a status code
never print it), no wire vocabulary, no parentheticals, nothing interpolated — so no
health data can reach a notice by construction — every sentence distinct, and none of them
equal to the `description` it replaced. The four states of a key are four sentences: no
key stored (the shipped subject-worded sentences, moved rather than rewritten), a
keychain that would not answer, a key the server rejected, and — separately — being rate
limited. "Add a key" and "replace the key you have" are different actions, and a single
"check your API key" would send the athlete to stare at something present and
correct-looking.

**Retry is decided, not defaulted: no failure ever re-asks itself.**
`PlanProposalDrafting`'s one-automatic-retry policy was read and deliberately **not**
followed, on that type's own reasoning: its retry exists to put a *correction* in front of
the model when a reply's content could not be used, and none of these failures are content
failures. There is nothing to correct in "you are offline", so a second automatic call is
the same call, and a loop of them is A14's named failure mode — spending the owner's
credit unasked. So `canRetry` gates a button, one call per tap, and it is false wherever
`ChatStreamError.isWorthRetrying` is false: a missing key, a rejected key, a refusal and
an unreadable response all say what to do instead rather than offering a button guaranteed
to fail identically. A retry asks the same question from the same history (the failed turn
was never persisted, so nothing moved), appends no second question bubble, and **erases
nothing** — the dropped attempt and its notice stay above the answer that finally arrives,
which is the additive treatment D8 gives a correction one surface over.

**Reported, not done.** The two files outside this ticket's named scope that it had to
touch are `ChatStreamEvent.swift` and `ChatStreamDecoder.swift` — a payload-free case and
one `switch` arm, both additive, plus the two MAX-107 regression tests whose expectations
now name the `ping` they always contained. Nothing else in the stream path moved. And the
stalled rung is the one part of the ladder CI cannot reach end to end: `ChatStreamDecoder`
is proved to emit heartbeats and `ChatReplyProgress` is proved to fold them into
`.stalled`, but whether the live API emits them during a genuine stall is only answerable
on a device.

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
  identical — so **almost no historical figure moves**, and that is an acceptance criterion
  with fixtures behind it. **Corrected by MAX-134, which built it:** the unqualified claim
  is false, because §6.2 also resolves each obligation *against the workouts of its own
  discipline*, and a scheduled run day whose only recorded workout was a lift therefore
  moves from "recorded but unscored" (neutral, excluded) to a genuine miss. That is A19's
  own argument arriving from the other side — a lift silently covering a skipped run — so
  it is a correction, taken deliberately. The accurate statement of the criterion is **no
  historical day moves whose recorded workouts all belong to the discipline that day
  prescribed**, and that is the property MAX-134's sweep pins.
- **Lifting is scored on adherence, not volume (A20).** HealthKit has no sets, reps or
  load, so the alternative is manual entry — PRD §3's *"the thing being killed"*. The
  non-goal is **not** spent. The honest cost is stated: adherence cannot tell a hard
  session from a token one.

**One escalation, and it is not a ticket's to make.** §11.4 / A21: the lift scores already
written are wrong, D8 forbids overwriting them, and they are not scorer misjudgements —
counting them as such corrupts the correction-rate signal D8 exists to protect. The
recorded lean is to label them; the decision is the owner's, tracked as MAX-143.
**Answered (owner, 2026-08-05): label them.** A21 carries the decision and what it changed
about its own wording — the label is an additive *record*, not only a string, because the
thing that has to happen to these scores is an exclusion from a number, and a sentence in a
header excludes nothing. Built as MAX-143; see its paragraph below.

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
| MAX-132 | Seed bands for lift days; the `easy.wellOverCap` shadow | 131 | Sonnet ✅ |
| MAX-133 | Match a workout to its own discipline's ask | 129, 131 | **Opus** ✅ |
| MAX-134 | Obligations, not days: tallies, streak, rest-day budget | 129, 133 | **Opus** ✅ |
| MAX-135 | The calendar's mixed day | 134, **105** | **Opus** ✅ |
| MAX-136 | Context and fact sheet learn discipline | 129, 130 | **Opus** ✅ |
| MAX-137 | Plan authoring for two slots | 129 | Sonnet ✅ |
| MAX-138 | The plan screen shows both | 129 | Sonnet ✅ |
| MAX-139 | Workout detail for a lift | 130, 133 | Sonnet ✅ |
| MAX-140 | Trend tiles, honestly ("days run", the effective denominator) | 134 | Sonnet ✅ |
| MAX-141 | `PlanProposal` covers lift days | 129, **099** | Sonnet 🔒 ✅ |
| MAX-142 | ~~`TrainingContext` is per-session, not per-run~~ — **not needed**, MAX-095 landed briefed | 129, **095** | — ✅ |
| MAX-143 | ~~Decide what to do with lifts already scored as runs~~ — **owner chose: label them**, and it is built | 128 | **Opus** ✅ |
| MAX-144 | ~~How adherence to a muscle-group prescription is judged~~ — **decided (A22)** | 129 | Owner ✅ |
| MAX-145 | **Enter muscle groups on a strength workout's detail screen** (A22) | 129, 144 | **Opus** ✅ |
| MAX-146 | Close the `rest.ranAnyway` shadow — the same defect as `easy.wellOverCap`, one band down (source: MAX-133) | 132, 133 | Sonnet ✅ |
| MAX-147 | The scorer's task text learns discipline (source: MAX-133) | 133, 136 | Sonnet ✅ |
| MAX-148 | A lift's duration and note become editable, proposable, and type-safe | 137, 141 | Sonnet ✅ |
| MAX-149 | Duration floor for fragments — **the classifier half of gap P3**; not yet wired to any author | 013, 131 | Sonnet ✅ |
| MAX-151 | **Author the duration floor** — `StandardPlanSeed` states one, the authoring screen edits it, `PlanProposal` can propose it. Without this MAX-149 never fires. (Depended on 146 only for file ownership of `StandardPlanSeed`, which is now released) | 149, 148 | Sonnet ✅ |
| MAX-151 | **Author the duration floor** — `StandardPlanSeed` states one, the authoring screen edits it, `PlanProposal` can propose it. Without this MAX-149 never fires — **closes gap P3 for real** | 149, 146, 148 | Sonnet ✅ |
| MAX-153 | **The chat shell: composer, thread list, sheet chrome** — the design pass MAX-092–103 never had over the shell its features sit in | Owner, 092–103 | **Opus** ✅ |
| MAX-165 | **The first plan's date covers captured history** (A23) — `.firstPlan`'s suggested `effectiveFrom` reaches back over the 90-day backfill instead of stopping at this week's Monday, and the authoring screen states in figures how many already-recorded workouts a candidate date would strand. **Closes R16.** Revisions and D1 untouched | 011, 033, 080 | **Opus** ✅ |

**MAX-153 — what was decided, what was rejected, and what it is blocked on.**

The owner's ask was "ensure our chat interface is top shelf; look online for examples",
plus, mid-ticket, "make sure the input is a Liquid Glass input with good button sizing"
and "the app should be good to use."

**Decided, and in the core where CI can see it.**

- **`ChatComposerSendControl`** — four states for one 44pt box (`.send`, `.unavailable`,
  `.awaitingReply`, `.stop`), resolved from `canSend`/`isStreaming` plus a
  `ChatComposerCancellation` parameter. Streaming outranks `canSend` unconditionally.
  Enabled and disabled send draw the **same glyph** so the target never changes shape
  under a keystroke; every state is spoken distinguishably, because the visual difference
  between two of them is a tint and `CLAUDE.md`'s hue rule applies to controls as much as
  to charts.
- **`ChatTranscriptFollow`** — follow-or-hold. Your own message always scrolls; incoming
  content scrolls only if you were already at the bottom; **focusing the composer no
  longer drags a scrolled-up reader down**, which is a deliberate departure from the
  pre-153 behaviour and the ticket's most user-visible change. Unseen activity is a
  **flag, not a count**, because the unit of arrival in a stream is a token — a counter
  would read "New (417)".
- **`ChatThreadListPresentation`** — recency banding (Today / Yesterday / Previous 7 days
  / Previous 30 days / Earlier), newest band first, empty bands never emitted; a
  Messages-style compact timestamp ladder (`now`, `12m`, `5h`, `Yesterday`, `Tue`,
  `3 Aug`, `3 Aug 2025`) built from `CalendarDay` arithmetic rather than `DateFormatter`
  so it is assertable on Linux CI; the row's scope line; and the whole VoiceOver sentence.
- **Copy moved to `ChatThreadListCopy`** — the empty and failed sentences the view held as
  literals, following MAX-150's precedent rather than opening a second voice.

**Rejected, with reasons.**

- **A tinted badge for "something arrived while you were away."** Information by hue
  alone. The label carries it: "Jump to latest" against "New reply".
- **A stop button during a stream, today.** `ChatModel` has no cancellation, and a stop
  that does not stop is worse than none. `.awaitingReply` shows progress; the `.stop`
  state exists, is tested, and turns on when one call site passes
  `cancellation: .available`.
- **`Text(_:style:.relative)` on a list row.** Wider than the title it competes with above
  default Dynamic Type, re-lays-out every minute, and says "0 seconds ago". Kept for
  VoiceOver, where width is free.
- **A counter of unread messages.** See above.
- **Scope on every row.** Nil for a workout thread (the title is already the run's date)
  and for a training thread still titled by its own window — otherwise the row prints one
  string twice.

**Research citations** (all in the PR, all read for this ticket): Apple's HIG 44×44pt
minimum tap target with the visible control permitted to be smaller than the region;
`GlassEffectContainer` + `glassEffect` as the iOS 26 way to let the system merge and morph
adjacent glass rather than hand-rolling a blur; `ScrollPosition` /
`defaultScrollAnchor(.bottom)` and the jump-to-latest pattern for transcripts;
Messages/Mail/Notes for the recency bands and the compact timestamp ladder; the
grow-to-a-ceiling-then-scroll composer behaviour common to iMessage, WhatsApp and
Telegram.

**Installed, after MAX-152 merged.** The composer and the transcript's `onChange` handlers
live in `App/Chat/ChatConversationView.swift`, which MAX-152 held while it was in flight;
MAX-153 wrote the views against a documented seam and installed them once that file was
free. What landed in the file:

- The hand-rolled `TextField` + `Image` row and the `.glassChrome(.toolbar)` wrapped round
  it are gone, replaced by `ChatComposerView`. **The outer glass went with them** —
  `ChatComposerView` carries its own `GlassEffectContainer`, and a second glass modifier
  round a view that glasses itself is chrome over chrome.
- The send control resolves from **MAX-152's `replyPhase`**, not from a boolean:
  `ChatComposerSendControl.resolve(canSend:replyPhase:)`. `ChatModel.isStreaming` is
  itself `replyPhase.isLive`, so there is one authority on "a reply is in flight". The
  composer does not distinguish waiting / streaming / stalled — those are three things to
  say in the transcript, and `ChatPendingReplyView` says them there.
- Every unconditional `scrollToBottom` became a `ChatTranscriptFollow` directive, including
  the focus handler that used to drag a scrolled-up reader to the end.
- **A third change kind, `.reflow`,** was added for MAX-152's shimmer. The waiting
  indicator appearing and a stall caption growing both move the content, so a reader at
  the bottom stays pinned — but neither is a reply, so neither may badge somebody who
  scrolled away. Telling them "New reply" because a placeholder resized is the app crying
  wolf about its own layout.
- `.defaultScrollAnchor(.bottom, for: .initialOffset)` so a thread with history opens at
  its newest turn. `for: .initialOffset` deliberately: where the scroll view *starts* is
  the platform's question; what it does when content grows is `ChatTranscriptFollow`'s,
  and two mechanisms answering one behaviour is how they drift.
- **Retry is MAX-152's and stays in the transcript**, beside the failure notice that
  explains what went wrong. The composer offers none — two retry affordances in two
  registers is worse than either alone.
| MAX-151 | **Author the duration floor** — `StandardPlanSeed` states one (600s), the authoring screen edits it, `PlanProposal` can propose it. **Closes gap P3 for real** | 149, 148 | Sonnet ✅ |
| MAX-158 | **Schema vocabulary reaches the athlete on a rejected proposal** — `PlanProposalError.description` says things like *"The reply left out `liftKind`, which the plan schema requires."* No PII and no status code, so not a privacy defect; but it names wire fields at a person who cannot act on them. MAX-155/156 left it deliberately (MAX-151 owned the file) — see write-up below | 155 | Sonnet ✅ |
| MAX-159 | **A recorded-but-unjudged workout outranks another obligation's settled miss** — a Tuesday whose lift was recorded but unscored and whose run was missed draws `.noVerdict`, and its sentence names neither. §7.2's principle says change it, but the same ordering governs single-obligation days shipped since MAX-061, so it moves historical cells and wants a designed state | 135 | **Opus** ✅ |
| MAX-160 | **Should a labelled miscategorised score leave the athlete's own average?** MAX-143 excluded it from the scorer-quality metric only; MAX-140 confirmed the average stays per-workout and declined to widen. A product decision, then a `Tallies` change | 143, 140 | Owner / overseer ✅ |
| MAX-170 | **The stall detector's ping assumption had never met the live API** — MAX-152's two-beat threshold rested on an unverified claim about ping cadence that the API's own documentation contradicts. The rule now calibrates against what each stream demonstrates rather than against a constant | 152 | **Opus** ✅ — see the MAX-170 section below for what was established, what could not be, and how the design tolerates being wrong |
| MAX-160 | ~~Should a labelled miscategorised score leave the athlete's own average?~~ **Owner decided: yes.** `TalliesCalculator.computeAverageScore` now skips a labelled score; the caption says when one was excluded and a fact-sheet line says why nothing is left when every scored workout was. See the MAX-160 note below | 143, 140 | Sonnet ✅ |
| MAX-168 | ~~**Open MAX-111's lift ingestion gate**~~ **Opened, on three conditions.** The blanket "not a run → no score" is gone; a lift is scored when (1) it is a lift — a ride and a hike stay out, permanently, (2) the athlete has said what it worked (A22, which the pipeline now honours rather than only the header stating it) and (3) the plan version in effect matched it to a band that **names** `.lift`. Condition 3 is the answer to "what about a plan whose rubric MAX-173 has not reached": it is read off the stored rubric, so a stale `rest.ranAnyway` can no longer stamp a lift *"Ran on a scheduled rest day."*, and an unprescribed lift is not scored against the catch-all either. **Nothing on the device is scored by merging this** — see the MAX-168 note below | 111, 132, 133, 146, **173**, **145/A22** | **Opus** ✅ |
| MAX-173 | **A rubric fix can reach a stored plan** — authoring a revision adopts the bands this build ships, stated on screen and declinable, as a **new plan version**. Closes the D1 gap that made every seed-side rubric correction unreachable on a device with a plan. **Unblocks MAX-168.** Opens **R17** | 080, 132, 146 | **Opus** ✅ |
| MAX-175 | **The app does not invent** — one principle, two expressions: the honest-refusal rule now holds over the *set* of model-facing prompts rather than in four literals that each remember it separately, and *no data, no judgement* is written down as a rule with tests. **The premise it was dispatched on was wrong** — the constraint was reported missing from chat and is not; see the MAX-175 section below | 174 | **Opus** ✅ |
| MAX-176 | **Per-workout strain, computed at ingestion** — the app now measures what a session *cost*, beside everything else it measures, which is whether the athlete did what was asked. A zone-weighted integral of the stored HR curve (Edwards' summated-zone score over the plan's cap-anchored zones), in **zone-weighted minutes**, unbounded, computed once and stored in a new nullable `strainPoints` column. **No curve, no strain** — nil, never zero. A lift gets one and it is heart-rate only (A20). **Nothing already stored is rescored or moved**; existing workouts read back with no strain until something re-runs their metrics. Consumed by MAX-177 (the tile and the prompt line) and MAX-178 (the rolling sums), both merged — see the MAX-176 section below | 174, 175 | **Opus** ✅ |
| MAX-177 | **Strain reaches the detail view and the prompt** — one tile (`SummaryTileData.strain`, appended after FR-1.5's own six rather than interleaved), one fact-sheet line, both disciplines (`DerivedMetricKind.strain` is `.anyDiscipline`). Nil states its own absence and distinguishes "no heart-rate data" from "heart-rate data but strain not yet computed" (MAX-176 rescored nothing already stored). The fact-sheet line states the unit and disclaims a bounded rating and a verdict on load — on every workout, not only a lift's. See the MAX-177 section below | 176 | Sonnet 🔒 ✅ |
| MAX-178 | **Acute vs. chronic load balance** — rolling 7-day and 28-day sums of `DerivedMetrics.strain.points`, and their ratio, in `LoadBalanceCalculator` (`TalliesCalculator`'s own shape). The ratio's denominator is the chronic sum *scaled to a week* (÷4), not the raw 28-day total — the two are not interchangeable, see the MAX-178 section below for why. A workout with no strain figure is skipped from both sums, never zeroed, and the gap is counted so a caption can say how many sessions a window is missing (MAX-176's own instruction). **The first 28 days of an athlete's recorded history are `.buildingHistory`**, a designed absence tile, never a ratio computed from a handful of days. No verdict, no colour, no "high"/"low" wording anywhere in the figure — reporting only | 176 | Sonnet ✅ |
| MAX-179 | **Per-muscle fatigue from the entries A22 already collects** — one session per group, weighted by its duration, decayed on a 48-hour half-life. States in its own doc comment what it cannot know (no sets, no reps, no load) and that **A20's tripwire governs the "just add a weight field" follow-up, not A22's permission**. A group never logged has *no* figure; a group logged a fortnight ago is *fresh* — a different fact. **Departs from the brief's "the last session" in one deliberate place**, which the MAX-179 section below sets out | 174, 175, A20/A22 | **Opus** ✅ |
| MAX-180 | **The muscle map, drawn** — `MuscleFatigueMark` bands MAX-179's reading into five states (`.notLogged`/`.fresh`/`.light`/`.moderate`/`.high`) and marks each with a non-hue geometric channel (fill fraction + dashed outline + glyph), extending `WCAGContrastTests`'s hue-alone test with a third representation rather than a parallel suite. `MuscleMapView` draws it on a flat content surface with `@ScaledMetric` throughout, and `WorkoutDetailView` composes it unconditionally (it is the athlete's state, not the workout's). A group never logged draws dashed-and-glyphed, never a coloured "at rest" fill. **Adapted after #173 landed on top of it**: the "last worked" caption reads `mostRecentlyWorkedAt`, not the removed `elapsedDays`, and the day count is now calendar-correct via `CalendarDay.days(until:)` rather than fixed 86,400-second blocks. See the MAX-180 section below | 179 | Sonnet ✅ — merged as `ae85d0a`. Compiles and its core tests pass in CI; **nothing about how it draws is verified** — see the PR's device checks |
| MAX-181 | **The fact sheet renders the lift slot** — `TrainingFactSheet`'s plan block now names each weekday's lift ask beside its run ask, tagged `Lift:`, omitted rather than stated when the plan asks nothing of the slot. Closes MAX-174 §5.3's G2, and MAX-136's open item. **Also closes the more severe consequence MAX-175 found and declined to fix**: `PlanProposalInstruction` tells a drafting model to restate each weekday's lift ask from this same fact sheet unchanged — it could not, so an accepted revision could silently zero out an athlete's whole lift schedule. See the MAX-181 section below | 174, 175 | Sonnet ✅ |
| MAX-184 | **An audit of the chat surface and its context continuity** — `docs/CHAT-AUDIT.md`. Seven defects, the worst of them a **"New chat" button that is inert on the ordinary path** and a **workout chat card that is not tappable and never refreshes**; a ranked craft list; and a position on the owner's central ask. **Nothing dangerous was found** — no data loss, no leak off the device, no crash. The one context finding that matters is not the one it was dispatched on: **strain, acute:chronic load balance and per-muscle fatigue reach a tile and reach no prompt**, so a training thread asked "am I ramping too fast" correctly refuses to answer a question the app has already computed. Proposes MAX-185–201; MAX-193 is blocked on a new amendment. See the MAX-184 section below | 090, 152, 153, 170, 177, 178, 179 | **Opus** — audit only, no behaviour changed |
| MAX-189 | **A failed thread delete is silent, and the row does not come back** — §2.5. Turn the `try?` into a `do`/`catch`, restore the row on failure, state the failure in `ChatThreadListCopy`'s voice matching `couldNotSaveReply`. One string, one state. **Needs device verification**: swipe to delete with the store failing, confirm the row returns and the message appears | 184, 150, 152 | Haiku 🔲 ready |

**Four collisions the overseer must respect.**

1. **MAX-105 before MAX-135, and MAX-105's brief must carry A17** — see the MAX-105 note
   above. Sequence 129 → 105 → 135.
2. ~~**MAX-095's brief must carry LIFTING-SPEC §10.2 before it is written.**~~ **Done —
   MAX-095 landed briefed, so MAX-142 is not needed.** Its roll-up is one line per
   *session*, discipline-tagged, with fields that do not apply omitted rather than
   nil-rendered, and the cap counts sessions. **The claim that followed — that the plan
   block needs no further edit — was wrong, and MAX-136 verified it against the code.** The
   block iterated `weeklyTemplate.entries` and printed `entry.session`, the *run* slot;
   MAX-129 put the lift ask on `Entry.liftSession`, so it never appeared there. §10.2's
   plan-block half stayed open through MAX-136, MAX-174's competitive read caught it again
   as G2, and **MAX-181 closed it**: each weekday's line now names the lift ask too, tagged
   `Lift:`, omitted rather than stated on a day that asks for none. See the MAX-181 section
   below.
3. ~~**MAX-110 adds `.lift` to `RestDayBudgeting.costTier` without reordering the existing
   cases.**~~ **Respected — MAX-128 inserted `.lift` between `.easy` and `.hard` and
   renumbered nothing else**, so every existing comparison is unchanged and no historical
   day converts differently. `Domain/ScheduledSession.swift` is still touched by 129 and
   131 and they are in dependency order.
4. **MAX-104 runs after 135–140.** It already absorbs MAX-086's absence-voice half; it
   should absorb the lifting surfaces in the same pass rather than spawning a follow-up.
   **Split, since: MAX-150 took the chat-and-dashboard half of that pass early** (those
   two surfaces were finished and drifting while lifting was still mid-build), leaving
   MAX-104 the lifting surfaces plus `App/Workouts/*` and `App/Plan/*`.

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
| `RubricEvaluator.evaluate` | ~~`planDay.scheduledSession.kind` picks the bands~~ **the workout's own discipline's ask, as of MAX-133** | MAX-133 ✅ |
| `RestDayBudgeting` / `TalliesCalculator` | ~~`PlanDay.canBeMissed`, `costTier`~~ **each day's obligations, as of MAX-134** | MAX-134 ✅ |
| `ScoreCalendar.dayState` / `agreement` | ~~the day's single prescribed kind~~ **each day's obligations, and the scored workout's own slot, as of MAX-135** | MAX-135 ✅ |
| `WorkoutFactSheet` | ~~`planDay.scheduledSession`~~ **the workout's own slot, as of MAX-136** | MAX-136 ✅ |
| `TrainingFactSheet` plan block | ~~`entry.session` — the lift slot is unrendered~~ **both slots, as of MAX-181** | MAX-181 ✅ |
| `PlanDraft` setters, `PlanAuthoringError` | ~~the run slot only~~ **both, as of MAX-137** | MAX-137 ✅ |
| `PlanDisplayData.WeekdayRow` | ~~one kind/distance/note per weekday~~ **both slots, as of MAX-138** | MAX-138 ✅ |
| `TrendTileData` planned mileage | sums `planDay.scheduledSession.distanceMeters` | MAX-140 |
| `PlanProposal` (MAX-099) | ~~validates the same shape `PlanAuthoringSession` does~~ **both slots, as of MAX-141** | MAX-141 ✅ |

**MAX-141 does need updating, and its brief should say so.** `PlanProposal` validates
against `PlanAuthoringSession`'s rules; those rules did not change for the run slot, so it
still compiles and still produces valid plans — but a proposal it accepts can only ever
prescribe rest on every lift slot, which is now a silently incomplete plan rather than the
only expressible one. Since the owner has reaffirmed that **the plan is configured through
chat**, that ticket is the real authoring path, not MAX-137's form.

**MAX-141 — done.** A `PlanProposal.Day` now carries the lift slot's ask alongside the
run slot's: `liftKind` and `liftMuscleGroups`, matching exactly the two fields
`PlanDraft.DayDraft`'s own setters expose (`setLiftKind`, `setLiftMuscleGroups`) — a note
or a duration is proposable through neither the screen nor chat yet, so the wire schema
was not widened to accept either. Decisions, and what each cost:

- **`prescribable` stays closed; a second, parallel vocabulary opens instead.**
  `ScheduledSessionKind.prescribable` still excludes `.lift` and still gates the run
  slot's `kind` field — widening it was the one thing LIFTING-SPEC §2.2 forbids, since it
  would let a reply prescribe a lift where the run ask goes. The lift slot gets its own
  wire field, `liftKind`, read against `ScheduledSessionKind.liftPrescribable` through a
  new lookup (`PlanProposal.liftKind(named:)`) with its own error case
  (`unknownLiftKind`). **A latent gap this closed as a side effect**: `sessionKind(named:)`
  previously searched `ScheduledSessionKind.allCases`, so a reply that sent `"kind":
  "lift"` for the run slot would have decoded successfully before this ticket — nothing
  in the vocabulary a model was *shown* offered the word, but nothing refused it either.
  Restricting the lookup to `.prescribable` closes that door explicitly and is pinned by
  `testALiftProposedIntoTheRunSlotIsRefused`.
- **`liftKind` is required per weekday, not `decodeIfPresent`-and-default-rest.** This
  was the real fork. `WeeklyTemplate`'s own wire format defaults an absent lift slot to
  rest (§2.3, MAX-129) precisely so a pre-lifting plan needs no migration — a strong
  precedent for doing the same here. Rejected anyway: `PlanDraft.applying(_:)`'s own doc
  already commits to "the proposal is a whole plan, not a patch" for the run slot, where
  every weekday's `kind` is required even though `"rest"` is one of its legal values.
  Making the lift slot's presence optional while the run slot's is not would be one
  proposal shape following two different rules for what silence means on the same day,
  and it would make "the model forgot to restate Tuesday's lift" indistinguishable from
  "the model means to drop it" — the first is exactly the kind of correctable mistake
  §4.5's one retry exists for, and a required field turns it into `missingField`, not a
  silent, unreviewable data loss. `liftMuscleGroups` stays optional (defaults to empty),
  matching `distanceMeters`/`note` on the run slot.
- **`applying(_:)` now replaces the lift slot outright, the same rule the run slot has
  always followed — carrying forward only `liftNote`/`liftDurationSeconds` while the
  lift kind is unchanged**, mirroring `carriedDurationSeconds(from:proposing:)`'s
  existing rule for the run slot's own uneditable duration. The consequence worth
  stating plainly: a proposal that restates the whole week *without* a weekday's lift
  (silence reading as `"liftKind": "rest"`) now reverts that day to rest rather than
  preserving it — this is what makes an unrequested drop of a lift day a `.changed` row
  on the card instead of an invisible merge, and `PlanProposalInstruction.taskDescription`
  was reworded to tell the model plainly to restate lift days from the fact sheet the
  same way it already restates run days.
- **`PlanProposalReview.liftNote` (the fixed "your lift days carry through unchanged"
  sentence) is gone, replaced by a "Lifts" section** — seven rows, Monday-first, diffed
  exactly like "The week." A lift is now a field a proposal can move, so it gets a row
  like every other field; a fixed sentence would have been strictly less honest than the
  diff once the diff could actually show one. `PlanProposalCardView`,
  `PlanAuthoringModel.PlanPrefillNotice` and `PlanAuthoringView` (App layer, not built by
  CI) were updated to match — no `swift test` coverage for that half, flagged under
  **Needs device verification** in the PR.
- **Rejected: proposing `liftDurationSeconds` or a lift `note`.** LIFTING-SPEC §4.3's
  worked example ("a lift, 45 minutes, lower body") names a duration, and it would have
  been easy to widen the schema to match. Not done, because `PlanDraft.DayDraft` itself
  has no `setLiftNote` or lift-duration setter yet — MAX-137 shipped only `setLiftKind`
  and `setLiftMuscleGroups` — so a proposal that set them would be prescribing through
  chat something the authoring *screen* still cannot edit, and the card's accept action
  hands the athlete a form that would silently ignore the field the model just set. This
  is real remaining scope (the duration half of LIFTING-SPEC §4.3's example), not
  finished here — it wants the ticket that gives `PlanDraft.DayDraft` those two setters
  first, so chat and the screen gain the ability together. **Superseded by MAX-148**,
  which gives `PlanDraft.DayDraft` both setters and `PlanProposal` both wire fields
  together, exactly as this note asked for.
- **`unknownMuscleGroup` and `liftRestDayIsNotEmpty` are new error cases**, not reuses of
  `unknownSessionKind`/`restDayIsNotEmpty` — each names a different field with a
  different vocabulary, and reusing the run-slot case would have pointed a retry at the
  wrong field's words. "A lift with no muscle groups named" is *not* one of these
  errors: `ScheduledSession.muscleGroups`'s own doc makes it a real, legal statement
  distinct from rest (A17), so the brief's suggested example of an invalid case was
  wrong — the actual invalid case pinned under test is a **rest** lift slot naming
  muscle groups (`liftRestDayIsNotEmpty`).

**MAX-148 closes the gap the paragraph above left open, plus a second one MAX-141 found
but did not fix: `setKind`/`PlanAuthoringSession` refusing `.lift` in the run slot at
the type level, not only in the picker.** Source: MAX-131 (which carried the fields with
no setter) and MAX-141 (which named both gaps explicitly and left them for "the ticket
that gives `PlanDraft.DayDraft` those two setters first").

- **`PlanDraft.DayDraft` gains `setLiftDurationSeconds` and `setLiftNote`.** Same shape
  as the existing lift setters: ignored while the slot is not `.lift` (nowhere legal for
  the value to go), and `setLiftKind` now clears both — alongside the groups it already
  cleared — the moment the kind leaves `.lift`, so a draft reached through this type's own
  setters can never make `liftSession()` throw.
- **`PlanProposal.Day` gains `liftDurationSeconds` and `liftNote` as real wire fields**,
  exactly the pattern MAX-141 set for `liftKind`/`liftMuscleGroups`: their own keys in
  `CodingKeys`, their own line in the rendered schema, `liftRestDayIsNotEmpty` widened to
  refuse a rest lift carrying either (not only muscle groups), and a non-positive duration
  refused through `liftSessionInvalid` — the same "reachable now" note the case's own doc
  carries.
- **The consequence worth stating plainly, mirroring MAX-141's own callout**: because both
  fields are now wire fields, `PlanDraft.applying(_:)` takes them directly from the
  proposal rather than carrying the athlete's existing value forward when the kind is
  unchanged. `carriedLiftDurationSeconds`/`carriedLiftNote` — the two carry-forward helpers
  MAX-141 wrote because there was nothing else to do — are deleted; the run slot's own
  `durationSeconds` keeps its carry-forward helper, because that field still has no wire
  representation (nothing prescribes a run's length yet). A model that wants to keep a
  lift's duration or note now has to restate it, the same as it already had to restate the
  muscle groups — `PlanProposalTests`' `testARestatedLiftIsAppliedFaithfully` was updated
  to send `liftNote` explicitly rather than relying on a carry.
- **The picker-only `prescribable` hole is closed at both layers named in the ticket.**
  `PlanDraft.DayDraft.setKind` now ignores `.lift` outright (a no-op, matching how a rest
  day already ignores a distance set on it), and `PlanAuthoringSession.weeklyTemplate(from:)`
  independently refuses a `.lift` run slot with a new `PlanAuthoringError.scheduledKindNotPrescribable`
  case — belt-and-braces, because `WeeklyTemplate` itself still does not forbid one, so a
  `PlanDraft` built from a stored `Plan` whose run slot already held a lift (however that
  happened) is refused at the door rather than saved as a plan judged against the wrong
  slot.
- **Authoring-screen density decision: a collapsed `DisclosureGroup`, not two more
  permanent controls.** Seven weekdays × two slots was already the screen's own stated
  concern (MAX-137); adding a duration Stepper and a note TextField as always-visible rows
  under every lift day would have added fourteen more controls to a screen that already has
  that many. Instead the two fields sit behind a `DisclosureGroup` beside the existing
  "Groups" menu, labelled with the pair rendered together (`PlanCopy.liftDetail`, "45 min ·
  lower body focus", or "Not set") so the row is scannable closed and only expands when an
  athlete actually wants to set a duration or note. **Rejected**: a sheet or separate
  per-day detail screen (too much navigation for two fields already inline for muscle
  groups) and a permanently visible Stepper + TextField pair (the density this ticket
  exists to avoid).
- **`PlanCopy.duration(_:)` and `PlanCopy.liftSession(_:)` learn to render the duration**,
  which is also what makes the diff work for free: `PlanProposalReview`'s existing
  per-weekday lift row already diffs the *rendered* string, so once that string includes
  the duration and note, a changed one is a `.changed` row with no new section or row-id
  needed — the ticket's "diff row for a changed duration/note" requirement is met by the
  rendering change alone, not by new diff logic.

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
- ~~**No behaviour change, and a lift is still left unscored** by MAX-111's ingestion gate.
  Nothing added here is reachable until MAX-133 matches a workout to its own discipline's
  ask; `RubricEvaluator` still reads `planDay.scheduledSession` for every workout.~~
  **MAX-133 landed: the evaluator now reads the ask of the workout's own discipline**, so
  this vocabulary is reachable the moment a rubric carries a lift band. A lift is still
  left unscored by MAX-111's gate — see MAX-133's paragraph for why that stays until
  MAX-132.
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
- ~~**Reported, not done: the classifier half of P3.** `WorkoutClassifier.isFragment` still
  tests distance only, so an HR-only treadmill fragment still reaches the scorer.
  LIFTING-SPEC §9.2 wants a duration floor there; the plan can now express one, and
  changing the classifier is a behaviour change this ticket's brief forbade.~~ **Closed by
  MAX-149.**

**MAX-149 — the classifier half of P3, and the argument for where the floor lives.** A
mis-started or accidentally split treadmill run — heart-rate data, no distance sample —
passed `WorkoutClassifier.isFragment`'s distance test (there was no distance to fail it
on) and reached the scorer as a real session, an immutable wrong score under D8.
LIFTING-SPEC §9.2 names this exactly and asks for a duration floor; MAX-131 reported it
rather than building it, because its brief forbade a behaviour change.

- **`Plan.minimumSessionDurationSeconds`, not a `WorkoutClassificationPolicy` fraction.**
  The two candidates were an absolute figure the plan version states — `heartRateCapBPM`'s
  own shape — or a third fraction alongside `fragmentDistanceFraction` in
  `WorkoutClassificationPolicy`. Rejected the second: that type's own doc already names its
  fractions a known, temporary gap against D1, held open only because they are *ratios* of
  a plan-stated quantity (the shortest prescribed run, the cap) rather than absolutes,
  pending "a `classification` block on a future plan version". Filing a brand-new
  free-standing threshold into a struct whose own comment says "this shouldn't really be
  here" would grow that gap rather than close it. A plan-relative fraction of the shortest
  prescribed run's *duration* was considered too, and rejected for a sharper reason:
  `ScheduledSession.durationSeconds` on the run slot is still carried-but-uneditable —
  MAX-137 and MAX-141 landed, but neither put a control on it, so nothing authors one — so
  a plan-relative floor would silently never fire for any plan on disk, which is the
  opposite of what the ticket is for. `minimumSessionDurationSeconds` sits directly on `Plan`, optional
  (defaulting nil, matching every field MAX-129/MAX-131 added), resolved once per plan
  version exactly like the cap.
- **Distance-tested runs are unaffected; the floor only ever answers the question the
  distance test could not ask.** `isFragment` now branches on whether the workout has a
  distance at all: if it does, the existing distance-fraction test runs exactly as before
  — a duration floor calibrated for "did this happen" has no business overruling a run
  whose distance already answered that, and a fixture pins a case where the two would
  disagree. Only a distance-less workout falls through to the duration floor, and only
  when the plan states one; a plan with no opinion asks no duration question, the same "no
  guessed threshold" rule the distance test already followed.
- **A lift cannot be caught by this floor, and it is not by luck.** `classify()` answers
  `.other` for any non-run before `isFragment` runs at all — `isFragment` is unreachable
  for a lift regardless of how aggressive the floor is. Pinned with a fixture using a
  floor long enough to catch a 45-minute lift, to make the claim more than "nothing tests
  it".
- **Nothing stored moves.** A hand-written pre-MAX-149 `Plan` payload — every key `Plan`
  already carried, no `minimumSessionDurationSeconds` key — decodes to a plan equal to the
  one this build authors with no floor stated, and the same fragment call matches under
  both. A plan that states no floor re-encodes without the key.
- **Reported, not done: authoring cannot carry the floor forward.**
  `PlanAuthoringSession.plan(from:effectiveFrom:)` builds every `Plan` field from
  `PlanDraft`, and `PlanDraft`/`PlanAuthoring.swift` are owned by MAX-148, in flight in
  parallel — out of this ticket's scope to touch. So a plan revision saved through the
  authoring screen today always produces `minimumSessionDurationSeconds == nil`, same as
  `StandardPlanSeed` (owned by MAX-146 at the time, and out of scope here) never setting
  one — **authoring the floor is MAX-151, not MAX-146**, which was the `rest.ranAnyway`
  shadow and is now merged. The domain type
  and the classifier are ready; nothing in this build can author a floor yet. That is
  follow-on ticket work, the same shape MAX-131 left `durationSeconds` in before MAX-137
  gave it an editor.

**MAX-151 — the three places the floor gets authored, and the value chosen for the
first one.** MAX-149 gave `Plan` the field and taught the classifier to read it, and
then reported, honestly, that nothing set it: `StandardPlanSeed` stayed silent, the
authoring screen had no control, and `PlanProposal` had no wire field — so every plan
on disk kept `minimumSessionDurationSeconds == nil` and the floor never fired. This
ticket is the follow-on MAX-149 named, taken in MAX-148's own shape (seed, screen,
proposal) rather than a new approach.

- **The seeded value is 600 seconds (ten minutes), and it is the real decision here.**
  A watch session carrying heart-rate data and no distance at all is overwhelmingly one
  of two things: a mis-started or HealthKit-split treadmill run — belt not moving yet,
  GPS never acquiring indoors, a stop tapped seconds after start — or a deliberate short
  session that genuinely has no distance sample, an indoor track with no GPS lock chief
  among them. The first shape is seconds to a couple of minutes; the second is rarely
  under ten. Ten minutes sits between them, and it is cross-checked rather than picked
  in isolation: `fragmentDistanceFraction` (0.25) against the seed's own shortest
  prescribed run — Saturday's 6 km — works out to 1 500 m, which an easy effort covers
  in roughly ten minutes, so the plan's two fragment floors read as one policy instead
  of two unrelated guesses. **Rejected: a plan-relative fraction**, for the reason
  `Plan.minimumSessionDurationSeconds`'s own doc already gives — the run slot's
  `durationSeconds` is still carried-but-uneditable, so a relative floor would have
  nothing to be relative *to* on any plan an athlete can actually author. **Rejected:
  leaving the seed at nil**, which was MAX-149's own stopgap and is precisely the "closed
  in vocabulary only" state this ticket exists to end — a seed that states no opinion
  ships an app whose central mis-start case, LIFTING-SPEC §9.2's worked example, is
  never caught on a fresh install.
- **A lift is still never caught, unchanged from MAX-149 and pinned again.** The seed
  choosing a number does not touch `WorkoutClassifier.classify`, which still answers
  `.other` for any non-run before `isFragment` runs at all — a lift has no distance by
  definition, and nothing in this ticket gives the floor a path to one.
  `FragmentDurationFloorTests.testALiftIsNeverClassifiedAsAFragmentByTheDurationFloor`
  (MAX-149's own test) still passes unmodified, and a new end-to-end test runs the same
  claim against the plan `StandardPlanSeed` actually produces rather than a hand-built
  fixture.
- **The screen: a plan-level control beside the cap, not a per-weekday one.**
  `PlanDraft` gains `minimumSessionDurationSeconds: Double?` as a plain `var` — the same
  shape `heartRateCapBPM` already has, no setter method, because there is no illegal
  combination for it to protect against the way a rest day and a distance protect each
  other. `PlanAuthoringView` gets one new section, "Fragment duration floor", between
  the HR cap and the cadence target — a stepper in whole minutes (0–30), zero reading as
  "no floor stated" the same convention the lift duration stepper already set.
  `PlanAuthoringSession.plan(from:effectiveFrom:)` validates it exactly like every other
  plan-level number (`Validate.optionalPositive`'s rule, translated to a new
  `PlanAuthoringError.minimumSessionDurationNotPositive`) — nil is the one legal
  "no opinion" answer, a stated zero or negative is not.
- **The proposal: a new top-level wire field, not a per-day one.** `PlanProposal` gains
  `minimumSessionDurationSeconds: Double?`, coded and validated the same way
  `heartRateCapBPM` is, with its own line in `schemaDescription`'s JSON shape and prose —
  "omit it to state no floor at all," matching every other optional field's instruction
  in that file. `PlanDraft.applying(_:)` takes it directly from the proposal, the same
  "plan-level field, no carry-forward helper" shape `heartRateCapBPM` already has —
  unlike the run slot's own `durationSeconds`, which still has no wire field and still
  needs `carriedDurationSeconds(from:proposing:)`. `PlanProposalReview.targetsSection`
  gains a fifth row, "Fragment duration floor", beside the cap and the two thresholds,
  rendering "None" for an absent floor — the same word the run slot's distance row and
  the lift slot's duration row already use for an unset numeric field.
- **Nothing stored moves (D1).** `StandardPlanSeed` is authoring input the scoring path
  never reads — see the file's own top-of-file note — so seeding a floor changes only
  what the *next* plan version starts from. `FragmentDurationFloorTests`' pre-MAX-149
  hand-written payload still decodes to a plan with no floor and still re-encodes
  without the key; nothing in this ticket touches that fixture or its assertions.
  `PlanAuthoringTests.testRevisionDraftReproducesTheStoredPlanExactly` now also asserts
  the floor carries forward unchanged on a revision, the same as the cap does.
- **The end-to-end proof the ticket exists for.** A new test builds a plan through
  `PlanAuthoring.session(revising: nil, ...)` — the exact path a first-time athlete's
  app takes — and classifies a 90-second, heart-rate-only, no-distance workout against
  it: `.other`. Before this ticket the seeded plan's floor was nil, `isFragment`'s
  duration branch never fired, and the same workout would have reached the scorer as a
  real session. A sibling test pins the other side: a genuine 15-minute no-distance run
  still classifies `.easy` under the same seeded plan.

**Tracker gap P3 is now genuinely closed**, not only expressible: the row above is
updated to say so.

**MAX-132 — `StandardPlanSeed` learns to speak the vocabulary MAX-131 gave it, and closes
the shadow §11.4 escalates.** Two changes to `Sources/MaximizeCore/Plan/StandardPlanSeed.swift`,
both additive to the seed, neither reaching a stored plan (D1):

- **Three adherence bands for `.lift`, per A20 and LIFTING-SPEC §3.5.** `lift.completed`
  (≥ 70% of the prescribed duration, 75–100), `lift.short` (< 70%, 40–74), and
  `lift.happened` (the ask stated no duration at all, 70–95) — the same
  "specific case, then a coarser fallback" shape the `long`/`hard` bands already use, and
  the same 0.8-vs-"prescribed by structure" pattern `hard.completed` established.
  **The fraction is 0.7, not the run bands' 0.8** — held loosely, and stated as an
  editable opinion in the code comment rather than a quotation. None of the three
  reference a load or a volume, which is what A20 requires.
- **`activeEnergyKilocalories` was considered again and declined again**, for the reason
  MAX-131 already gave: it is a volume proxy, and A20's own words rule it out.
- **Every one of the three new bands carries `.actualDiscipline(oneOf: [.lift])`, not
  only the one that strictly needs it to resolve a metric.** `appliesTo: [.lift]` filters
  by the scheduled kind, not by what actually happened — the exact gap `easy.wellOverCap`
  had. Without the guard, a scheduled lift day on which the athlete ran instead could let
  that run's duration satisfy `lift.completed` by coincidence, planting the same defect
  this ticket exists to close, one band down. This is a decision this ticket made beyond
  its literal brief ("adherence bands for lift days"); it is small, and reusing
  `.actualDiscipline` is exactly what MAX-131 built the vocabulary for.
- **`easy.wellOverCap` gains `.actualDiscipline(oneOf: [.run])`**, closing the shadow
  §11.4 escalates: today the band's only condition is average heart rate above cap + 8,
  which any lift clears as a matter of course, so a lift scheduled on an easy-run day
  matched it and was permanently scored 20–45, *"Well above the easy cap for the whole
  run."* Same identifier, same score range, same rationale — only the condition list
  grew, so a `Score` this band already produced for an actual easy run is unaffected.
- **This is a code change to a data-producing function, not a threshold change.** D1
  governs thresholds inside a *stored* plan version; this file only ever supplies the
  bytes a *new* first plan version starts from (see the file's own top-of-file note).
  Nothing here touches `Sources/MaximizeCore/Scoring/`.
- **Reusing MAX-131's shadow-test fixtures rather than a parallel set.** All four new
  tests live in `LiftRubricVocabularyTests.swift`, and the regression test
  (`testTheSeedsWellOverCapBandNoLongerMatchesALiftAndJudgesTheRunAsBefore`) reuses
  `Self.lift()` and `Self.liftMetrics(averageHeartRateBPM:)` from
  `testADisciplineConditionMakesTheWellOverCapShadowUnwritable` — but evaluates
  `StandardPlanSeed.rubricBands()` itself rather than a rubric the test authors, which
  is the gap the earlier test left (it proved the vocabulary *could* close the shadow;
  nothing before this ticket proved the seed *actually does*). The other three tests
  cover a full-duration lift (`lift.completed`), a short one (`lift.short`), and a day
  scheduled as a lift on which something else was recorded (falls to
  `fallback.recorded` — none of the lift bands' `.actualDiscipline` guard is satisfied).
- **Rejected: matching a workout to the lift slot in this ticket.** `RubricEvaluator`
  still reads `planDay.scheduledSession` — the run slot — for every workout;
  routing a workout to the session of its own discipline is MAX-133, dispatched
  separately and in parallel, and it owns `Scoring/RubricEvaluation.swift` and
  `Scoring/WorkoutScorer.swift`. So **nothing reaches these bands yet** — every test
  above writes the `.lift` kind onto the run slot to exercise the vocabulary through the
  real evaluator, the same device `testABandCanRequireAFractionOfThePrescribedDuration`
  already used. This is expected, not a gap this ticket left.
- **Rejected: fixing the scores already written under the unguarded band.** D8 makes an
  auto-score immutable and the plan is versioned data (D1) — this seed change cannot
  reach a stored plan, only the first version a *new* plan starts from. The lifts already
  scored 20–45 by `easy.wellOverCap` or 40–69 by `fallback.recorded` stay scored that way.
  What to do about them is §11.4's escalation, tracked as MAX-143 and explicitly not this
  ticket's to decide — no migration and no rescore were written.

**MAX-133 — a workout is judged against its own discipline's ask.** `RubricEvaluator`
resolves `planDay.scheduledSession(for:)` on `workout.activityType.discipline` instead of
reading the run slot for everything. `RubricBand.appliesTo` filters on the *scheduled*
kind, so this one line is what makes MAX-132's lift bands reachable at all — and it closes
A21's defect from the other side: `easy.wellOverCap` cannot fire on a lift because a lift
is never shown an easy-run day's bands, whatever conditions that band carries.

- **The discipline is stored on the `RubricEvaluation`, not the resolved session.** The
  evaluation outlives its context — `WorkoutScorer` is handed it on its own — so it has to
  carry which slot it read. Recording the *fact* (`discipline`) and leaving the resolution
  to `PlanDay.scheduledSession(for:)` keeps one place turning a (day, discipline) pair into
  an ask, rather than a second copy that can disagree with the calendar. `Score` gains
  nothing, exactly as LIFTING-SPEC §5 predicted: the `scheduledSession` it already stored
  now names the right slot.
- **Reference resolution moved too, and it was the half easy to miss.** `holds` resolved
  `.scheduledDistance` / `.scheduledDuration` against `planDay.scheduledSession`. Filtering
  bands by one slot while resolving thresholds against the other would have measured a
  lift's *"70% of the prescribed duration"* against the run the day also wanted. Both now
  read the one session the evaluator resolved; a fixture prescribing 60 minutes of running
  and 45 of lifting on the same Tuesday pins it.
- **A discipline the day prescribed nothing for resolves to `.rest`.** Not an error and not
  a fallback to the other slot: `PlanDay.scheduledSession(for:)` is total, "no ask to be
  relative to" is a thing a plan says, and `.rest` is how it says it. The workout is then
  judged by whatever the rubric says about a rest day (`rest.ranAnyway`), which is the
  treatment a run on a rest day has always had. Rejected: falling back to the other
  discipline's ask, which is the cross-discipline judgement A17 exists to prevent; and a
  new error case, which would put in Swift a decision D1 says belongs in plan data — a
  rubric with nothing to say about a rest day still refuses (`noBandMatched`) rather than
  defaulting.
- **`WorkoutScorer` gained the guard the routing needs.** Day plus plan version no longer
  identifies a pairing: a lift and a run on the same Tuesday share both, so an evaluation
  made against one discipline's ask would have passed the existing checks and written the
  other's prescription into a permanent record (D8). The scorer now also requires
  `evaluation.discipline` to match the context's workout.
- **MAX-111's ingestion gate stays, and taking it out is now its own ticket.** MAX-132
  merged while this was in flight, so the seed does have lift bands — but only for a day
  whose **lift slot is prescribed**, and `StandardPlanSeed.weeklySessions()` prescribes a
  lift on no weekday, as does every plan already on disk. So a lift let through today
  routes correctly to `.rest` and matches `rest.ranAnyway`, which is unconditional and
  reads *"Ran on a scheduled rest day."* — running language on a lift, permanently, under
  D8. Routing a lift correctly is not the same as having somewhere to route it *to*.
  Removing the gate is also a behaviour change with reach this ticket does not cover: a
  lift that scores acquires a calendar colour and enters the tallies, which is MAX-134's
  and MAX-135's arithmetic. **Reported, not done**, with the seed-side fix it wants named:
  either `.actualDiscipline(oneOf: [.run])` on `rest.ranAnyway`, or a lift-on-an-unasked-day
  band. The comment at the gate now states this reason rather than the mechanism this
  ticket removed, and a test pins that a lift under a rubric with no band for it is
  *refused* rather than mis-scored.

**MAX-146 — closes the `rest.ranAnyway` shadow MAX-133 named.** One line in
`Sources/MaximizeCore/Plan/StandardPlanSeed.swift`: `rest.ranAnyway` gains
`.actualDiscipline(oneOf: [.run])`, the identical condition and the identical reasoning
MAX-132 already used to close `easy.wellOverCap`. Same identifier, same score range
(50–75), same rationale string — only the condition list grew, so a `Score` this band
already produced for an actual run on a scheduled rest day is unaffected.

- **Chosen over a new band, and here is why.** MAX-133's report named two candidates: the
  condition above, or a dedicated band for "a lift on a day whose lift slot prescribes
  nothing." The report also flagged the risk worth checking before picking either — that
  narrowing `rest.ranAnyway` might leave such a lift matching *nothing*, which would be a
  `noBandMatched` refusal instead of a mis-score, possibly a worse outcome. Reading
  `RubricEvaluator` settles it: `bands(for: .rest)` still includes `fallback.recorded`
  (`appliesTo` empty, no conditions, last in the seed's order), so a narrowed
  `rest.ranAnyway` does not throw — the lift falls through to the seed's own unconditional
  catch-all, 40–69, *"Recorded, but the plan has no specific rule for this session."* That
  is already honest for this case, and it is the seed's designed answer for exactly this
  shape of gap (see the type's own note on why the catch-all's range sits below the
  effective threshold). A dedicated band was rejected on that basis: it would need its own
  score range, and choosing one is a product opinion about how much an unscheduled lift
  should count for — not a shadow-closing decision, and not this ticket's to make.
  `testALiftOnADayThatDoesNotPrescribeOneNoLongerMatchesRestRanAnyway` is the test that
  fails without the fix, pinning both facts: no longer `rest.ranAnyway`, and specifically
  `fallback.recorded` rather than a thrown error.
  `testARunOnAScheduledRestDayStillMatchesRestRanAnywayExactlyAsBefore` is the paired
  regression, on the historical Monday-run case `DisciplineMatchedEvaluationTests` and the
  seed's own tests already exercise elsewhere, both live in `LiftRubricVocabularyTests.swift`.
- **The rest of the seed, audited for the same shape.** Every remaining band was checked
  against "does this band's `appliesTo` reach a discipline it was never written about."
  `.easy`/`.long`/`.hard`/`.other` are unreachable by a lift regardless of any band's own
  conditions: `ScheduledSessionKind.liftPrescribable` restricts the **lift** slot to
  `[.rest, .lift]` only, so a lift's own-discipline ask (the only session
  `RubricEvaluator` shows it, since MAX-133) can never resolve to any of those four kinds
  — the routing itself closes the door, not the band. `.lift`-scoped bands
  (`lift.completed`, `lift.short`, `lift.happened`) already carry
  `.actualDiscipline(oneOf: [.lift])`, MAX-132's own guard. `.rest` was the one exception
  worth finding, because it is the *default* both slots share: every weekday starts `.rest`
  unless prescribed otherwise, so it is the only scheduled kind a workout of either
  discipline can land on through no plan decision at all. `fallback.recorded` and
  `skipped` are both intentionally unconditional/unreachable by the seed's own design (see
  the type's top-of-file note) and are not shadows — they are declared catch-alls, not
  accidents of placement. **Finding: `rest.ranAnyway` was the only band with this defect;
  nothing else in the seed needs the same fix.**
- **D1, restated for this file specifically.** This is a change to the *seed* —
  `StandardPlanSeed.rubricBands()` — which only ever supplies the bytes a **new** first
  plan version starts from. It cannot reach a plan already saved, and it does not try to:
  every plan on disk keeps the bands it was saved with. Nothing here migrates or
  rescores anything already written; the label MAX-143 built handles what already exists
  under D8's constraint, and this ticket does not touch it.
- **What is still true.** MAX-111's ingestion gate stays shut — this ticket does not open
  it, and opening it remains its own decision, independent of this fix.

**MAX-134 — the unit of account is the obligation.** A19/LIFTING-SPEC §6. A Tuesday asking
for a run *and* a lift is two obligations: it contributes two to the effective ratio's
denominator, both must be met for the day to extend the streak, and the rest-day budget
forgives one of them at a time rather than converting the whole day. Two *attempts at one*
obligation are untouched and still resolve best-of — §5's warm-up jog — which is
deliberately the opposite rule, because "was every attempt at my run good" and "did I do
everything the plan asked today" are different questions.

- **The shared roll-up §7.3 demands is `DayObligationResolver.resolve`, returning
  `DayObligations`.** One core function answering "what did this day come to", read by the
  tallies and the streak here and by the calendar's mixed day next. **MAX-135 calls
  `DayObligationResolver.resolve(date:planDay:workouts:scoreLedgers:convertedObligations:outcomeIsKnown:)`
  and maps the result to a `ScoreCalendarDayState`** — it must not compute a roll-up of its
  own, which is the whole reason §6 and §7 were decided together. `DayObligations` gives it
  `resolutions` (ordered run-then-lift), `metObligations`, `unmetObligations`, `isFullyMet`
  and `streakContribution`; each `ObligationResolution` carries the outcome, the ask, the
  band and the deciding workout's id — the three facts §7.2's `partiallyMet` state is built
  from. **No verdict enum and no severity ordering were shipped**: §7.2 says in terms that
  it is not specifying the visual, so this ticket fixed the arithmetic and left the state
  to the ticket that can see a pixel.
- **Two reads are carried side by side on purpose.** `outcome` uses
  `ScoreLedger.isEffective` (the annotation where one exists, §8); `band` uses
  `automatic.band` of the best-banded workout (D1/D4/D8 — the calendar never colours from a
  correction). They can legitimately disagree, and collapsing them would have silently
  broken whichever surface lost. `ScoreCalendar.bestScoredPair` now delegates to the
  resolver's `bestScored`, so "the day's best session" is one implementation, not two.
- **The budget converts obligations; `costTier` was not touched.** A19 names reordering the
  tiers as the trap, so the function is byte-for-byte what MAX-128 left — the change is
  entirely in *what is offered* to the ranking. Adjacency generalises per discipline's own
  row (§6.4): a missed lift is framed by the lift slot's neighbours, not the run slot's.
  N stays N conversions per week, so a two-obligation day can consume a budget of 1 and
  leave its other half missed. `RestDayOverride` (the stored §8 record) is untouched; the
  budget now returns `ConvertedObligation`, which is not persisted and nothing writes.
- **One class of historical day moves, deliberately — the A19 paragraph above is corrected
  to say so.** §6.2 resolves each obligation against the workouts of *its own discipline*,
  so a scheduled run day whose only recorded workout was a lift is now a miss, where the
  old discipline-blind "was anything recorded" test left it neutral and excluded from both
  sides of the ratio. Preserving that would have preserved a bug: a lift silently covering
  a skipped run is exactly the failure A19 exists to name, in mirror image. **How much this
  affects, measured rather than guessed:** zero days in the existing tallies and budgeting
  fixtures have this shape (every workout in both suites is a run), and the one instance in
  `ScoreCalendarTests` asserts a cell state that a recorded workout still wins, so it is
  unmoved. On real data it affects only days where the athlete lifted *instead of* running
  on a prescribed run day. A ride, walk or hike is unaffected — `ActivityType.discipline`
  makes `.run` the residual (A17), so only strength training is attributed elsewhere.
- **The regression evidence is a reference implementation, not hand-picked numbers.**
  `legacyDayCounting` and `legacyConversions` in `ObligationTalliesTests` are the
  pre-MAX-134 rules transcribed, and the sweep runs **every** combination of outcomes over
  a run-only week — nothing recorded / recorded-unscored / scored-effective /
  scored-ineffective on each of five prescribed days, against two budgets, 2,048 weeks —
  asserting eligible, effective and streak agree exactly. The budget gets the same
  treatment over every subset of the week. 2,048 hand-worked weeks is not something anyone
  would write or trust; a transcribed oracle is.
- **`EffectiveDayTally` is now `EffectiveObligationTally`**, as §6.2 asks. Field names are
  unchanged and `Tallies.effectiveDays` keeps its name — the tile that reads `4/5` today
  and `6/8` on a week with three lifts needs one line of copy saying the denominator is
  sessions, and **that copy is MAX-140's**, not this ticket's.
- **`PlanDay.canBeMissed` was deliberately not widened.** It is also the calendar's
  predicate (`.scheduledRest`, `prescribesASession`), so widening it would have changed
  what a cell draws without a designed state — MAX-135's job. The obligation-level question
  is `prescribedDisciplines` / `hasObligations` instead. The two agree on every day either
  has seen, because every plan on disk rests its lift slot.
- **`ScoreCalendar` changed by the minimum the shared budget forces.** It reads the run
  slot's conversions only (a forgiven *lift* has no cell state until MAX-135) and builds
  the same `workoutDisciplines` mapping the tallies do, so the two cannot disagree about
  what the budget was offered — D2's drift with a colour attached is exactly what §7.3 is
  about.
- **Reported, not done: whether a miscategorised score should leave the athlete's own
  averages.** MAX-143 added `ScoreLedger.countsTowardScorerQuality` and explicitly left
  this open, flagging it as MAX-134's. It was **not taken**: `Tallies.averageScore` is a
  mean over scored workouts and has no unit of account to change, so deciding it here would
  have mixed a second, unrelated judgement into this PR. The question is live and worth a
  ticket — a lift scored 25 against a running rubric currently drags the athlete's average
  down, and A21 says that score was the answer to the wrong question.
- **No existing run's score moves, proven with fixtures rather than by argument.** Ten
  historical (day, execution) rows — every scheduled kind the fixture week prescribes and
  every row of §10.3's ladder — are scored through the new routing and compared against the
  record the previous evaluator would have written, reconstructed by substituting the exact
  expression it used (`planDay.scheduledSession`). Value equality *and* encoded bytes, with
  band identifiers pinned as literals alongside so both sides cannot drift together.
- **Nothing already scored is rescored, and nothing is backfilled** (D8). The lifts already
  carrying a failed-easy-run score keep it; what to do about them is A21/MAX-143, still the
  owner's.
- **Reported, not done: `WorkoutScorer`'s task text still opens *"You are scoring one
  running workout"*.** It is the stable, health-data-free half of the scoring prompt, and no
  lift can reach it while MAX-111's gate stands. Rewording it is prompt content, which wants
  the ticket that owns the lift's fact sheet (MAX-136) and its own security review — not a
  routing ticket.

**MAX-135 — the calendar's mixed day.** LIFTING-SPEC §7. A day can prescribe two
obligations, and a ~42pt cell has to be able to say "one of two met" without gaining a
colour channel — §7.2 is explicit that it gains a **state**, and MAX-084, MAX-087 and
MAX-105 have already spent the cell's budget between them.

- **`ScoreCalendarDayState.partiallyMet(met:unmet:)`, and it computes no roll-up of its
  own.** `ScoreCalendar.resolve` calls `DayObligationResolver.resolve` per day and reads
  `metObligations`/`unmetObligations` off the result — §7.3's requirement, so the cell and
  the effective-obligations tile cannot disagree about the same Tuesday. A test asserts
  that agreement directly rather than trusting the arrangement. The payload is two small
  structs rather than §7.2's sketched triple: the unmet half carries the band it earned
  where one was reached and **nil where nothing was recorded**, which is the difference
  between "you lifted and it fell short" and "you did not lift" — the one thing a single
  fill and a single glyph cannot carry, and which the spoken sentence therefore must.
- **The visual is a shape, and that was the honest answer rather than the cheap one.**
  The fill is D9's red — the same token `.missed` draws, so the three red states measure
  **1.00:1** against each other, computed in `WCAGContrastTests` rather than asserted —
  and the whole separation is the glyph: an activity figure for a run that went badly, an
  "×" for a day nothing happened on, a half-filled disc for a day that did one of two
  things. Shape survives greyscale, every kind of colour vision, Increase Contrast and
  Reduce Transparency alike, which is the same argument MAX-126 used to give `.noVerdict`
  no colour of its own. **Rejected: reusing MAX-084's corner pip** for the met half — that
  slot's vocabulary is "which band is this fill", and this fill is not a band; and
  **rejected: a split fill**, which is a second colour channel by another name.
- **`testNoTwoScoreBandsAreDistinguishedByHueAlone` was widened, not duplicated.** Its
  universe is now the *cells* the calendar draws — fill token plus glyph, corner pip and
  fill/no-fill in the day grid; hollow and inset size at year density — so band-versus-band
  coverage is unchanged (the three `.scored` cells share an activity glyph by construction
  and still have to pass on the pip) and every new state is held to the same rule. It is
  renamed `testNoTwoCalendarCellsAreDistinguishedByHueAlone`.
- **Two decisions moved into the core to make that test possible**, and they are the
  ticket's real architecture change. The glyph table is now
  `MaximizeCore.ScoreCalendarGlyph` (the app is a passthrough) and the mixed day's spoken
  sentence is `ScoreCalendarCopy`, on `PlanCopy`'s vocabulary. Both are load-bearing
  channels for this state, and while they sat in the app target nothing could check them —
  `swift test` never compiles it. The rest of `ScoreCalendarFormatting`'s copy stayed put:
  moving it needs `WorkoutDisplayFormatting`, which is `App/Workouts/` and another ticket's
  file this session.
- **At year density the mixed day collapses onto the miss, deliberately.** No glyph exists
  at ~6pt, and the two alternatives were a band colour it did not earn or a full-footprint
  red reading against `.effective`'s full-footprint green on hue alone. Hollow is true of
  both states; the spoken sentence carries the rest, exactly as `.scheduledRest` and
  `.convertedRest` are already left to it.
- **Three one-slot readings were widened with it, and no historical cell moves.**
  `prescribesASession` and the `.scheduledRest`/`.missed`/`.convertedRest`/`.forthcoming`
  empties now read both slots (a lift-only day drew *"scheduled rest day"* over an
  outstanding ask before), `ScoreCalendar` stops filtering the rest-day budget's
  conversions to the run slot — the workaround MAX-134 left for this ticket — and
  `agreement` compares a scored workout against **its own discipline's** ask. Every plan on
  disk rests its lift slot, so all four agree with what they replaced on every day the app
  has ever seen; a run-only week is asserted cell by cell to say so.
- **A both-met day is coloured by the worse of its two bands.** §7.2's rule applied to the
  day that met everything: across obligations the calendar is all-of, the same as the
  streak (§6.3), while two attempts at *one* obligation still resolve best-of (§5) inside
  the resolver. Unreachable until something scores lifts, and tested through an obligation
  met by a *correction* over a marginal auto-score, which pins the other half of it — the
  cell colours from the immutable auto-score, never from the annotation (D1/D4/D8).
- ~~**Reported, not done: a recorded-but-unjudged workout still outranks another
  obligation's settled miss.**~~ **Taken by MAX-159 ✅ — see its section below for the
  precedence, the new state, and the one historical cell shape that moves.** A Tuesday
  whose lift was recorded and unscored and whose run
  was missed draws `.noVerdict`, and its spoken sentence names neither the miss nor the
  second ask. §7.2's principle points at changing it, but the same ordering governs
  single-obligation days that have been on screen since MAX-061 — a ride on a missed run
  day reads the same way — so changing it here would have moved historical cells under
  cover of a lifting ticket. It wants its own ticket, and probably a designed state rather
  than a reordering. **One detail of this note is wrong and MAX-159 corrects it**: the ride
  does *not* read the same way, because `Discipline` makes a ride `.run` by slot, so its
  obligation is `.awaitingVerdict` rather than `.missed`. The single-obligation shape that
  actually moves is a **lift** on a prescribed run day. The rest of the note stands, and
  the designed state it predicted is what MAX-159 built.
- **Not verified, and it is the interesting half.** No pixel was drawn. Whether
  `circle.lefthalf.filled` reads as "half of it happened" at 42pt rather than as noise, and
  whether a mixed day reads as *worse* than a plain miss when the two share a fill, are
  device questions. See the PR's device list.

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

**MAX-143 — the owner chose to label, and the label is a record.** A21's escalation is
settled. Every lift scored against the running rubric keeps its score, byte for byte, and
gains a `MiscategorisedScoreLabel` beside it — its own identifier, timestamped, carrying the
ask the score was judged against and the discipline the workout actually was.
`ScoreLedger.divergence` returns nil for a labelled score, and that single line is the whole
product change: these scores stop counting as scorer misjudgements in the one metric D8
exists to protect (PRD §2).

- **Nothing stored moved, and it is asserted on bytes rather than argued.** `StoredScore`
  before and after labelling, columns and the `ScheduledSession` blob inside it, and the
  encoded `Score` after a full labelling pass. There is no write path from anything this
  ticket added to a `Score`: `ScoreRepository` gained one method and it inserts a row in a
  different table.
- **The exclusion is at the metric, not at each consumer.** `divergence` *is* PRD §2's
  correction-rate signal, so the guard lives there rather than in the callers — nothing
  aggregates it yet, and `countsTowardScorerQuality` is exposed so the first thing that does
  filters on the same predicate instead of re-deriving it. `wasCorrected` and
  `effectiveValue` are deliberately **unchanged**: a label says the auto-score is not
  evidence about the scorer, not that the athlete's correction never happened.
- **Not an annotation, and that is the load-bearing distinction.** A21 rejected
  manufacturing annotations because an annotation means *a human corrected this*, and filing
  these as corrections would damage the metric worse than leaving them. A separate record
  type is what makes that impossible rather than merely discouraged.
- **Detection is a rule; labelling is a record.** `MiscategorisedScoreLabel
  .isMiscategorised` is a pure function of the ask the score stored and the workout's own
  discipline — a fact the app can answer only because MAX-133 made "its own discipline's
  ask" a real thing. The label is nonetheless *stored*, for D1's reason: a derived answer
  changes when the derivation changes, so a later ticket mapping a new HealthKit type to
  `.lift` would silently relabel history and move a metric computed over it.
- **A score judged against `.rest` is never labelled, and nothing is lost.** `.rest` belongs
  to both slots, so it names no discipline. That is the one case the rule cannot see, and it
  is also the case where the old evaluator and the new one resolve to the same ask — every
  stored plan prescribes rest on every lift slot (MAX-129), so a lift on a run-rest day got
  the bands it would get today.
- **How a score comes to be labelled: an idempotent pass at launch**, alongside MAX-067's
  splits backfill and for the same reasons. It reads stored rows and writes label rows,
  skips anything already labelled, and therefore needs no "has this run" flag — a flag can be
  lost, restored out of step with the rows it describes, and has to be migrated itself.
  Candidates are lifts: a stored score judged against the other discipline's ask can only be
  a lift shown a run ask, since nothing has ever written `.lift` into a plan's run slot.
  **It is not a migration.** Nothing stored is rewritten, re-typed or deleted, and that
  distinction is what makes the pass compatible with D8 rather than an exception to it.
- **A score labelled twice costs nothing.** `ScoreLedger` reads labelling as a property of
  the set rather than a count, and resolves the earliest as the one in force — the treatment
  `WorkoutRepository` already gives a duplicate workout, for the same reason (two devices,
  neither synced).
- **How it presents, decided: the score is shown and a sentence explains it.** Nothing is
  hidden, no number moves, the band and rationale read exactly as before, and the athlete's
  history is not rewritten. `MiscategorisedScoreCopy` holds the two strings in the core where
  copy lives. **Reported, not done: nothing renders them yet.** The verdict header
  (`Domain/WorkoutVerdict.swift`, `App/Workouts/`) is MAX-139's and the calendar's VoiceOver
  sentence is MAX-150's, both in flight — so the core carries the state and the words, and
  wiring them to a surface wants whichever of those lands second.
- **Also reported, not done: the average-score tile still counts these scores.** This ticket
  excluded them from the scorer-quality metric, which is the one D8 protects. Whether a
  miscategorised score should also leave the athlete's own averages is a question about a
  number already on screen, it belongs to `Tallies` (MAX-134's files), and it was not taken.
- **CI compiles the App layer and never runs it.** The SwiftData record, the store
  conformance, the delete cascade and the launch trigger are App-layer (R2, R13); the
  mapping they depend on is tested in the core. See the PR's **Needs device verification**.

**MAX-136 — the prompt stops describing a lift as a run.** LIFTING-SPEC §10.1. A lift's
fact sheet now carries the day and weekday, the type, duration, active energy, the
classification, the plan version, **its own slot's prescription**, the goals, average and
maximum heart rate, zone splits and the heart-rate shape — and no cap line, no cadence
line, no pace line, no distance line, no setting line and no splits section. The two lines
§10.1 singled out are gone: the HR cap and the cadence band are the plan's *running*
settings, and they were being printed under "The plan" as though they governed a lift.

- **One renderer with a discipline branch, not a second renderer.** `factSheet()` keeps its
  single entry point (A12 rule 1) and every figure both branches carry still goes through
  the same `FactSheetFormatting` function (rule 3). What a lift needs and a run does not —
  a prescription written in minutes and muscle groups — is a private formatter in
  `WorkoutFactSheet`, deliberately *not* moved into `FactSheetFormatting`, on the precedent
  the file already sets for `energy`: a formatter with one caller buys no shared guarantee
  by moving, and it gains its second caller the day `TrainingFactSheet`'s plan block
  carries the lift slot.
- **The absence rule inverts rather than lapsing.** This renderer's standing rule is that
  an absent metric states its own absence; §10.1 forbids that for a lift, because a heading
  that exists only to disclaim itself is prompt tokens spent on nothing. But the rule
  exists to stop Claude reasoning from a gap, and that hazard does not go away — so the
  sheet says once, in one sentence, that the missing figures are a fact about the
  discipline and not about the record. Stated once instead of nine times, which is exactly
  the trade `TrainingFactSheet` already makes for a roll-up.
- **`WorkoutContext.scheduledSession` is the accessor that describes the workout**, and it
  is computed, not stored. `planDay.scheduledSession` is the run slot whatever the workout
  was; `scheduledSession` asks `PlanDay.scheduledSession(for:)` with the workout's own
  discipline. **Rejected: selecting it into a stored property in the builder.** It is a
  total lookup over two values the context already carries, so a stored copy would be a
  second answer to "which ask governs this workout", free to drift from `planDay` — the
  shape D2 warns about. `planDay` is untouched, so `RubricEvaluator` still reads the run
  slot; matching a workout to its own discipline's ask there is **MAX-133**.
- **`.rest` is rendered, not dropped.** "You lifted on a day the plan asked for no lift" is
  precisely what a scorer needs; the lift slot's totality is what makes it sayable.
- **The builder gates the split series on discipline too**, so the answer to "did this
  health data leave the device" stays in the one assembler D3 names. Not a formality: a
  lift ingested before MAX-130 has a fabricated cadence, grade-adjusted pace and split
  series on file, and this is what stops those reaching a prompt. **Rejected: gating on
  `DerivedMetricKind.distanceSplits`,** whose requirement is the narrower
  `.runningActivity` — the section is gated on discipline, so a narrower data gate would
  have a hike's chat prompt printing "no breakdown is on file for this run" over splits
  that are on file.
- **A hike and a ride are untouched.** They sit in the run slot by A17 and render exactly as
  before. Whether the running-*form* figures should be omitted for them as well is a real
  question and a different one — it moves a scoring prompt for workouts A17 did not move —
  and it is reported here rather than taken.
- **A run's fact sheet is pinned byte for byte.** `ContextDisciplineTests` writes the whole
  expected sheet out as a literal rather than probing it with `contains`, because the
  property that had to be preserved is that the scoring prompt is character-identical: a
  regression here would not look like a failure, it would look like slightly different
  scores, stored forever under D8.
- ~~**Reported, not done: `TrainingFactSheet`'s plan block still renders only the run
  slot.**~~ **Closed by MAX-181.** The collision note above records MAX-142 as unnecessary
  because "the plan block renders the whole stored `WeeklyTemplate`". Verified against the
  code: **the roll-up half of §10.2 is genuinely done** — one line per session,
  discipline-tagged, absent fields omitted, the cap counting sessions — but the plan block
  iterated `plan.weeklyTemplate.entries` and printed `entry.session`, which is the *run*
  slot. MAX-129 put the lift ask on `Entry.liftSession`, not into `entries`, so it never
  appeared. §10.2's second sentence ("the plan block must carry the weekly template's
  **lift** slot, or 'am I on plan' is answerable about half the plan") stayed open through
  this ticket's own report of it, was rediscovered by MAX-174's competitive read as G2, and
  MAX-181 closed it: each weekday's line now names the lift ask too, tagged `Lift:`,
  omitted rather than stated on a day that asks for none. This ticket's brief had scoped
  the fix to `WorkoutFactSheet`, `WorkoutContext` and `WorkoutContextBuilder`, which is why
  it was left alone here rather than taken as a drive-by. See the MAX-181 section below.

**MAX-139 — the workout detail screen stops drawing a lift as a run with holes in it.**
LIFTING-SPEC §10.1's other half. The fact sheet stopped describing a lift in running
vocabulary at MAX-136; this is the screen.

- **The verdict header now reads the workout's own discipline's ask, not the run
  slot's.** `WorkoutVerdict.scheduledSession` used to be `planDay?.scheduledSession`
  unconditionally — the run slot, whatever the workout was — which is why a lift's
  header showed the day's run ask (an easy run it did not do) instead of its own lift
  ask. It now resolves through `PlanDay.scheduledSession(for:)`, keyed on a new public
  `WorkoutVerdict.discipline` read from `Workout.activityType.discipline`. A day
  prescribing a run and no lift now reports `.rest` for a lift on it — the honest
  answer, per §5's "a workout of a discipline the day did not prescribe" — never the
  run's easy-run ask. Regression-tested (`testALiftOnAGovernedDayReportsTheLiftAskNot
  TheRunAsk`) against the exact scenario the pre-existing test asserted the *old*, wrong
  behaviour for; that test is rewritten rather than left contradicting the fix. A second
  test pins a day prescribing both slots resolving each workout to its own ask.
- **Four run-only things stop appearing on a lift's screen, and one sentence stands in
  their place.** Cadence versus target, the route map, the pace splits, and the HR
  curve's cap line describe a running prescription (a cadence target is steps against a
  running gait; `Plan.heartRateCapBPM` is documented as the easy-run ceiling) and none
  belongs on a lift's screen — not even in its own "no data" state, which is what
  `CadenceBandView` draws today for any workout with no cadence average, lift or not.
  **Decision: the decision of which sections apply lives in `SummaryTileData`, not in
  the view.** A new `SummaryTileData.showsRunOnlySections: Bool` (false for a lift) is
  what `WorkoutDetailView` reads to skip `CadenceBandView`, `RouteMapView` and
  `SplitsView` entirely, and a new `SummaryTileData.disciplineNote: String?` (non-nil
  only for a lift) is the one sentence `SummaryTilesView` renders in their place —
  worded apart from `WorkoutFactSheet.disciplineFraming` and from `RouteMapView`'s
  indoor-run copy, per CLAUDE.md's "different statements must not share copy" (the
  discipline not applying and the sensor not being there are different facts). Both are
  tested directly on `SummaryTileData`, not inferred from a view.
- **The lift's summary tiles are gated explicitly, not left to accident.** Distance,
  drift and grade-adjusted pace are now `nil` for a lift by an explicit discipline check
  in `SummaryTileData.init`, not merely trusted to already be nil from upstream. Two
  reasons that is not redundant: `distance` reads `Workout.distanceMeters` directly,
  which `DerivedMetricKind` has no opinion about at all, so nothing upstream stops a
  captured lift from carrying one; and a lift ingested **before** MAX-130 gated the
  calculator can carry a stored drift or grade-adjusted pace figure the old,
  discipline-blind calculator computed — the identical "stale figure from before this
  ticket" case `WorkoutFactSheet`'s `describesARun` branch already guards against. A
  dedicated test constructs exactly that stale-metrics case and asserts both tiles stay
  hidden. What a lift keeps: duration, active energy, and average/maximum heart rate — a
  heart rate measured during a lift is still a heart rate (LIFTING-SPEC §3.2).
- **The HR curve stays for a lift; only its cap line goes.** `HRCurveView` is unchanged
  and untouched — the curve and the avg/max HR figures apply to both disciplines. What
  changed is `WorkoutDetailModel.heartRateChart`, which used to hand every workout the
  plan's `heartRateCapBPM` unconditionally: a single plan-level field with no
  per-discipline sibling, so a lift on a day a plan governs was drawing the running cap
  as a dashed line with a "Cap N bpm" annotation. It now passes `nil` for a lift's
  `capBPM`, the same absence `HRCurveView` already renders correctly for "no plan
  governs this day." **Known imperfection, left as found**: on a lift day a plan *does*
  govern, `HRCurveView`'s own copy for a nil cap still reads "No plan governs this day,
  so there's no cap to compare against" — technically true of the run slot's cap, not of
  the day. Fixing the sentence needs a discipline-aware copy branch inside
  `HRCurveView.swift`, which is outside this ticket's five listed files; reported rather
  than done.
- **The verdict header now says when a score was reached against the wrong
  discipline's ask (A21/MAX-143).** MAX-143 shipped `MiscategorisedScoreLabel` and
  `MiscategorisedScoreCopy` and explicitly left wiring them to a surface to "whichever
  of MAX-139 or MAX-150 lands second" — MAX-150 landed first, so this ticket took it. A
  new `WorkoutVerdict.miscategorisationLabel` reads `ScoreLedger.miscategorisationLabel`
  straight through (never re-derived), and `VerdictHeaderView` renders
  `MiscategorisedScoreCopy.labelledDetail` as one more plain-text, no-colour line below
  the rationale — the identical treatment `annotationRow` already gives a manual
  correction, because a label is the same kind of fact: additive information beside an
  unchanged, immutable score (D8). The score chip's own VoiceOver label is combined into
  one element and gains `labelledAccessibilitySuffix` when a label is present, so the
  number and the caveat read as one sentence rather than two unrelated labels.
- **The last view literal adopts `FailureCopy`.** MAX-154 defined
  `LoadFailureSurface.workoutDetail` and left `App/Workouts/WorkoutDetailView.swift`
  alone because this ticket was in flight; the `.failed` case now reads
  `FailureCopy.couldNotLoad(.workoutDetail)`.
- **Two files beyond this ticket's listed five were touched, both minimally and both
  unowned by any parallel ticket.** `App/Workouts/WorkoutDetailModel.swift` gained the
  discipline parameter `heartRateChart` needed to gate the cap line (above) — the value
  is assembled there and nowhere else reachable from the five listed files.
  `App/Workouts/WorkoutDisplayFormatting.swift`'s `describeScheduledSession(_:unit:)` is
  the one formatter `VerdictHeaderView` calls for the "Scheduled" row, and its `.lift`
  case still read `session.note ?? "Lift"` — written before MAX-131/MAX-145 gave a lift
  session a duration and muscle groups to show. Left as `"Lift"` alone, the header's
  discipline fix would have been structurally correct (the right `ScheduledSession`) but
  said almost nothing about it; it now reads "Lift · 45:00 · Chest and shoulders",
  reusing `SummaryTileData.formattedDuration` and `MuscleGroupEntryCopy.describe` so a
  lift's ask is never worded two different ways one screen apart.
- **Considered and rejected: a numeric lifting-progression tile, and a zone-splits
  view.** LIFTING-SPEC §4.2 ships no numeric lifting progression — nothing measures load
  or volume — so there is no target for a tile to show against, and a `— / — ` tile is
  worse than no tile. Zone splits (§3.3's recommendation to keep them for a lift) have no
  summary-tile or chart surface anywhere in the app today, for *any* discipline — only
  the fact sheet renders them as prose — so adding one would be new-feature scope for a
  ticket titled "workout detail for a lift," not a removal-and-replacement. Reported,
  not built.
- **Not verified by CI beyond compilation.** Every section composed by
  `WorkoutDetailView`, the cadence/route/splits omission, the HR curve's cap line, and
  the verdict header's rendering are App-layer (tracker R2, R13) — CI compiles them and
  never draws a pixel. **Needs device verification**: open a lift's detail screen and
  confirm no cadence card, no route card, no splits card, and no dashed cap line appear;
  confirm the discipline-note sentence reads correctly below the summary tiles; confirm
  the "Scheduled" row shows the lift's own ask (duration and muscle groups, where
  prescribed) rather than the day's run ask; open a run's detail screen and confirm
  nothing changed. A device with a historical miscategorised lift score would also
  confirm the new label row, but none is known to exist on this account yet.

**MAX-140 — the trend tiles stop calling obligations days, and the average score is
decided to be per-workout.** LIFTING-SPEC §14 named three jobs; here is what happened to
each.

- **The effective-days caption was a lie on screen, and now is not.** Since MAX-134,
  `Tallies.effectiveDays` (`EffectiveObligationTally`) counts prescribed *obligations*,
  not calendar days — a Tuesday asking for a run and a lift is two chances, and a week
  with three lifts reads `6/8` where it used to read `4/5` for the same training. The
  number was already right (MAX-134's own byte-for-byte regression proved that); the
  caption still said "effective days" over a denominator that no longer counted days.
  Fixed in `TrendTileData.swift`: "effective sessions" at week/month, "effective, of N
  eligible sessions" at year — "sessions" rather than "obligations" because it is the
  word LIFTING-SPEC §6.2 itself uses for this exact cost, and the word `PlanFormatting`
  already uses on the plan screen. Two new tests exercise this through the real
  `TalliesCalculator`/`DayObligationResolver` pipeline rather than a hand-built `Tallies`
  — a mixed run+lift day reading `1/2`, and a run-only week reading the same `4/5` a
  reader would have gotten before MAX-134, proving the single-discipline-history
  invariant at the tile layer and not only at `Tallies`'.
- **"Days run" was already fixed.** MAX-150 landed "days trained" ahead of this ticket
  starting. Checked, not redone: `workoutDays`' doc comment now says so explicitly, and
  the existing `testAMonthAddsDaysTrainedAndKeepsTheArcComparison` is the pin.
- **Average score: decided per-workout, deliberately.** `Tallies.averageScore` already
  means "mean of every scored workout's `effectiveValue` in the interval" —
  `TalliesCalculator.computeAverageScore` (unmoved, MAX-134's file) sums one term per
  scored workout, so a day that completed and scored both a run and a lift already
  contributed two terms before this ticket, the same as two scored attempts at one
  obligation always have. **Decision: keep it, and say why in the type's own
  documentation rather than leave the reader to infer it.** "How good was each thing I
  did" (this tile) and "did I meet each thing the plan asked of me" (`effectiveDays`,
  best-of-per-obligation then AND-across-day) are different questions, and collapsing
  the average to one best-of figure per day would discard a second scored effort's own
  grade — data the athlete asked to see — to buy a distinction that belongs to the other
  question. D2 is respected by construction: this ticket touches no arithmetic, only
  documents the arithmetic `Tallies` already runs.
- **Reported, not decided: whether a MAX-143-labelled miscategorised score (a lift
  scored against the running rubric, A21) should leave this average.**
  `ScoreLedger.countsTowardScorerQuality` already excludes it from PRD §2's
  scorer-quality signal; whether it should *also* stop dragging down the athlete's own
  average score is a live question MAX-134's own tracker note flagged and explicitly did
  not take, on the grounds that it belongs to `Tallies`/`TalliesCalculator`. This
  ticket's scope names those exact files off-limits (`Tallies/`, `Domain/Tallies.swift`
  — MAX-134's), so it is reported rather than done here: building a second, competing
  average inside `TrendTileData` to work around the boundary would be exactly the D2
  drift this file exists to avoid. **Filed here as a candidate follow-up ticket** —
  "exclude miscategorised scores from `Tallies.averageScore`" — rather than picked up.
- **Found in passing, reported, not touched:** `Context/TrainingFactSheet.swift` prints
  the identical string, "Effective days: N/M", straight from the same
  `EffectiveObligationTally` — the same caption bug, one layer over. Out of this ticket's
  named files (`Metrics/TrendTileData.swift`, `App/Dashboard/TrendTilesView.swift`), and
  it is prompt content, which CLAUDE.md requires a `/security-review` for regardless of
  how small the wording change. Left alone; flagged for whoever owns the fact sheet next
  (MAX-136/147's territory).
- **`App/Dashboard/TrendTilesView.swift` needed no change.** Every string it renders
  comes from `TrendTileData.tiles`; the view lays tiles out and reads captions, it does
  not know their words. Listed in the ticket's file scope, read, left untouched.

**Needs device verification: none.** Every change in this ticket is a string returned by
`MaximizeCore`, pinned by tests that run in CI; nothing here reaches a view, a gesture or
a rendering decision no test can see.

**MAX-147 — the task text learns discipline too.** MAX-133's report named this exactly:
`WorkoutScorer`'s stable half still opened *"You are scoring one running workout"* for
every call, lift included. This is the fix, one level up from MAX-136's fact sheet.

- **Decided: one function with a discipline branch, not two independent string
  literals.** The rejection rule, the rationale contract (`RationaleContract
  .instructionText`) and the JSON reply format (`ScoreProposal
  .responseFormatDescription`) are the same contract for either discipline — only the
  opening sentence and the first instruction's wording (which measured facts to weigh)
  differ. Two complete literals would have duplicated those shared paragraphs and let
  them drift apart the next time either was edited on its own ticket, which is exactly
  the failure `WorkoutFactSheet.factSheet()` avoids by staying one renderer with one
  discipline branch (A12, MAX-136). `WorkoutScorer.taskDescription(for:)` makes the
  identical choice at the scale of the instruction that wraps that fact sheet. **Rejected:
  a single text with inline conditionals** ("if this is a lift, ignore the pace
  instruction below") — that keeps the running vocabulary physically present in every
  lift prompt, which is the exact hazard being closed, just moved from "stated" to
  "stated and then retracted".
- **The branch is on `Discipline`, not `ActivityType.isRun`**, for the reason the fact
  sheet's is: A17's slot is what a workout is judged against, so a hike or a ride sits in
  the run slot and reads the unchanged run text.
- **The lift branch says what to weigh, not only what to ignore.** LIFTING-SPEC §8.3:
  adherence is whether the prescribed session happened, on the prescribed day, for
  roughly the prescribed length — so the lift instruction says that positively rather
  than listing absent running figures a second time; MAX-136's `disciplineFraming` on the
  fact sheet already carries that disclaimer once, and repeating it in the task text
  would be the same fact stated twice at two removes from each other, free to drift.
  Carries none of `pace`, `cadence`, `cap`, `splits` or `distance` — nothing describes a
  lift's fact sheet by those words — and says nothing about load or volume, because §8.3
  is explicit that no such number is in the record; a task that invited the model to
  weigh either would be inviting it to invent one. Tested by asserting the absence of
  each term against the rendered instruction, not by reading the source.
- **The run branch is pinned as a literal** (`ScorerTaskTextTests
  .testTheRunTaskTextIsUnchanged`), so an edit made in service of the lift branch cannot
  drift it silently. The two shared paragraphs it does not own — `RationaleContract`'s
  wording and `ScoreProposal`'s reply format — are read live from those types rather than
  duplicated a second time in the pinned literal, so a future edit to either does not fail
  this ticket's test for a reason that has nothing to do with it.
- **`ScoringInstruction.task`'s doc comment now says "stable per discipline"** rather than
  "identical for every workout" — still true, still cacheable, still free of health data;
  there are simply two stable values instead of one. No caller assumed a single global
  literal: the one place that read the doc comment for a caching decision
  (`AnthropicScoringModelClient`) sends whatever `instruction.task` resolves to as the
  system block already, so a second stable value costs it nothing.
- **No new data enters a prompt.** `context.discipline` selects between two fixed
  literals; it is read, not assembled — `WorkoutScorer` already read the equivalent
  (`context.workout.activityType.discipline`) for its own guard checks before this
  ticket. D3 is unmoved: the fact sheet stays `WorkoutContextBuilder`'s alone to compose,
  and this ticket touches only the instruction wrapped around it.
- **No rescore, no backfill** (D8). Every score already written keeps the task text it was
  produced under; this changes what a *future* call sends, nothing already stored.

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

## MAX-154 — the app-wide error-handling audit

**Scope: every failure path outside chat.** Chat's own failure states are MAX-152/153's
and were not touched. The audit was a full sweep of `App/` and `Sources/MaximizeCore/`
for the three defect classes the ticket named: a failure that reaches the person as
nothing, a failure that reaches them as noise, and a failure the code claims cannot
happen. **The inventory below is the deliverable, including the rows nothing was done
to** — an audit whose findings vanish into a diff is not reviewable.

### 1. Failures the code claims cannot happen — the ban holds

Scanned across `App/` and `Sources/MaximizeCore/` (excluding `Tests/`, where these are
permitted):

| Construct | Count in non-test code | Verdict |
|---|---|---|
| Force unwrap (`x!`) | **0** | CLAUDE.md's rule is actually kept, not merely stated |
| `try!` | **0** | Five source comments *mention* `try!` to explain why a defensive enum case exists instead of one |
| `fatalError` | **0** | One comment, same shape (`PlanProposalDrafting`) |
| `as!` | **0** | — |
| Implicitly-unwrapped optional (`: T!`) | **0** | — |
| `assertionFailure` | 1 | `Surfaces.swift:252` — the debug-only glass-over-data tripwire, a logged decision, compiles out of release |
| Array subscripting | 2 | Both guarded: `ScoreCalendarView.door` subscripts `[0]` only inside `where workoutIDs.count == 1`; `DayWorkoutsView.step(by:)` guards on `indices.contains(next)` first |

Nothing in this class needed fixing. Recording it matters anyway: the claim "the ban
holds" had never been checked, and the checks above are what makes it a fact rather than
an assumption.

### 2. Failures that reached the person as nothing — fixed

- **The dashboard drew a blank three sections deep.** `DashboardView` rendered
  `ScoreCalendarView`, `DriftOverlayView` and `TrendTilesView` inside `if let interval =
  intervalModel.state.interval`, with **no `else`**. When the interval model is `.failed`
  — a system clock outside `CalendarDay`'s domain — the entire dashboard below the
  selector was absent, with a one-line caption on a control above it the only hint.
  Fixed: an `else` branch carrying `FailureCopy.dashboardUnavailableWithoutToday`.
- **The store failing to open discarded its reason entirely.**
  `PersistenceComposition.modelContainer` was `try? MaximizeModelContainer.makeOnDisk()`.
  This is the most consequential failure in the app — every screen degrades, ingestion
  falls back to the anchor-pinning sink, nothing is written — and the error went nowhere.
  Fixed: a `do`/`catch` logging `domain` and `code` `.public` and the error itself
  `.private`, following `IngestionComposition`'s established split for exactly this
  reason (a Core Data error's `userInfo` can carry stored row values, i.e. health data).

### 3. Failures that reached the person as noise, or as a false claim — fixed

- **A failed Keychain read was reported as "No key is stored."** `SettingsView` held a
  `Bool` and set it to `false` in the `catch`, so a device that could not be asked stated
  flatly that nothing was there — and, because the **Clear** button was gated on that
  flag, the only control that removes a key was withdrawn on exactly the device where one
  might still be sitting. Fixed: `StoredAPIKeyPresence` is three states
  (`stored`/`notStored`/`unknown`), `permitsClearing` is true for two of them, and a
  failed save or clear now re-reads presence rather than leaving the line reading as it
  did before the attempt.
- **"No workouts yet." asserted something R10 says the app cannot know.** An empty list
  and a refused Health *read* are indistinguishable from inside this app. Fixed: the copy
  states the ordinary reading, then names the other possibility and where to check it —
  **without** claiming Health is or is not connected, which is the claim R10 forbids. A
  test asserts the words "connected" and "denied" appear in no Health-related string.
- **Four verbs for one event.** "Could not load workouts.", "Couldn't load the plan.",
  "Couldn't load the calendar.", "Couldn't load this plan version.", "Couldn't load the
  runs in this interval." — five screens, four spellings, none of them the one
  `ChatConversationCopy.failedToLoad` had already established at MAX-150. Fixed: one verb,
  asserted against chat's by test, so the app has a single failure voice rather than a
  chat one and a not-chat one.
- **Two dozen athlete-facing string literals, across eleven files, were being chosen in
  `App/` — in `catch` blocks and `switch` arms CI compiles and never runs.** CLAUDE.md is explicit that this is the defect and not the fix: the layer is
  compiled by CI and never executed (R2, R13), so nothing but a reader could tell whether
  an edit kept the care the comments described. All of them now read a value from
  `MaximizeCore.FailureCopy`, which has tests.

### 4. Acceptable with reason — inspected, left alone

Every one of these was read in full and is deliberate. Listing them is the point: a later
audit should not have to re-derive that they are fine.

- **`AnchoredWorkoutIngester:229` — `try? await anchorStore.clearAnchor()`.** Discarding a
  clear failure is correct: the fetch is already retrying without an anchor, and failing
  the pass over a failed *cleanup* would pin the pipeline on the corrupt byte the code is
  in the middle of routing around.
- **`WorkoutIngestionPipeline:234, 498` — `try? await scores.ledger(...)`.** A ledger read
  that fails is not evidence a score is absent, and the pipeline treats "unknown" the same
  as "present" — it declines to score rather than risking a second auto-score (D8).
- **`WorkoutIngestionPipeline:636` — `try? await Task.sleep(...)`.** A cancelled sleep
  means the model already answered. Commented as such.
- **`MaximizeModelContainer:248, 290` — per-file `try? setAttributes`.** One file in a
  transient state must not cost every other file its protection class; the enumerator's
  `errorHandler` returns `true` for the same reason.
- **`MiscategorisedScoreLabelling:115` — `try? ... else { continue }`.** One unreadable
  ledger skips one score, not the pass. The pass is idempotent, so the skipped row is
  labelled on the next launch.
- **`WorkoutSampleExtractor:343, 435, 495` — `try?` per sample.** Rejecting one implausible
  reading and keeping the series is the documented policy; a whole-series throw would lose
  a run's curve permanently.
- **`SettingsView:196` — `guard let budget = try? RestDayBudget(daysPerWeek:) else
  { return }`.** Unreachable: the picker offers `0...7` and that is the type's whole
  permitted domain. A silent `return` on an unreachable branch is preferable to inventing
  copy for a state that cannot occur.
- **`ScoringModelError` / `ScoringError` / `DomainError` `description`s.** Diagnostic by
  design and correctly so — they are read in a debugger, and none reaches a screen. See
  the finding below for the one place that is *nearly* untrue.
- **R11's escape is implemented.** `WorkoutIngestionPipeline` reports
  `.workoutAbandoned(step:)` at both `storingTheWorkout` and `discardingTheWorkout`, and
  `IngestionComposition` logs it loudly, so a permanently unacceptable workout no longer
  wedges the pipeline. The audit touched none of it. **The R11 row below still reads
  "MAX-033 must handle this" and is now stale** — left for whoever owns that row to tick,
  rather than re-graded by a ticket that only read the code.
- **`ScoreProposal:75`, `PlanProposal:666`** interpolate a decoding error into a
  `malformedResponse(reason:)` payload. Developer-facing, never rendered.

### 5. Found, reported, not taken

Each of these is a real finding in a file another ticket in flight owns, or on a surface
another ticket owns. Per the brief, they are reported rather than taken.

- **A status code can reach the athlete's screen.** `PlanProposalDrafting.description`
  returns `"The plan could not be drafted. \(error.description)."`, where `error` is a
  `ScoringModelError` — so "The Anthropic API returned an unexpected status (400)." is
  rendered verbatim on the plan proposal card. That is defect class 2 exactly: an HTTP
  status and a vendor name where a description of what happened belongs. **Not taken**:
  the sentence is displayed on a chat surface and MAX-152 owns chat's failure states.
  Filed as **MAX-155**.
- **`ScoringError.description` interpolates a workout UUID and a `CalendarDay`.**
  `contextAlreadyScored(workoutID:)` renders the identifier; `noPlanInEffect(day:)`
  renders a date. Neither reaches a screen today, and the one log that could carry them
  is `.private`, so this is a latent hazard rather than a live leak — but CLAUDE.md rules
  identifiers and dates out of error strings without a "probably fine" exception, and the
  distance between this and a leak is one future `.public` log line. Filed as **MAX-156**.
- **`App/Workouts/WorkoutDetailView.swift:64`** still carries `Text("Could not load this
  workout.")`, the last view literal of the five. `LoadFailureSurface.workoutDetail` and
  its sentence are defined and tested; adopting them is one line. **Not taken**:
  `App/Workouts/*` is MAX-139's.
- **No surface in the app offers a retry.** Every `.failed` state is terminal until the
  view is rebuilt, including the ones caused by something that plainly could succeed on a
  second attempt. New risk row **R15** below.

### What CI proves about this ticket, and what it does not

CI compiles `App/` and runs `FailureCopyTests`. That proves every sentence exists, that no
two cases share one, that none carries a digit or names a type, and that the Health copy
claims nothing R10 forbids. **It proves nothing about any of the failures themselves.** CI
opens no socket, touches no Health store, reads no Keychain and opens no SwiftData store,
so every path this ticket touches is device-verified only. The PR lists how to provoke each one.

---

## MAX-155/156 — error descriptions stop leaking codes and identifiers

Both filed by MAX-154's audit (§5, "found, reported, not taken"), both fixed the same
shift: a `description` that used to double as screen or log text now stays a debugger
diagnostic on the type that already had one, and a new, narrower channel carries the
words that are actually safe to show or store. **Corrected from the tracker rows that
filed them:** MAX-155's row names `PlanProposalDrafting.description` interpolating a
`ScoringModelError` — that description lives on `PlanDraftingFailure`
(`Plan/PlanProposalDrafting.swift`), and the interpolated type is `PlanProposalModelError`,
not `ScoringModelError`. Trusted the code over the row, per the ticket's own instruction.

### MAX-155 — the plan proposal card

**Decision: a sibling to `ChatFailureNotice`, not a case added to it.**
`ChatFailureNotice` maps exactly one input type (`ChatStreamError`) and its own doc
comment states that as the reason its exhaustiveness claim is meaningful.
`PlanDraftingFailure` wraps two types `ChatStreamError` knows nothing about
(`PlanProposalModelError` for a transport failure, `PlanProposalError` for a rejected
proposal), so folding it in would mean either widening `ChatFailureNotice`'s signature
to a third, unrelated error type, or bolting a second entry point onto a type whose
whole design is "one mapping, one input." `PlanDraftingNotice`
(`Sources/MaximizeCore/Plan/PlanDraftingNotice.swift`) is the sibling instead, same
shape, same rules, its own exhaustive `switch` with no `default`.

**A 400 from the drafting endpoint and a 400 from the stream get the same words, by
different code.** Both `unexpectedStatus` cases mean the same thing to an athlete —
"this app built a request Anthropic rejected, and asking again will not help" — so the
sentences read alike on purpose. But `ChatStreamError.unexpectedStatus` and
`PlanProposalModelError.unexpectedStatus` are different types, so the sentence is
written twice, once per `switch`, the same way each type already writes its own
`.noAPIKeyStored` sentence rather than sharing a helper across two enums that happen to
share a case name.

**`PlanDraftingFailure.description` is unchanged**, payload and all — it still
interpolates `PlanProposalModelError.description`, status codes included. That is
deliberate, not an oversight: `ChatStreamError.description` was already accepted as a
developer diagnostic before MAX-152, on the reasoning `FailureCopy` states explicitly
("`ScoringModelError.description` and friends stay as they are ... written for a
developer reading a debugger"). Rewriting `PlanDraftingFailure.description` in place
would only be right if nothing else read it; something did —
`ChatModel.noteDraftingFailure` — and that is the one line this ticket changed, to read
`PlanDraftingNotice.notice(for:).message` instead. The doc comment that used to claim
`description` was screen-safe (the actual bug — see MAX-154's finding) is corrected to
say the opposite and point at the new type.

**`.rejected(PlanProposalError)` is the deliberate, documented exception** to "nothing
here is interpolated": `PlanProposalError.description` is correction text, not a wire
diagnostic — the same string `PlanProposalInstruction(retryingAfter:)` already puts in
front of the model, and MAX-101's own documentation calls it "the one the athlete should
read verbatim." It is carried into `PlanDraftingNotice` unchanged. Rewriting it would be
a second opinion about a file this ticket does not own (`Plan/PlanProposal.swift`,
MAX-151) — flagged, not touched, per this ticket's scope discipline.

**Retry: no new flag.** `ChatFailureNotice.offersRetry` gates `ChatModel.canRetry`, but
nothing gates "Draft a plan from this conversation" on the failure kind — the same
button that failed is the only affordance for every case, and tapping it is what asks
again. That already satisfies MAX-152's rule (a button, never an automatic policy)
without a property, so `PlanDraftingNotice` does not add one; adding a flag nothing
reads would be a second, unenforced decision.

**Tests:** `Tests/MaximizeCoreTests/PlanDraftingNoticeTests.swift`, exhaustive over
`PlanProposalModelError` — every case a distinct, non-empty sentence, no digit anywhere
(the exact MAX-155 regression, checked by name for 400 and every other status this
client can receive), no wire vocabulary, no case name. Plus
`ChatPlanDraftingTests.testAnUnexpectedStatusNeverReachesTheTranscriptAsANumber`, driving
the failure through `ChatModel.draftPlan()` end to end. One existing assertion was
updated rather than left to rot:
`ChatPlanDraftingTests.testEveryFailureGetsASentenceInTheTranscript`'s `.requestFailed`
fragment moved from "connectivity" (a wire word that reached the screen by the bug this
ticket fixes) to "connection" (what the transcript now actually says) — documented in
place, not silently changed. `PlanProposalDraftingTests`' two assertions against
`.description` directly (`testTwoUnusableRepliesStopRatherThanLooping`,
`testTheNoKeySentencePointsAtTheFix`) were left untouched, because `.description`'s
behaviour for those two cases is unchanged.

### MAX-156 — `ScoringError.description`

**Decision: delete the payload from the two affected sentences; no new property.**
`noPlanInEffect(day:)` and `contextAlreadyScored(workoutID:)` no longer interpolate
their associated values into `description` — full stop, not "unless the caller is
`.private`". CLAUDE.md's health-and-privacy rule has no "the current caller happens to
be careful" clause, and a `description` is a plain `String`: nothing stops a future
`.public` log call, a screen, or a crash reporter from reading it, so the fix had to
make the leak structurally impossible rather than rely on today's one call site staying
careful.

**No second "diagnostic" channel was added, because one already exists.** The ticket
brief allows for "a separate non-`description` channel that callers must reach for
deliberately" if a diagnostic genuinely needs the value. It does not: the day and the
workout ID are still sitting on the case as ordinary associated values, and a caller
that wants one switches on `.noPlanInEffect(let day)` or
`.contextAlreadyScored(let workoutID)` directly — already deliberate, already typed,
and adding a mirrored property would only duplicate a channel the enum already provides
for free.

**The other five cases were left alone.** `noBandMatched` interpolates a
`ScheduledSessionKind` and `WorkoutClassification` raw value ("easy", "hard") — plan
vocabulary, not an identifier or a date — and the model-fault cases
(`malformedResponse`, `scoreOutOfPermittedRange`, `scoreOutsideBand`,
`rationaleRejected`) interpolate a score, a range, or a caller-supplied reason string,
none of which name a specific workout. MAX-156's brief is the identifier and the date
specifically; widening the diagnostic-copy rewrite to every case was not asked for and
was not done.

**Tests:** `Tests/MaximizeCoreTests/ScoringErrorPrivacyTests.swift`, one instance of
every `ScoringError` case built with a distinctive UUID and `CalendarDay`, asserting
`description` contains neither the identifier's `uuidString` nor the date's ISO string
(nor its bare year) for any of the seven cases — not just the two that used to leak. A
companion test confirms the two affected sentences still say something a debugger reader
can act on, and another confirms the day and workout ID are still reachable by matching
the specific case, which is the "separate channel" this decision relies on.

### What CI can and cannot prove, for both

CI proves: every notice/description exists, is non-empty, is distinct from its
siblings, and — mechanically, by regex over the rendered strings — carries no digit and
none of the banned wire/enum tokens. It cannot prove the two athlete-facing surfaces
(the plan proposal card, and anything that ever renders a `ScoringError` — nothing does
today) look right, or that provoking a real 400 from `AnthropicPlanProposalClient`
against a live server produces exactly the case this ticket assumes. See the PR's
**Needs device verification**.

---

## MAX-157 — the fact sheet counts sessions, not days

**Source: MAX-140's report.** MAX-140 fixed `TrendTileData`'s on-screen "effective days"
caption to "effective sessions" and found, in passing, that `Context/TrainingFactSheet.swift`
prints the identical mislabelled string straight from the same `EffectiveObligationTally` —
one layer deeper, in what Claude is told rather than what the athlete reads. Since MAX-134
(A19/LIFTING-SPEC §6.2), that count is prescribed *obligations*: a Tuesday asking for a run
and a lift contributes two. A prompt that hands Claude a number and calls it "days" invites
Claude to reason and answer in days, to the athlete, about a figure that is not days — worse
than a wrong on-screen caption, because the athlete has no label in front of them to correct
for it.

**The fix: two lines relabelled, in `TrainingFactSheet.talliesLines`.** Both branches of the
`effective.rate == nil` check now read "Effective sessions" instead of "Effective days" —
the populated case (`"Effective sessions: \(effectiveCount)/\(eligibleCount)"`) and the
absence case (`"Effective sessions: nothing in this window was eligible — …"`). "Sessions"
rather than "obligations", matching LIFTING-SPEC §6.2's and `PlanFormatting`'s own word, and
the exact word MAX-140 gives the dashboard tile for the same reason. No arithmetic moved —
`effective.effectiveCount`/`effective.eligibleCount` are read from the `EffectiveObligationTally`
`Tallies` already computed (D2); only the label changed.

**Prompt text, before and after** (for the security review this PR carries):

```
- Effective days: 4/5
+ Effective sessions: 4/5

- Effective days: nothing in this window was eligible — the plan asked for rest, no plan
-     governed these days, or their outcome is not yet known.
+ Effective sessions: nothing in this window was eligible — the plan asked for rest, no
+     plan governed these days, or their outcome is not yet known.
```

**No new field of health data enters the prompt.** This changes two words on two lines
that were already there; the numbers, their source (`Tallies.effectiveDays`), and every
other line of the fact sheet are unchanged.

**Swept the whole file for the same class of drift, not just the two named lines:**

- **"Days with at least one workout: N" (`tallies.workoutDays`) — left alone.** `workoutDays`
  counts distinct calendar days with at least one recorded workout of any discipline
  (`Tallies`'s own doc comment); a day carrying both a run and a lift still counts once.
  MAX-134 never touched this figure, so "days" is still its true unit. A comment now says
  so in place, so the next sweep does not have to re-derive it.
- **"Current streak: N days" (`tallies.currentStreak`) — left alone, and this is the one
  worth explaining rather than just checking.** LIFTING-SPEC §6.3 rolls a day's obligations
  up with AND *before* the streak ever sees it — a day extends the streak only if it had at
  least one obligation and every obligation on it was met. So what the streak walks is one
  entry per calendar day regardless of how many sessions that day prescribed, and its unit
  of account is genuinely the day. Relabelling this line would have been the same defect in
  the opposite direction — stating an obligation count in day words is wrong, but so is
  stating a genuine day count in some other word to look consistent. A comment now says why
  it stays "days," so a future editor does not "fix" it back into the same class of bug.
- **The rest-day budget — no line to fix.** `TrainingFactSheet.swift` does not render a
  rest-day-budget figure at all (checked: no "budget" line anywhere in the file or in
  `TrainingContext.swift`). `ContextBuilder.Inputs.restDayBudget` reaches the training
  context's tallies computation but nothing prints the budget itself or its conversions
  today, so there is nothing here mislabelled and nothing to add — adding one would be a
  new field of prompt content, which this ticket's brief rules out.
- **The per-session lines already say "session," not "day."** `sessionLines`' preamble
  ("One line per session — per session, not per day, because a day can hold both a run and
  a lift and the plan asks for each separately") and every per-session field were already
  discipline- and session-aware as of MAX-095/MAX-136. Read, left untouched.
- **The window and plan blocks — no obligation counts to mislabel.** `windowLines` and
  `planLines` state calendar-day spans and plan settings, never a count of obligations, so
  none of A19's unit change reaches them.

**Tests.** `Tests/MaximizeCoreTests/TrainingContextAgreementTests.swift` pinned the old
"Effective days" wording in two places — `testEveryTalliedFigureAgreesWithTheDashboardsOwn`
(the populated case, against the tile's own value) and
`testAnEmptyEffectiveDayRatioIsWithheldOnBothSurfaces` (the absence case, and the "not 0/0"
negative assertion). Both updated in place to assert "Effective sessions" instead, and the
absence-case test gained an explicit `XCTAssertFalse(sheet.contains("Effective days:"))` so
a regression back to the old label fails even if a future rewrite stops matching the exact
absence sentence.

**What CI can and cannot prove.** CI can prove: the package compiles and
`TrainingContextAgreementTests` — including the two updated assertions — passes, which
pins the corrected wording as a literal string a future edit cannot silently drift. CI
cannot prove anything about how Claude actually reasons over the corrected label; that is
inherent to prompt-wording changes and not something a unit test can close. **Needs device
verification: none** — this ticket touches no view, no gesture and no HealthKit path; the
only way to observe the change is to read a rendered fact sheet or a training-thread
transcript, and CI already asserts the string it contains.

**`swift build`/`swift test` were not run.** There is no Swift toolchain in this container
(R1); CI is the actual compiler. The change is two string literals and their surrounding
comments, both call sites still take the same two `Int`s they took before, and the touched
test file's assertions were re-read line by line against the new strings. That is "reads
correctly and should compile," not "compiles" — stated at that strength deliberately.

---

## MAX-160 — a labelled miscategorised score leaves the athlete's own average

**The owner's decision, taken.** MAX-143 excluded a labelled score from PRD §2's
scorer-quality metric only, and reported — deliberately, twice, in MAX-134's own tracker
note and again in MAX-140's — that whether it should also leave the athlete's own average
was a live, undecided question belonging to `Tallies`/`TalliesCalculator`. The owner
decided: yes. The reasoning this ticket built against: the average answers "how am I
training," and a score produced by asking the wrong question is not evidence about the
athlete's training any more than it is evidence about the scorer — it is noise from a bug.
Excluding it from an aggregate is not rewriting history (D8): the score stays on the
workout, visible, with its rationale and `MiscategorisedScoreCopy.labelledDetail`'s
explanation. Only what `Tallies.averageScore` reads changed.

**The shared-predicate question, answered: `ScoreLedger.isMiscategorised`, not
`countsTowardScorerQuality`.** MAX-143 exposed `countsTowardScorerQuality` explicitly so a
future aggregate would filter on it rather than re-derive the rule, and this is that
aggregate. But `countsTowardScorerQuality` (`!isMiscategorised`, today) answers "is this
evidence about the scorer" — PRD §2's question — and this ticket's question is "is this
evidence about the athlete's training." The two happen to agree on every score in the
codebase right now, because labelling is the only thing either predicate currently reacts
to. They are not, on inspection, the same question: a future reason to exclude a score
from PRD §2's signal that has nothing to do with whether it honestly measures the athlete
(a scorer-model version bump invalidating old rationales, say) would, if this ticket had
coupled the average to `countsTowardScorerQuality`, silently move the athlete's average
for a reason that has nothing to do with them — a latent bug that would be correct today
and wrong the day the two questions actually diverge. `computeAverageScore` reads
`ScoreLedger.isMiscategorised` directly instead, which states the one fact this exclusion
is actually about. See `TalliesCalculator`'s own documentation, right beside the function,
for the same argument in place.

**A label excludes the whole workout, correction or not.** The ticket's instruction was
literal — "skip a score carrying a `MiscategorisedScoreLabel`" — and this ticket followed
it without carving out an exception for a workout the athlete has since corrected by hand.
`ScoreLedger.wasCorrected` and `.effectiveValue` are unaffected by labelling (MAX-143's own
rule, restated in `Score.swift`), so the correction still stands and still shows on the
workout — it is simply never summed into this particular average, because the workout it
came from was never judged against its own discipline's ask in the first place.
`testALabelledAndCorrectedScoreIsStillExcludedFromTheAverage` pins this.

**The designed state: "no scores to average," not zero.** When every scored workout in an
interval is labelled, `Tallies.averageScore` stays nil — the same "honest absence" the
type already gave "nothing scored yet" — rather than resolving to `0.0`, which would read
as "you scored zero" instead of "nothing here counts as evidence." The two nils are told
apart by the new `averageScoreExcludedMiscategorisedCount`, which is `0` for the ordinary
absence and the excluded count for this one. `testAnAverageOverOnlyLabelledScoresIsNilRatherThanZero`
pins the value; `testALabelledScoreLeavesNoAverageAndTheFactSheetSaysWhy`
(`TrainingContextAgreementTests`) pins that the two nils say different things on the one
surface that can say anything about an absent tile — the fact sheet, which is prose, not a
value/caption pair. The dashboard tile itself cannot: `TrendTileData.averageScore` is
`nil` either way, because there is no value left to caption a reason onto — documented in
place rather than solved by inventing a value-less tile, which no other absence in that
type does either.

**The caption, where there is a value to caption.** `TrendTileData.averageScore`'s caption
is `"avg score"` unchanged when nothing was excluded — the property that keeps a
single-discipline history's tile byte-identical — and `"avg score (excludes N score(s) from
before the plan distinguished lifting)"` when `averageScoreExcludedMiscategorisedCount` is
positive. `TrainingFactSheet`'s "Average score" line folds in the identical parenthetical
when there is still a figure to report, and prints
`MiscategorisedScoreCopy.onlyExcludedScoresAverageLine` instead of the ordinary absence
sentence when there is not. Both surfaces call through one pair of functions —
`MiscategorisedScoreCopy.averageExclusionNote`/`.onlyExcludedScoresAverageLine`, beside
MAX-143's `labelledDetail` — so the wording cannot drift apart the way MAX-140 and MAX-157
each found it already had (A12 rule 3).

**Copy lives in `MiscategorisedScoreLabel.swift`, extending `MiscategorisedScoreCopy`
rather than a new type.** That enum is already "what a surface showing a labelled score
says about it," and the average's copy is exactly that question asked of an aggregate
instead of a single workout. `Domain/Score.swift` was read and not touched — this ticket's
brief named it MAX-143's, and nothing about the average's exclusion needed a change to
`Score` or `ScoreLedger` themselves; `isMiscategorised` and `effectiveValue` already said
everything `computeAverageScore` needed to read.

**Swept every other aggregate over scores; changed one, reported the rest.**

- **`Tallies.averageScore` — changed.** This ticket's whole scope.
- **`Tallies.effectiveDays` (`EffectiveObligationTally`) — unchanged, and a labelled score
  still counts.** `DayObligationResolver`/`DayObligations.swift` reads `ScoreLedger
  .isEffective` with no label filter anywhere in the resolution — `bestScored(_:)` and
  `resolutions.filter { $0.outcome.isEffective }` take every scored workout of the right
  discipline as-is. A lift mis-scored against the running rubric before MAX-133 today still
  counts toward, or against, the plan-adherence ratio exactly as an honestly-scored one
  would. **Not changed here**: this ticket's scope was named as `Tallies.averageScore`
  specifically, and MAX-140 already declined to widen the analogous question once. Filed as
  a candidate follow-up — "exclude a labelled score from `EffectiveObligationTally` too" —
  rather than picked up.
- **`Tallies.currentStreak` — unchanged, and a labelled score still can extend or break
  it.** The streak walks `DayObligationResolver`'s same per-day roll-up
  (`DayObligations.streakContribution`), so whatever is true of `effectiveDays` above is
  true here too: a labelled score is ordinary evidence to the streak walk today. Same
  disposition — reported, not touched.
- **`Dashboard/ScoreCalendar.swift` — read, not touched (MAX-159's file, off-limits to this
  ticket).** `bestScoredPair` resolves a calendar day's cell from every scored workout with
  no label filter either, so a labelled score paints the calendar exactly as an unlabelled
  one would. Same finding as the two above, on a different surface; reported for whoever
  next owns that file.
- **`TrendTileData.workoutDays`/`.mileage`/`.totalDistance`/`.streak` (as a tile) — not
  score-based**, so labelling has no surface here to reach. Checked, not changed.
- **`Context/TrainingFactSheet.swift`'s other lines — checked.** "Days with at least one
  workout," "Effective sessions" and "Current streak" all read `Tallies` fields this ticket
  did not touch, so they carry the same labelled-score exposure as their `Tallies`
  counterparts above and no new one. The per-session lines (`sessionLines`) already show
  each session's own verdict — including, for a labelled score, nothing extra today; MAX-143
  did not add a per-session label sentence to the fact sheet and this ticket does not add
  one either, being out of scope.

**In one sentence: this ticket makes the athlete's average stop counting a category error
against them; it deliberately leaves the plan-adherence ratio, the streak and the calendar
still counting one, and says so rather than quietly narrowing what "excluded" means.**

**Tests** (all in `MaximizeCoreTests`, all touching only files this ticket owns):
`TalliesTests` gains `testALabelledScoreIsExcludedFromTheAverageAndAnUnlabelledOneIsNot`,
`testAnAverageOverOnlyLabelledScoresIsNilRatherThanZero`,
`testALabelledAndCorrectedScoreIsStillExcludedFromTheAverage`,
`testASingleDisciplineHistoryLeavesTheAverageAndItsExcludedCountUnchanged` (the
byte-identical fixture) and a validation test for the new field's non-negativity.
`TrendTileDataTests` gains three caption tests (none excluded, one excluded, several
excluded — plural wording). `MiscategorisedScoreLabelTests` pins the two new copy
functions' wording and voice, the same way it already pins `labelledDetail`.
`TrainingContextAgreementTests` gains `testALabelledScoreLeavesNoAverageAndTheFactSheetSaysWhy`,
the tile/fact-sheet agreement property extended to the all-excluded case.

**What CI can and cannot prove.** CI can prove: the package compiles, every new and
existing `TalliesTests`/`TrendTileDataTests`/`MiscategorisedScoreLabelTests`/
`TrainingContextAgreementTests` assertion passes, and — because the new parameter carries a
default of `0` — every pre-existing direct `Tallies(...)` construction in the test suite
keeps compiling unchanged, which is itself evidence the change is additive rather than a
signature break threaded everywhere. CI cannot prove the longer caption
("avg score (excludes 1 score from before the plan distinguished lifting)") lays out well
inside `TrendTilesView`'s two-column grid tile at large Dynamic Type sizes — that view was
not touched, takes whatever caption `MaximizeCore` hands it, and has no `.lineLimit()` set,
so the caption should wrap rather than truncate, but only a device can confirm it reads
well rather than merely wrapping. **Needs device verification**: open the dashboard with a
history containing at least one labelled score (none is known to exist on this account
yet) and confirm the average-score tile's longer caption is legible at the default and a
large Dynamic Type size, on both the weekly and monthly/annual tile sets.

**`swift build`/`swift test` were not run.** There is no Swift toolchain in this container
(R1); CI is the actual compiler. Every new test was reasoned by hand against the exact
arithmetic `computeAverageScore` now runs and the exact strings `MiscategorisedScoreCopy`
now returns — reads correctly and should compile and pass, not confirmed to.

---

## MAX-104 — copy and absence voice: the plan and workout screens

**MAX-150's accurate remainder.** MAX-150 took the chat and dashboard half of the
app-wide copy pass early and left `App/Plan/*` and `App/Workouts/*` in full for this
ticket, plus one already-checked item (`ChatEntryPoint`'s workout-subject strings — see
MAX-150's own note). By the time this ticket ran, the lifting build (128–150) had landed
across both directories, so the brief was not just "match MAX-150's voice" but "check
what the lifting build left wrong" — MAX-139 and MAX-134/140/157 each reported or implied
a specific defect in a file they were not allowed to touch.

**The voice is MAX-150's, unchanged, not re-derived:** say what's true, in one plain
sentence, using the noun the underlying data actually counts; absence gets a real
sentence naming what's missing and why; two different facts stay two different sentences;
never restate a fact the surface already stated a few lines away.

### Inventory

Every string in `App/Plan/*` and `App/Workouts/*` was traced to its source and
classified. Most of both directories was already correct: `SummaryTilesView`,
`WorkoutChatSectionView`, `MuscleGroupEntryView`, `CadenceBandView`, `SplitsView`,
`WorkoutRow`, `DayWorkoutsView`, `WorkoutsListModel`, `PlanView`, `PlanDetailSections`,
`PlanVersionDetailView`, `PlanViewModel` read every string off a core type MAX-095–150
already got right, and `CadenceBandView`/`SplitsView`/`RouteMapView`'s own "no plan
governs this day" / "no splits" / "no route" sentences are true exactly because those
three sections are gated off a lift's screen entirely
(`SummaryTileData.showsRunOnlySections`, MAX-139) — a run-only view speaking in run
vocabulary is not a bug. Four things were not fine:

1. **`App/Workouts/WorkoutDetailView.swift`'s failure literal — already fixed.** MAX-154
   reported this as the one un-adopted `LoadFailureSurface.workoutDetail` call site, but
   MAX-139 landed touching this exact file in between and adopted it
   (`Text(FailureCopy.couldNotLoad(.workoutDetail))` is already the `.failed` case's
   body). Checked, confirmed, no action — recorded here so the next reader does not
   re-open it.
2. **`HRCurveView`'s cap-absence sentence conflated two different facts (MAX-139's
   report).** "No plan governs this day, so there's no cap to compare against." was
   shown whenever `capBPM` was nil — for a run with no governing plan, correctly, and
   for **every lift**, incorrectly: `Plan.heartRateCapBPM` is the easy-run ceiling and is
   withheld from a lift's curve regardless of whether a plan governs the day
   (`WorkoutDetailModel.heartRateChart`). A lift on a plan-governed day was told a false
   thing about its own plan. Fixed — see below.
3. **Two spots had drifted onto `CalendarDay.description`'s bare `YYYY-MM-DD` wire
   format** instead of the plan screens' own "Aug 5, 2026" (`PlanFormatting.dayLabel`,
   established at MAX-102): `PlanAuthoringView`'s governed-day preview row
   (`planDay.date.description`) and `PlanAuthoringModel`'s save confirmation
   (`"…effective from \(saved.effectiveFrom)."`). Neither is new to the lifting build —
   both predate it — but both are exactly CLAUDE.md's "one consistent voice," broken on
   the one screen whose whole job is showing dates.
4. **The same wire-format leak was inside a core-declared error message.**
   `PlanAuthoringError.effectiveFromTooEarly`'s `description` interpolated
   `\(earliest)` directly — a `CalendarDay`, which is `.description`'s bare wire
   format — so the athlete-facing validation message read "…take effect is
   2026-06-02." on the one screen everything else calls "Jun 2, 2026." A core file's
   own string had the same bug the App layer did.

**Two more, not wrong, but not where MAX-150's own rule says they belong:**

5. **`RouteMapView`'s and `SplitsView`'s `.unavailable` sentences were view literals
   selected by a case of a core-declared enum** (`RouteMapData`, `SplitsListData`) —
   exactly the shape MAX-150 wrote down as its rule for what moves to the core ("a
   string whose selection is driven by a case of a core-declared type belongs beside
   that type"). Neither sentence was factually wrong; both were in the wrong layer for
   CI to pin them against a future edit to either enum.

### What changed

**HR curve (`Sources/MaximizeCore/Metrics/HeartRateChartData.swift`).** Added
`discipline: Discipline` to the initializer (no default — every call site says
explicitly which discipline this is, `SummaryTileData`'s own convention) and a computed
`capAbsenceReason: CapAbsenceReason?` (`.notApplicableToDiscipline` / `.noPlanForDay`),
resolved from `discipline` and `capBPM` so the two can never disagree — a cap present
and a reason for its absence is not a state the type can represent. `HRCurveView` now
reads the computed `capAbsenceExplanation: String?` instead of hand-testing `capBPM ==
nil` and printing one hard-coded sentence. `WorkoutDetailModel`'s one call site passes
`discipline:`, which it already had in scope. Four new tests in
`HeartRateChartDataTests.swift` pin both sentences, that they differ, and that a present
cap yields neither.

**Plan-screen dates.** Moved the "Aug 5, 2026" formatter itself from
`App/Plan/PlanFormatting.swift` down to `PlanCopy.day(_:)` (core) — GMT-pinned,
unchanged algorithm — so a core-declared error and every plan view read a date the same
way. `PlanFormatting.dayLabel` now calls straight through, matching every other function
in that file. `PlanAuthoringError.effectiveFromTooEarly` and the two drifted call sites
(`PlanAuthoringView`'s preview row, `PlanAuthoringModel`'s confirmation) now go through
`PlanCopy.day(_:)` / `PlanFormatting.dayLabel(_:)`. While in the file, also moved
`PlanAuthoringError`'s three weekday interpolations off `String(describing: weekday)
.capitalized` (a second, reflection-based spelling of the same vocabulary
`PlanCopy.weekday(_:)` already owns) onto `PlanCopy.weekday(_:)` directly — output
unchanged, one fewer place the weekday's name could drift. `PlanCopyTests.swift` (new)
pins `day(_:)` against a mid-month date, a year boundary, and the exact wire-format
regression this ticket found. `PlanAuthoringTests.swift`'s
`testBackDatingErrorNamesTheEarliestPermittedDay` — the one test that had pinned the old
`2026-06-02` wire format as the *expected* value — updated to assert `"Jun 2, 2026"` and
assert the wire format is now absent.

**Route and splits absence text.** `RouteMapData.unavailableExplanation` and
`SplitsListData.unavailableExplanation` (both core, both `public static let`) now own
the sentences `RouteMapView` and `SplitsView` used to hard-code. Each has a test
(`RouteMapDataTests`, `SplitsListDataTests`) pinning the exact string.

### `session`/`day` sweep

Checked every "day"/"days" occurrence in both directories against what it counts, per
MAX-134/140/157's own concern. All of them are calendar-day references (a weekday-picker
label, a plan's effective-from date, `WorkoutDisplayFormatting`'s "Rest day") rather than
a *count* of something MAX-134 redefined the unit of — neither directory renders a
tally-style figure (an "N days"/"N sessions" count) at all; those live on the dashboard,
which is MAX-150's and MAX-157's. Nothing to relabel here.

### Reviewed and left alone, on purpose

- **`WorkoutDisplayFormatting.swift`'s switches on `ActivityType`/`WorkoutClassification`
  /`ScheduledSession` (all core-declared types) stay in the App layer**, the same
  exception MAX-150 recorded for `ScoreCalendarFormatting.swift`: it predates MAX-150's
  own "belongs beside the core type" rule, every string in it is correct today, and
  relocating a formatter this central (read by `WorkoutRow`, `VerdictHeaderView`, and
  `PlanFormatting`'s own weekday-line rendering) is an architecture change, not a copy
  fix. Flagged rather than silently left, per MAX-150's own precedent.
- **`PlanAuthoringFormatting.describe(_ mode:)`/`.explain(_ mode:)`** switch on
  `PlanAuthoringSession.Mode`, a core-declared type, and by MAX-150's rule belong beside
  it — but MAX-101 already gave a reasoned, deliberate account for keeping them in the
  App layer ("so this file stays the one place the authoring screen's own copy is
  written"), the text is correct, and there are exactly two call sites, both already
  reading through this one function (no duplication risk to close). Not moved; noted so
  a future copy pass does not have to re-discover the tension between the two rules.
- **`PlanAuthoringFormatting.explain(.firstPlan)`'s "runs are captured but not measured
  against anything"** — checked against whether a first-plan's consequences read
  correctly now that lifts exist. It still does: a lift is never scored regardless of
  whether a plan exists (MAX-111), and the sentence is specifically about what a first
  plan unlocks for scoring, which is unchanged. Not a finding.
- **`VerdictHeaderView`'s `awaitingScoreSection`/`noVerdictSection` run-vocabulary
  strings** ("Scoring runs automatically once the run is captured.", "The plan scores
  runs, so there's no score for this workout.") — checked against `WorkoutVerdict.init`:
  `.awaitingScore` is reachable only when `activityType.isRun`, and `.noVerdict` only for
  a non-run, non-lift discipline still classified `.other` (a ride, a hike). Both
  sentences are true of every workout that can reach them. Not a finding.
- **`CadenceBandView`/`SplitsView`/`RouteMapView`'s own run-vocabulary absence
  sentences** — all three sections are omitted from a lift's screen entirely
  (`SummaryTileData.showsRunOnlySections`, MAX-139), so "no plan governs this day, so
  there's no target band to compare against" and "no splits/route recorded for this
  run" are never shown for anything but a run. Not a finding — this is the one place
  "no plan governs this day" is still the correct, undifferentiated sentence, because
  the discipline ambiguity `HRCurveView` had cannot arise here.

### Tests

`HeartRateChartDataTests.swift` (4 new), `PlanCopyTests.swift` (new file, 3 tests),
`RouteMapDataTests.swift` (1 new), `SplitsListDataTests.swift` (1 new),
`PlanAuthoringTests.swift` (1 updated to assert the corrected wording and the absence of
the old wire format). Every new or changed string with a data dependency has a test
asserting its exact value, following `FailureCopy`/`PlanCopy`'s own bar.

### What CI can and cannot prove

CI can prove: the package compiles, and the ten new/updated tests above pass, pinning
both `HeartRateChartData` absence sentences (and that they differ), `PlanCopy.day(_:)`'s
formatting including the year-boundary case, and the two moved absence sentences on
`RouteMapData`/`SplitsListData`. CI cannot prove that `HRCurveView` actually renders the
right sentence for a real lift on a real device, that `PlanAuthoringView`'s governed-day
preview reads correctly against Dynamic Type, or anything about how either screen looks —
see CLAUDE.md's own distinction.

**Needs device verification:**
- Open a lift's workout detail screen on a day a plan governs (any weekday with a lift
  prescribed and rest on the run slot) and confirm the HR curve's note reads "This is a
  lift, not a run, so there's no heart-rate cap to compare against." — not "No plan
  governs this day."
- Open a run's workout detail on a day no plan governs (before the plan's
  `effectiveFrom`, if reachable, or by design a run with no stored plan) and confirm the
  HR curve still reads "No plan governs this day, so there's no cap to compare against."
- Open the plan-authoring screen (Plan tab → Author a revision), scroll to "The first
  week this version governs," and confirm each row's date reads "Aug 5, 2026" style, not
  "2026-08-05".
- Save a plan revision and confirm the on-screen confirmation ("Saved plan v_N_,
  effective from …") reads the same date style.
- Trigger the back-dating rejection (attempt to set "Takes effect" earlier than
  permitted, if the picker's own bound can be bypassed, or read the message on a device
  where it fires) and confirm the earliest-permitted date reads "Aug 5, 2026" style.
- An outdoor run with a `hasRoute` flag but no stored route, and an outdoor run with no
  stored splits breakdown — confirm both still read exactly as before ("This run's route
  could not be loaded.", "No splits recorded for this run."); this is a pure relocation,
  not a wording change, and worth a device glance since neither test suite renders a
  view.

**`swift build`/`swift test` were not run** — no Swift toolchain in this container (R1);
CI is the actual compiler. Every change is a string relocation, a new computed property
resolved from existing stored data, or a wording fix with no branch or control-flow
change; every touched call site was re-read line by line against its new signature. That
is "reads correctly and should compile, and ten tests are written to prove the strings
once it does" — not "compiles," stated at that strength deliberately, per CLAUDE.md's own
distinction between the two sentences.

---

## MAX-158 — a rejected proposal stops speaking schema

**The defect, restated precisely.** `PlanProposalError.description` is written for two
readers at once: `PlanProposalInstruction(retryingAfter:)` appends it to the retry as a
correction, and `PlanDraftingNotice`'s `.rejected` case — MAX-155's own documented,
deliberate exception — carried it straight onto the plan proposal card. The words that
make the retry work ("the reply left out `liftKind`, which the plan schema requires")
are exactly the words an athlete cannot act on: nothing on their screen is called
`liftKind`, and they have never seen a schema.

**Decision: two renderings, one error — a type, not a second property.**
`PlanProposalError.description` is untouched, payload and all, and stays the correction
channel. `PlanProposalErrorNotice` (`Sources/MaximizeCore/Plan/PlanProposalErrorNotice.swift`)
is the new sibling, same shape as `ChatFailureNotice` and `PlanDraftingNotice`: a
`message`, a private initialiser, and one exhaustive `static func notice(for:)` with no
`default`. A second `String` property sitting next to `description` on the same enum was
considered and rejected — a naming convention is exactly what let the original defect
happen (`PlanDraftingNotice` reading `error.description` as though it were already
screen-safe), and a second property is still a naming convention: nothing stops a future
call site from reaching for the wrong one by habit. A distinct type is not a habit — a
caller wanting athlete-facing text has exactly one type here that offers any.

**Fourteen cases get a new, constant sentence; one case is left alone, on purpose.**
`.rejectedByAuthoring(PlanAuthoringError)` is not rewritten. `PlanAuthoringError` was
built for this exact readership — its own doc comment says its cases "say what the
athlete did and what to do instead," and `FailureCopy.planCouldNotBePrepared`'s doc
comment independently calls it "already athlete-facing." It never carries a field name,
"JSON," or "schema." Writing a second sentence for it would be two descriptions of the
same plan-authoring rule, free to drift the moment one is edited and the other is not —
the same argument D2/D3 make for one context builder rather than two notions of what a
workout is. So `PlanProposalErrorNotice` delegates that one case to
`authoringError.description` verbatim, and says explicitly why doing so is not the
naming-convention trap the rest of the type exists to close: `PlanAuthoringError` is a
type of its own, switched on by name, not a same-shaped property assumed safe by
proximity.

The other fourteen cases (`malformedResponse`, `missingField`, `forbiddenField`,
`unknownSessionKind`, `unknownWeekday`, `unknownLiftKind`, `unknownMuscleGroup`,
`weekIsNotOneSessionPerWeekday`, `restDayIsNotEmpty`, `liftRestDayIsNotEmpty`,
`malformedGoalTargetDay`, `longRunArcIsEmpty`, `longRunArcWeekNotPositive`,
`longRunArcOutOfOrder`) each get one constant sentence, matching
`PlanDraftingNotice.transportMessage`'s rule: nothing here is interpolated, so a
payload (a field name, a weekday, a week index) cannot slip through by accident. Each
sentence says what is wrong with the *plan*, in `PlanCopy`'s vocabulary — a run kind, a
lift kind, a muscle group, a rest day, a long-run week — rather than what was wrong with
the *reply*.

**`PlanDraftingNotice`'s `.rejected` case is the one line that changed.** It now reads
`PlanProposalErrorNotice.notice(for: error).message` instead of `error.description`
directly; the surrounding "Claude's plan was not one this app could use, twice: … Nothing
has changed — say what you want and ask again." sentence is unchanged, since that framing
was never the leak. `ChatModel.noteDraftingFailure` needed no change — it already read
`PlanDraftingNotice`, never `PlanProposalError.description` directly.

**The retry is unweakened.** `PlanProposalInstruction`, `PlanProposalDrafting`, and
`PlanProposalError.description` itself are untouched. `PlanProposalDraftingTests`'
`testAnUnusableReplyIsAskedAgainOnceWithTheReason` still asserts the retry's `task`
contains `PlanAuthoringError.heartRateCapImplausible(...).description` verbatim, and
`PlanProposalTests.testAStringWhereANumberBelongsIsRefusedNotCoerced` still asserts
`description` names the field. Neither was touched; both still pass by inspection.

**Tests:** `Tests/MaximizeCoreTests/PlanProposalErrorNoticeTests.swift`, exhaustive over
all fifteen `PlanProposalError` cases — every case a distinct, non-empty sentence; no
message contains a quotation mark (every field name and value `description` names is
quoted, so a surviving quote is itself a leak detector); a banned-token list catches
"JSON", "schema", and the specific field names this ticket's brief named; the fourteen
model-boundary cases are asserted to differ from their own `description`, and two
instances of the same case with different payloads are asserted to read identically,
confirming nothing is interpolated; `.rejectedByAuthoring` is asserted to equal
`PlanAuthoringError.description` verbatim, pinning the one deliberate exception; and the
correction channel is asserted, separately, to still name the precise field for every
case that has one. `PlanDraftingNoticeTests` gained three tests replacing the one that
used to assert the bug (`testARejectedProposalCarriesTheCorrectionTextVerbatim`, which
asserted the card *did* contain `error.description` — now asserting the opposite) and
confirming the `.rejectedByAuthoring` case still reads its one shared sentence through
`PlanDraftingNotice` end to end.

**Scope discipline.** `Dashboard/ScoreCalendar.swift` and `App/Dashboard/ScoreCalendar*`
(MAX-159's files) were not touched. No file outside `Sources/MaximizeCore/Plan/` and its
tests was edited.

### What CI can and cannot prove

CI proves: the package compiles; every `PlanProposalError` case maps to a distinct,
non-empty, quotation-mark-free sentence with no `default` branch to fall through to; the
correction channel (`description`) still names the precise field for every case that has
one; and the `.rejected` path of `PlanDraftingNotice` reads the new type rather than the
old one. It cannot prove the plan proposal card actually renders this text on a device,
or that a real rejected proposal from Anthropic reaches this path the way the tests
simulate it. See the PR's **Needs device verification**.

---

## MAX-165 — the first plan's date covers captured history (A23)

**The defect, and why it was invisible.** Three behaviours, each correct on its own:
`AnchoredIngestionPolicy.standard` backfills 90 days on the first successful pass;
`PlanAuthoringSession` suggested `today.startOfTrainingWeek()` for a first plan; and a
workout on a day no plan governs is stored *without* derived metrics and reported as
`.workoutPredatesEveryPlan`. That third reason never resolves — MAX-011 forbids a later
version from opening before an earlier one, and `App/IngestionComposition.swift` says so
in a comment. Composed, they mean an athlete who accepted the suggested date on the day
they installed the app permanently stranded ~89 days of their own history. Nothing on
screen said how many, or that it had happened. Filed as **R16**.

**The fix is where the defect is, not where it hurts.** MAX-011's rule is what makes
historical scores reproducible and is not weakened by a line. `earliestEffectiveFrom` was
*already* `nil` for `.firstPlan` — the core has always permitted a first plan to reach
backwards, because there is no earlier version to re-govern. What was missing was a
suggestion that used the permission.

### What `.firstPlan` suggests now

`FirstPlanDating.suggestedEffectiveFrom(covering:today:)` — **the earlier of the earliest
captured workout's day and the current training week's Monday.**

- The earliest captured workout's day is A23, and it is the only date that brings the
  whole backfill under a plan.
- The Monday is kept as a *ceiling* rather than dropped, which is a small deliberate
  refinement of A23's literal wording ("the earliest workout's day, falling back to
  `startOfTrainingWeek()`"). Where the two differ — an athlete whose entire history falls
  inside the current week — both cover every captured workout, and the Monday additionally
  keeps the whole-week start that arc weeks and the Monday-first template were designed
  around. It also buys an invariant worth having: **the new suggestion can never be later
  than the old one**, so it can only ever exclude fewer workouts, never more. There is a
  test asserting exactly that across five histories.
- No workouts stored: the Monday, unchanged. Nothing to cover, and a plan dated
  arbitrarily far back would claim days it has no business claiming.
- Earliest older than the backfill window: not a case to defend against. A workout the
  ingester never fetched is not in the store and no effective date can reach it. The
  suggestion covers everything the device holds, which is all a plan can do.

**Is a plan dated before the athlete's real training start harmful? No, and the asymmetry
is the argument.** A plan governs *days*; a day before they trained is a day with no
workout on it. It acquires no score, enters no tally that counts sessions, and produces no
obligation anyone sees — `PlanCalendar` would answer "easy 8 km" for a Tuesday in their
past and nothing asks it. Dating too early costs a hypothetical answer nobody requests;
dating too late costs a workout that can never be measured. Those are not comparable, so
the suggestion errs in the recoverable direction.

### The number, which matters more than the default

The athlete can still move the date, and a date picker that silently strands 89 days *is*
the defect. `CapturedWorkoutHistory.workoutsExcluded(byEffectiveFrom:)` counts what a
candidate date leaves outside every plan version, and `PlanCopy.excludedWorkoutsNotice`
turns it into the one sentence the screen shows. Both are core, both under test.

- **Inclusive of the effective day itself**, matching `PlanCalendar.plan(on:)`. Boundary
  tests walk same-day, day-before and either side.
- **Counts workouts, not days** — two runs on one day are two workouts a date can strand.
- **Nil at zero, not "0 workouts"**: absence is the designed state, and a rendered zero
  would turn the ordinary case into a warning to be dismissed on every screen.
- **Always zero for a revision**, and gated on `Mode` rather than on arithmetic. A
  revision cannot strand anything — every day before its date is already governed by the
  version it supersedes — and running the first plan's arithmetic there would put a large,
  entirely false number in front of an athlete whose history is wholly covered.

### D8, checked rather than assumed

Stranded workouts were never scored, so completing them later is not a rescore. That was
verified against `completeIngestion(forWorkout:)` rather than asserted: its only early
return is on an existing `ScoreLedger`, and a workout with no derived metrics has none, so
enrichment runs in full. `applyScore` re-reads the ledger before the model is ever asked,
and `recordAutomaticScore` is D8's actual enforcement point either way. Nothing in this
ticket reads or writes a score.

### App layer, deliberately thin

`PlanAuthoringModel` gains a `WorkoutRepository` it reads once, at load, only to build a
`CapturedWorkoutHistory`; `Editing.excludedWorkoutsNotice` is a computed passthrough to the
session; the view adds one `quietText`. No date arithmetic, no counting, no copy in either.

One asymmetry worth naming: a failed workout read reaches `.failed` rather than degrading
to "nothing captured", unlike the distance-unit read beside it. Assuming an empty history
would suggest the exact date this ticket exists to stop suggesting *and* suppress the count
line while doing it. In practice this and the plan read are the same store, so a workout
read failing alone is close to unreachable.

### Found, reported, not taken

- **A workout that syncs after the first plan is saved, dated before its effective date,
  is stranded identically and still silently.** A late Watch sync or a Health import from
  another app does this. Outside first run; named in FIRST-RUN-SPEC §7.4 and now in R16's
  status line. **Not fixed here** — it wants its own ticket, and the honest fix is probably
  a visible count of unmeasurable workouts rather than anything in the authoring screen.
- `PlanAuthoringFormatting.explain(.firstPlan)`'s prose already states the permanence
  correctly and needed no change; what it could not state was the number, which is now
  stated beside the control that decides it.

### Tests

New file `Tests/MaximizeCoreTests/FirstPlanDatingTests.swift`: the suggestion covers the
earliest captured workout; the no-workouts-yet fallback; the default-parameter
compatibility case; the ceiling case; the never-later-than-before invariant; a history
older than any backfill window; the count at same-day and day-before and across a
three-day walk; workouts-not-days; zone-dependent day resolution; the notice's singular,
plural and absent forms; and two revision tests pinning that D1's bound and the
zero-exclusion answer both hold.

**And the end-to-end pair, which is what proves the ticket did its job.** A run is
captured on 2026-01-01 with no plan authored, and is stored with no derived metrics. 63
days later — inside the 90-day window — the authoring session is built from the store and
its suggested date accepted: the run acquires its metrics under version 1, driven through
the real `WorkoutIngestionPipeline`. The sibling test authors the *old* suggestion instead
and asserts the run stays unmeasured with `.workoutPredatesEveryPlan` reported, and that a
later version dated to rescue it is refused — so nobody reintroduces the old default
believing it was harmless.

### What CI can and cannot prove

CI can prove: the package compiles, the suggestion and the count are correct at their
boundaries, the notice's exact wording, that a revision is unchanged in every respect, and
— end to end, against the real pipeline — that a stranded workout acquires derived metrics
under a first plan dated by the new suggestion and does not under the old one.

CI cannot prove anything about the screen. It never draws a pixel.

**`swift build`/`swift test` were not run** — no Swift toolchain in this container (R1).

**Needs device verification:**
- Open the plan-authoring screen with no plan authored and workouts already captured.
  Confirm "First day governed" opens on the earliest captured workout's date, not this
  week's Monday.
- Drag that date forward past some captured runs and confirm the count line appears
  beneath the picker, updates as the date moves, and reads with the right singular/plural.
- Drag it back to the suggested date and confirm the line disappears entirely rather than
  reading "0 workouts".
- Confirm the line wraps legibly at large Dynamic Type sizes — it is the longest sentence
  in that section.
- Open the screen to author a *revision* and confirm no count line appears at any
  permitted date, and that the earliest-permitted bound is unchanged.
- Save the first plan at the suggested date, then open a workout from before this week and
  confirm it now shows derived metrics (this is `completeIngestion` on appear doing its
  job; it is the whole point and only a device can show it).

---

## MAX-162 — the first-run checklist, in the core

Four facts in — has the Health sheet been presented, is a plan version stored, is a key
stored, is any workout stored — and out come the outstanding steps in ask order and the
single next action. Pure core (`Sources/MaximizeCore/FirstRun/`), no view, no framework,
every branch executed by CI. FIRST-RUN-SPEC §3, §5, §8, §9.

### The seam MAX-163 and MAX-164 read

The interface matters more than the internals here, because two tickets consume it.

- **MAX-164 (setup card) reads `FirstRunChecklist.card`** — one `FirstRunCardState?`,
  switched over, `nil` meaning no card — and `FirstRunCopy.card(_:)` for the words. That
  value is a `FirstRunCardCopy`: `heading`, `body`, `detail` (a second paragraph at
  secondary weight, present only for the waiting state), `action: FirstRunStep?` and
  `actionLabel: String?`. **The card assembles nothing**: it never branches on `facts`, and
  it never writes a sentence.
- **MAX-163 (launch cover) reads `FirstRunCopy.cover`** and nothing else here — `title`,
  `health`, `privacy`, `continueLabel`, plus `paragraphs` for laying the two out. The
  cover's *gate* is that ticket's own `FirstRunPresentationRecording`, deliberately not
  defined here.
- **Either, later:** `remainingSteps` and `nextStep`, if the owner decides the card should
  list all three steps rather than the next one (spec §15 q2). Both ship today so that is a
  view change, not a redesign.
- **`healthAccess` must be the device-lifetime answer, not the launch's.**
  `HealthAccessState.notRequestedYet` is documented as "not presented *on this launch*",
  because the Settings section holds it in `@State`. A checklist built from that value puts
  "Health access has not been requested" on the card at every launch of a working install —
  §5.4's nag, exactly. MAX-163's recorded presentation is what resolves to
  `.requestAnswered`. Documented on `FirstRunFacts`; **this is the likeliest wiring mistake
  in the set.**
- **§5.4's "the card does not come back" is MAX-164's**, and is stated as such: this type is
  a pure function of facts and cannot express "already shown once".

### R10, structurally rather than editorially

`FirstRunStep` models **no per-step completion** — no `isComplete`, no `.done`, no case
standing for a step that has been taken — and the Health step has **no completed state**. A
step that has been done leaves `remainingSteps`; it never sits in it wearing a tick. So a
view cannot render "Health ✓" from anything in this module, because no value means it. The
banned-phrase test was **extended over `FirstRunCopy`** rather than duplicated
(`FailureCopyTests.testNoHealthCopyClaimsAccessWasGrantedOrRefused`), per spec §9.3 and
CLAUDE.md's instruction about the analogous hue rule.

### Decided

- **Health → plan → key, and the order is a property, not case order.**
  `FirstRunStep.recovery` states what a delay costs — nothing arrives until Health is
  answered; a plan is irrecoverable only before the date it is eventually given; a key is
  fully recovered whenever it is done, because history is scored when next opened. The ask
  order is that, ascending, and a test asserts the two agree, so a step added later has to
  answer the same question to get a position.
- **A Keychain read that failed (`StoredAPIKeyPresence.unknown`) is not a missing key.** It
  produces no step and never the "No Anthropic API key" card. MAX-154's finding was exactly
  this conflation reaching a screen as a confident absence; Settings already says the honest
  thing where the athlete can act on it.
- **`.requestFailed` gets its own card**, because state 1's copy says the question has not
  been put and after a failed request that is false. Same button — asking again is the fix
  for both.
- **`HealthAccessState.healthDataUnavailable` gets a sixth card state, which is not in the
  spec's five.** The checklist takes a `HealthAccessState` (§9.1 requires it) and that enum
  has four cases. It carries no action — an athlete cannot install a Health store — and it
  empties `remainingSteps`, because a plan and a key would be steps toward data that can
  never arrive. **Flagged as a deliberate extension of the spec.**
- **Two spec sentences were reworded, and the phrase is now banned in the test.** §5.2's
  state 2 ("Runs are being captured…") and state 3 ("Your runs are captured and measured.")
  both assert that capture is happening — the one claim R10 says the app cannot make, since
  a refused read looks identical from inside. The shipped wording says workouts are stored
  *as they arrive*, and `"being captured"` is on the banned list so it cannot quietly come
  back. §8's wording, which the spec defends explicitly, is kept verbatim.

### Rejected

- **A `Bool` for "Health asked".** `HealthAccessState` and `StoredAPIKeyPresence` already
  carry the honest third answer for the two facts that can fail to be established; a boolean
  beside them is how MAX-154's defect happened.
- **A per-step `isComplete`, even defaulted to false.** It is the one field from which a
  tick could be drawn, and the whole R10 defence is that no such field exists.
- **Collapsing §8's second paragraph into `FailureCopy.noWorkoutsRecorded`** (spec §15 q4,
  "try collapsing first"). Tried: that string opens "No workouts yet.", which under a heading
  already reading "Nothing recorded yet." is the same sentence twice on one card. They are
  written for different moments. A test asserts both still name the same recovery path in
  Settings, which is the drift that would actually matter.
- **Copy for the `.unknown` key state.** Two voices on one fact, and a nag built on a guess.

### Tests

`Tests/MaximizeCoreTests/FirstRunChecklistTests.swift` resolves **all forty-eight
combinations** of the four facts and asserts over the whole set: that the card's action is
always the next step (two independent derivations that must never disagree), that at most
one action is offered however many steps remain, that Health outranks everything while it
is still a question, that the key is never asked before the steps above it, that remaining
steps are always in ask order, that `.unknown` never becomes a missing key, that a device
without Health data is told so and asked for nothing, and that the only combination with no
card is the fully settled one. Plus the two named windows — set up with nothing recorded,
and set up with something recorded — and copy properties: every state has its own heading
and sentence, the buttons are distinct, the ninety days in the waiting copy match
`AnchoredIngestionPolicy.standard.firstRunBackfill`, and no other string carries a digit
(the same privacy proof `FailureCopy` uses — nothing interpolates, so nothing can leak).

### What CI can and cannot prove

CI can prove: the package compiles, and every branch and every string of the checklist
behaves as above — including the R10 rule over both copy types.

CI cannot prove anything about a screen; no view exists yet. It also cannot prove the fact
*supply* is right, and that is the risk this ticket cannot close: a correct checklist fed
`HealthAccessState` from a per-launch `@State` would nag on every launch. MAX-163 and
MAX-164 carry that verification.


## MAX-163 — the first-launch cover

One `fullScreenCover`, mounted on `RootTabView`'s `TabView`. Its single action presents
the iOS Health sheet (`HealthAccessSettingsSection`'s call site, a second time); it reads
`FirstRunCopy.cover` and nothing else from MAX-162's module; it dismisses claiming no
result, ever. FIRST-RUN-SPEC §4, §9.

New: `Sources/MaximizeCore/FirstRun/FirstRunPresentationRecording.swift`,
`App/FirstRun/FirstRunCoverView.swift`,
`App/FirstRun/UserDefaultsFirstRunPresentationStore.swift`. Touched:
`App/RootTabView.swift` (mounts the cover and resolves the gate on appear).

### The gate: device-lifetime, and where it lives

MAX-162 flagged this as the likeliest bug in the set — a cover gated on
`HealthAccessState`'s per-launch `@State` would present itself on every launch of a
working install. Closing it took two pieces, both new:

- **`FirstRunPresentationRecording`** (core protocol) — `hasPresentedHealthRequest: Bool`
  and `recordHealthRequestPresented()`. Reached through a protocol, per CLAUDE.md, because
  `UserDefaults` is a platform type the core does not touch.
- **`FirstRunCoverGate.shouldPresent(_:)`** (core, one line: `!recording
  .hasPresentedHealthRequest`) — still put in the core and tested, because "should a
  screen appear" is a decision, not layout, and the whole point of this ticket is that the
  decision is provable rather than trusted to a view's `@State` initializer.
- **`UserDefaultsFirstRunPresentationStore`** (app adapter) — a single boolean key in
  `UserDefaults.standard`.

**Deliberately not added to `FirstRunChecklist`.** That type is MAX-164's seam and answers
a different question ("what is left to set up"); the cover's question — "has this specific
one-shot screen been shown before" — is narrower and unrelated to the other three facts.
`FirstRunChecklist` still composes `HealthAccessState.requestAnswered` from this same
recording, which is MAX-164's wiring to get right, not this ticket's.

### Decided

- **`UserDefaults`, not a file (MAX-031's anchor pattern) and not `AppSettings`.** The
  anchor store rejected `UserDefaults` because the anchor's correctness needs "durable the
  instant `save` returns," a promise `UserDefaults` does not make. This flag needs only
  "eventually true" — the failure mode of a delayed write is the cover appearing one extra
  time, and iOS itself makes a repeat `requestAuthorization` call idempotent once answered,
  so an extra presentation costs nothing but a tap. `AppSettings` (SwiftData) was rejected
  for the reason spec §4.4 gives directly: a store that fails to open must not be the thing
  that makes the one screen asking for health permissions reappear forever.
- **Reinstall resets the recording, on purpose.** `UserDefaults.standard` is removed with
  the app container, so a reinstall shows the cover again — correct, per spec §4.4: A8
  defers CloudKit, so a reinstall already loses every workout, plan and score, and re-asking
  the one question iOS will not let this app ask twice per install is the intended
  behaviour, not a gap.
- **The recording is written the instant Continue is tapped, not conditioned on what the
  Health call returns.** Considered recording only on `HealthKitObserverError
  .healthDataUnavailable` — throws before HealthKit is ever asked, so no sheet exists to
  present. Rejected in favour of recording unconditionally: a device with no Health store
  fails identically on every future attempt, so *not* recording there would present the
  cover on every single launch forever — precisely the nag this ticket was warned about,
  and worse than the alternative. Recording unconditionally costs nothing on the path where
  the sheet really was shown, because iOS's own repeat-call behaviour (no UI on a second ask
  once answered) makes "asked again" harmless.
- **`fullScreenCover`, not `sheet`.** A drag-dismissible sheet lets someone dismiss the one
  screen that explains what is about to be asked without reading it — a small departure
  from the lighter presentation this app otherwise reaches for (`ChatSheet`, the Settings
  sheet), named here per CLAUDE.md's "say why" on a deliberate default departure.
- **The primary button is `.buttonStyle(.borderedProminent)` + `Color.accent`**, matching
  `PlanView`'s "Author a plan" — the system's own current control, not a hand-rolled
  capsule, per the same rule `glassChrome` enforces for chrome.

### Rejected

- **A checkmark, a "Health connected" line, or any second screen after the sheet returns.**
  R10: iOS never reports read-access outcome, and this is the one screen where that claim
  would be most tempting. The view draws nothing from the call's result either way — see
  `presentHealthSheet()`'s empty `catch`.
- **Reading the caught `Error` for anything, including a log.** An arbitrary HealthKit
  `Error` may carry sample values in `userInfo` (CLAUDE.md — health data does not go into
  logs). The failed-request sentence a person eventually sees comes from MAX-164's card via
  `HealthAccessState.requestFailed`, never from this view.
- **New `FirstRunCopy` strings.** The ticket's own instruction: read `.cover` and nothing
  else. Nothing here needed a word MAX-162 had not already written and tested.

### Tests

`Tests/MaximizeCoreTests/FirstRunCoverGateTests.swift`: the cover presents on a fresh
install (an unrecorded fake), does not present once recorded, recording is idempotent
across repeated calls, and — the acceptance criterion the ticket named explicitly — the
recording survives a *simulated* relaunch: a second, independently constructed fake seeded
with what the first one wrote stands in for a new process, the same technique
`FirstRunChecklistTests` uses elsewhere in this module for "a fresh install" without
running one.

### What CI can and cannot prove

CI can prove: the gate's decision is correct against a fake for every combination this
ticket defined — fresh, recorded, idempotent-recorded, and simulated-relaunch. The package
compiles and the app shell builds against Xcode 26's simulator SDK.

CI cannot prove, and this PR says so under **Needs device verification**: that a
`fullScreenCover` actually appears on a fresh install; that tapping Continue actually
presents the iOS Health sheet, or what it looks like; that a real app relaunch — not a
second fake object standing in for one — leaves the `UserDefaults` write intact; that the
cover's copy fits at Dynamic Type AX5; that Reduce Transparency and Increase Contrast leave
the screen readable (`.contentSurface(.screen)` is already opaque by construction, so this
is a lower-risk check than most, but it is still a device check, not a proof).
**`swift build`/`swift test` were not run** — no Swift toolchain in this container (R1).

---

## MAX-164 — the setup card on the Workouts tab

`App/FirstRun/FirstRunCardView.swift` renders `FirstRunChecklist.card`'s six states
(`FirstRunCopy.card(_:)` for every word) above the workout list; `App/FirstRun/FirstRunModel.swift`
is the async plumbing that reads the four facts and re-resolves the card on appear and
after each of the card's actions returns. `App/WorkoutsView.swift` wires both in and
answers the three actions: Health access in place, "Author a plan" pushed (matching
`PlanView`'s own entry point), "Add a key" presented as a Settings sheet. FIRST-RUN-SPEC
§5, §8. No change to `Sources/MaximizeCore/`.

**Landed in two passes.** First opened before MAX-163 merged, with `healthAccess` held in
memory and the gap below reported rather than closed. MAX-163 landed
`FirstRunPresentationRecording` shortly after, and this PR was updated in place — same
branch, same ticket — to read it, closing the gap before merge. The section below is kept
as "closed" rather than rewritten as if it were never open, because the reasoning for
*why* the reconciliation below is not a plain pass-through is worth keeping on the record.

### Decided

- **The card is a fixed header above every load state of the list**, not only the loaded
  one — `.loading`, `.failed` and the empty state all get it too, because none of those
  states are gated on setup being complete and the card's own presence is what answers
  "why is this list not helping me yet."
- **`FailureCopy.noWorkoutsRecorded` is suppressed while the card is showing.** Both are
  independently correct absence copy, and stacking them **is** the mistake FIRST-RUN-SPEC
  §8 considered and rejected for the card's own two paragraphs — extended here to the two
  *surfaces*, not just the two sentences the spec was originally weighing. Once the card
  is gone this is the sole absence message again, exactly as before this ticket.
- **"Author a plan" pushes `PlanAuthoringView`, not a sheet.** `PlanView` already opens the
  same screen the same way for the same first-plan case, worded identically
  (`FirstRunCopy.actionLabel(for: .authorAPlan)` = "Author a plan" = `PlanView`'s own
  button); matching that precedent beat matching `SettingsView.planSection`'s sheet,
  which exists for a *different* entry point (revising from Settings).
- **The Health-request adapter (`FirstRunModel.requestRealHealthAccess`) and the Keychain
  presence read (`FirstRunModel.resolveKeyPresence`) are duplicated from
  `HealthAccessSettingsSection` and `SettingsView`, not shared.** Both views are outside
  this ticket's file list; both duplicates are three lines of adapter with no decision in
  them (the decision — what a result *means* — is `MaximizeCore`'s). Flagged for a future
  ticket that touches both spots to fold into one.
- **`FirstRunModel.requestHealthAccessTapped()` also calls
  `presentationRecording.recordHealthRequestPresented()`**, not only the launch cover.
  This card's own Health button is reachable — the rare, crash-recovery path
  `FirstRunCardState.healthAccessNotRequested`'s own doc comment names ("a cover dismissed
  by a crash, a store that failed at the wrong moment") — and if a tap through *this* door
  left the recording unwritten, `FirstRunCoverGate` would still believe the sheet had never
  been shown and reopen the full-screen cover on top of an otherwise working install on the
  next launch. Recording is idempotent (MAX-163's own guarantee), so this costs nothing on
  the ordinary path where the cover already wrote it first.

### Closed: `healthAccess` now reads MAX-163's device-lifetime recording

MAX-162's own note had named this "the likeliest wiring mistake in the set." This PR opened
before MAX-163 merged, with the gap reported rather than closed (`healthAccess` held in
memory, seeded `.notRequestedYet`, per this ticket's scope discipline against adding the
missing protocol itself). MAX-163 landed `FirstRunPresentationRecording` immediately after,
and this same branch was updated to read it before merging — `FirstRunModel
.resolveHealthAccess()` composes `presentationRecording.hasPresentedHealthRequest` with a
capability check, rather than passing the recording straight through:

- Not yet presented → `.notRequestedYet` — unchanged from a fresh install's answer today.
- Presented, and `HKHealthStore.isHealthDataAvailable()` says this device can provide
  Health data → `.requestAnswered`. The recording only ever means "the sheet was presented
  and answered" (its own doc comment); it never means granted or refused (R10), so
  `.requestAnswered` is the strongest honest reading of a `true` recording.
- **Presented, but this device has no Health store → `.healthDataUnavailable`, not
  `.requestAnswered`.** This is the reconciliation the coordinator asked for by name:
  MAX-163's recording is written the instant the cover's Continue button is tapped,
  *unconditionally* — deliberately not gated on the Health call succeeding, because a
  device with no Health store fails that call identically forever and gating the recording
  on success would rebuild the every-launch nag through another door. Trusting the
  recording alone here would read a `true` value on such a device as "answered" and put a
  plan-and-key checklist in front of an athlete on hardware that can never receive a
  workout. `isHealthDataAvailable()` is a synchronous capability check with no privacy
  surface — "does this hardware support HealthKit," not anything about the athlete — so
  reconciling on every `load()` costs nothing and needs no permission.
- `.requestFailed` stays reachable only within the current session
  (`sessionHealthAccessOverride`), never from the persisted recording: once presented, the
  recording cannot un-present itself, so a relaunch cannot distinguish "answered" from
  "failed for a reason other than device capability." MAX-163's own reasoning is that this
  does not need distinguishing past the current session, because a repeat
  `requestAuthorization` call is itself idempotent and harmless once the sheet has been
  shown once.

**Consequence, now closed:** an athlete who granted Health access on a past launch sees the
correct downstream card (plan, key, or nothing) on the very next launch, whether or not
they ever touched this ticket's own Health button — the cover's recording and this card's
now agree, because both write to and read the one `FirstRunPresentationRecording`.

### Rejected

- **Combining the six states' rendering with a branch in the view.** `FirstRunCardView`
  switches on nothing; `copy.detail` and `copy.actionLabel` being `nil` on the states that
  have neither is what makes the layout unconditional. A view-side `switch state` would
  have duplicated `FirstRunChecklist`'s own case list for no reason.
- **A checklist-style list of all three steps.** The type carries `remainingSteps` for
  this (FIRST-RUN-SPEC §5.3, §15 q2); MAX-164 renders `card` only, per the spec's decision
  that a checklist reads as a nag and the single next action reads as guidance.

### What CI can and cannot prove

CI can prove: the app target compiles, `xcodebuild` links `MaximizeCore` and
`App/FirstRun/`'s two new files against it, and — unchanged by this ticket —
`FirstRunChecklistTests` and `FailureCopyTests` still hold `FirstRunChecklist`/`FirstRunCopy`
to every branch and the R10 banned-phrase list.

CI cannot prove anything this ticket actually changed: that the card renders correctly at
any state, any Dynamic Type size, or under Increase Contrast/Reduce Transparency; that the
three actions reach the right screen and the card disappears on return; that the
Health-request button actually presents the iOS sheet; or — the one that matters most for
this pass — that a `UserDefaults` write from this card's own Health button, or from the
launch cover, is actually read back as `true` by the other on a real relaunch. Both
`FirstRunCoverGateTests` (MAX-163) and this ticket's reasoning above are proven only
against a fake; the real adapter is untested by construction (R1, no toolchain, no
device). See the PR's "Needs device verification" section for the checklist.

**`swift build`/`swift test` were not run** — no Swift toolchain in this container (R1).
Nothing in this ticket touches `Sources/MaximizeCore/`, so neither suite's *content*
changed; `swift test` was not re-run to confirm the unmodified suite still passes.

---

## MAX-166 — the conversational route, offered from the authoring screen

FIRST-RUN-SPEC §10 argues at length against a conversational *first run* and settles on
the one place a conversational route belongs: "the authoring screen is where the
conversational route should be offered, since that is where a person who dislikes the
form is standing." §13 decision 5: "Offer it, from the authoring screen only, gated on a
stored key." This ticket builds the door, not a new drafting mechanism —
`ChatConversationView`'s "Draft a plan from this conversation" has shipped since MAX-101
and is unchanged.

**Premise checked against stored data first, per this ticket's own instruction.** The
affordance did not already exist, `PlanAuthoringView` had no reference to chat, and
`ChatConversationView`'s drafting entry point is reachable exactly as the spec assumes —
so the ticket proceeded as briefed.

### The gate, in the core

`PlanAuthoringConversationalRoute` (`Sources/MaximizeCore/Plan/`) reads
`StoredAPIKeyPresence` — the same three-state read Settings' key section and
`FirstRunModel` already use — and answers two things: whether the action is enabled, and
what the screen says either way. `.stored` and `.unknown` both enable it, matching
`StoredAPIKeyPresence.permitsClearing`'s own reasoning (Settings offers **Clear** on both
for the same "a failed read is not evidence of absence" argument, and `FirstRunChecklist`
makes the identical call for its own "add a key" step). Only `.notStored` disables it.

**Never a hidden button.** CLAUDE.md's "absence is a designed state" — the button always
renders; `PlanAuthoringConversationalRoute.explanation` supplies the sentence under it in
either state, worded to match `ChatFailureNotice.noAPIKeyStored(for:)`'s own register for
the missing-key case rather than writing a second sentence about the same fact. Tested in
`PlanAuthoringConversationalRouteTests` — every case of `StoredAPIKeyPresence`, both
explanations non-empty and distinct, the unavailable one naming Settings and not claiming
a key is stored.

### App layer, deliberately thin

`PlanAuthoringModel` gained one `keyStore: AnthropicAPIKeyStoring` parameter (defaults to
`KeychainAnthropicAPIKeyStore()`, matching `SettingsView`/`FirstRunModel`) and one
`resolveKeyPresence()` — the same three-state read duplicated a third time rather than
shared, matching `FirstRunModel`'s own reasoning for its duplicated
`performHealthAccessRequest`. `PlanAuthoringView` adds one `Section` (placed right after
"Current plan", ahead of the eleven-field form) with the action button and the core's
explanation text underneath, and a `.sheet(item:)` presenting `ChatSheet(subject:
.training(scope))` — a fresh training thread frozen to "this week", the same fallback
`ChatSheet.defaultInterval()` already resolves to. No change to `ChatSheet` or
`ChatConversationView`: both already supported this call shape.

**A14 held explicitly.** The button presents a sheet and calls nothing; `ChatModel` fires
only when the athlete sends a message inside the conversation it opens. **CHAT-FIRST
§2.5 held too**: the sheet opened is the same one MAX-101 already proved ends at
`PlanAuthoringView`, reviewed and saved by hand — this ticket adds a second door to it,
not a second way to write.

### Tests

`PlanAuthoringConversationalRouteTests` — nine tests, all in `MaximizeCore`, all
synchronous (the type carries no `@MainActor` state). No test touches `App/`, which is
never run by CI (R2/R13); the gate itself is what is verified there.

### What CI can and cannot prove

CI can prove: the package compiles, `PlanAuthoringConversationalRouteTests` holds the
gate to every `StoredAPIKeyPresence` case, and the app target still links.

CI cannot prove: that the button renders where intended, at any Dynamic Type size or
under Increase Contrast/Reduce Transparency; that a tap actually presents `ChatSheet`;
that the disabled state reads as disabled rather than merely dim; or that the "this week"
scope resolves sensibly on a real device's clock. See the PR's "Needs device
verification" section.

**`swift build`/`swift test` were not run** — no Swift toolchain in this container (R1).

---

## MAX-170 — the stall detector stops depending on the ping cadence

**MAX-152's threshold rested on a claim about the API that nobody had checked, and the
API's own documentation contradicts it.** `ChatReplyProgress.heartbeatsBeforeStall` was
two, justified as: "the API is documented as free to send a `ping` at any time … two in a
row with no token between them will not happen to a stream that is producing text." The
first half is right and the second half was an assumption.

### What was established

Read from the current Messages API streaming documentation, which is authoritative here:

- **Pings carry no cadence guarantee of any kind.** The whole of what is specified is
  that event streams "may also include **any number** of `ping` events" and that "there
  may be `ping` events **dispersed throughout the response**". No interval, no frequency,
  no upper or lower bound, no statement that the rate is stable across models, effort
  levels or load.
- **Pings during ordinary generation are the documented shape, not an edge case.** The
  published streaming examples place a `ping` *between two consecutive `text_delta`
  events*, and another between `content_block_start` and the first delta. So a healthy,
  actively-producing stream demonstrably emits pings mid-reply.
- **The stream's shape is explicitly not frozen.** The versioning policy reserves the
  right to add event types and instructs clients to tolerate unknown ones, so even a
  cadence measured today is an implementation detail rather than a contract.
- **The failure mode was live, not theoretical.** Community reports against the Anthropic
  TypeScript SDK (anthropics/anthropic-sdk-typescript#998, and the Claude Code hang it
  cites) describe pings as a roughly fifteen-to-thirty-second liveness signal, and
  separately describe high-effort Opus replies going quiet for sixty to a hundred and
  twenty seconds between deltas during a thinking pass. Those two figures together put a
  perfectly healthy reply at somewhere between two and eight consecutive quiet beats —
  the low end of which is exactly MAX-152's threshold. **A slow reply rendering as
  stalled was not a remote possibility; it was the expected case.**

### What could not be established, and it is the important half

**Nothing about the real cadence.** It is not documented, the numbers above are
third-party observations with no Anthropic confirmation, and the SDK issue that reports
them proposes that the server should start advertising its own next-ping interval —
which is an admission by its author that the interval varies and cannot be assumed. CI
opens no sockets, so nothing in this repo can measure it either. **Any constant chosen
here is a guess, and choosing a larger one would only have moved the guess.**

### How the design tolerates being wrong

The rule no longer asks how many beats mean a stall in general. It asks how many beats
mean a stall *on this stream*, and lets the stream answer.

- **Every quiet run that ends in a token is evidence.** It proves this connection goes
  that quiet while healthy. `longestHealthyQuietRun` records the largest such run, and
  the bar (`heartbeatsRequiredForStall`) sits a margin above it. A chatty-ping stream
  teaches the machine to expect chatty pings.
- **Beats before the first token calibrate it too**, which is the case that matters most.
  A long thinking pass is precisely when the cadence is measurable and precisely what the
  old rule would have mistaken for a stall; now the token that ends the pause records the
  whole run as normal.
- **Calibration is a `max`, so it only ever raises the bar.** No stream can make the
  machine more trigger-happy than the floor.
- **It cannot be talked out of firing.** `longestHealthyQuietRun` moves only on
  `.textArrived`, so once text genuinely stops the bar is frozen while the quiet run
  grows without limit. Every dead stream crosses it. That termination property is tested
  across every calibration level rather than asserted.
- **Being wrong stays cheap in the direction it can still be wrong.** The floor is the
  one remaining guess. Too high only delays an advisory line. Too low shows that line
  early on a working reply — and the rung is withdrawn by the very next token, its copy
  ("Still connected — nothing new for a moment.") says the connection is fine rather than
  that anything broke, and surviving one stall raises the bar so the same reply is not
  accused twice. A wrong floor produces a true sentence slightly early, not a healthy
  reply presenting as a dead one.

**Which side of MAX-152's line this falls on.** MAX-152 rejected deciding a stall *by*
elapsed time, and that still stands: there is no clock, no `Task.sleep`, no injected date,
and the machine remains a pure fold over stream events that CI runs in microseconds. This
change only *refuses to declare* a stall until the stream has produced more silence than
it has ever produced while working. Counting rule, not timing rule.

### The MAX-152 tests that were deliberately changed

None were weakened; four stopped pinning a number this ticket deliberately moved.
`testASingleQuietBeatMidReplyIsStillStreaming` asserted the constant equals two and now
asserts it exceeds one — the property that actually makes the case meaningful.
`testAStalledReplyGoesBackToStreamingWhenTextResumes`,
`testWaitingStreamingAndStalledAreThreeDistinctStates` and
`testAStalledReplyCanStillCompleteNormally` each built a stall by writing two heartbeats
literally; they now read the bar from the type, and the first and third gained an explicit
assertion that the premise holds (that the reply really is stalled before the thing under
test happens), which the old versions never checked.

**The recovery bug the ticket asked about does not exist.** `.textArrived` guards on
`phase.isLive`, `.stalled` is live, so text after a stall already returned the reply to
`.streaming`, and MAX-152 had a test for it. Verified rather than assumed; the coverage is
now extended to a stall that resumes, keeps streaming and then completes.

### Reported, not done — a pinging-but-dead stream never terminates

MAX-152 stated its cost as "a connection that hangs and sends no pings stays `.streaming`
until the client's own idle timeout turns it into `.failed(.interrupted)`". **The mirror
image is worse and was unstated.** `AnthropicStreamingChatClient.idleTimeout` is a
`URLRequest.timeoutInterval` on a streaming response — a *byte-level* inactivity timer
that resets whenever data arrives. A ping is data. So a connection that has died on the
model's side while its keep-alives continue **never trips that timeout at all**: the
request is held open indefinitely by the very frames that prove nothing is being said.

For that stream `.stalled` is the only signal the app has, and it is not a terminal
state — the reply stays live, the composer stays blocked, and nothing ever resolves. That
is why the bar above must stay finite, and it is why the honest fix is a turn-level budget
in the app layer (a cap on total quiet beats, or on wall time, that produces a real
terminal failure) rather than anything else this ticket could do in the core. **Outside
MAX-170's scope and outside `MaximizeCore` — reported here for its own ticket.**

**`swift build`/`swift test` were not run** — no Swift toolchain in this container (R1).
The change is pure core logic, so CI proves the rule end to end; what CI cannot prove is
the live cadence the floor is calibrated against. See the PR's "Needs device verification".
## MAX-173 — a rubric fix can reach a stored plan

**The gap, and why it was invisible.** `PlanAuthoringSession` reached
`StandardPlanSeed.rubricBands()` at exactly one place — the `.firstPlan` branch. Every
revision built with `rubricBands: current.rubric.bands`, carrying the stored bands forward
verbatim, and chat proposals (MAX-141/148) went through the same door and inherited the same
stale bands. Each half was correct on its own: D1 says a seed is authoring input and must not
reach a stored plan, and carrying a revision's bands forward is what stops a seed edit
silently re-writing a rubric an athlete tuned. Composed, they meant **no seed-side rubric fix
could ever reach a plan that already existed** — a whole class of correction with no delivery
route. Found by MAX-168 when it refused to open the lift-scoring gate.

**Two corrections were stranded.** MAX-132's three `lift.*` adherence bands — a stored plan
resolves `bands(for: .lift)` to `[skipped, fallback.recorded]` and lands on the catch-all, so
even authoring a lift day through chat could not reach them. And MAX-146's
`.actualDiscipline(oneOf: [.run])` on `rest.ranAnyway` — a stored plan's copy is
unconditional, so a lift on a day prescribing no lift matches it and is permanently stamped
*"Ran on a scheduled rest day."*, 50–75.

**The mechanism, and it is the one D1 already provides.** A session now holds two band lists
— the superseded version's, and the ones this build ships — and `adoptsCurrentRubric` decides
which the saved version carries. `adoptingCurrentRubric(_:)` returns a copy; there is no
setter, no code path that mutates a stored plan's rubric in place, and no migration. A rubric
change is a **new version with its own `effectiveFrom`**, written through the one door that
already existed (`plan(from:effectiveFrom:)`, A13's "opens by hand").

**Decided: adopt by default, state it, allow a decline.** Three arguments, none carrying it
alone. (1) *Nothing stored carries athlete intent* — there is no band editor and never has
been, so every band in every stored plan is a past copy of the seed; adopting takes the
corrected version of rules the athlete never chose. (2) *It cannot move history* — scoring
resolves the version in effect on the workout's own date, so the blast radius is days on or
after a date the athlete picks. (3) *Declining is the failure with no exit* — leaving it off
keeps a rubric that calls every lift a run, forever. The default lives in `MaximizeCore`, not
in the view, deliberately: a screen that had to remember to switch the fix **on** is one
forgotten call away from the defect, which is R13's signature.

**Decided: a plain statement, not a band-level diff.** A deliberate departure from the
proposal card's per-field diff (MAX-101/141), and the honest answer.
*"`.metric(averageHeartRateBPM, greaterThan, .heartRateCap(offsetBPM: 8))` gained
`.actualDiscipline(oneOf: [.run])`"* is a sentence about a data structure; an athlete asked to
approve it can only guess. `RubricBand.rationale` is the one renderable field — it is the line
that appears in a verdict header — so the section states counts ("3 added and 2 changed") and
lists the rules in the exact words they will later use. A test asserts the notice speaks no
band identifier and no condition case name.

**Decided: a revision, with its own section — not its own action.** A `Plan` has no partial
form; `PlanCalendar` resolves one record per date, so "change only the rubric" already *is*
"author a new version identical except the rubric". A separate action would mean a second path
to `PlanRepository.store(_:)`, which A13 forbids. It gets its own section rather than being
buried in the week grid, and the copy states that saving without touching anything else
changes nothing but the rules and the start date.

**A hand-authored rubric is a non-case today, and the decline path exists anyway.** No band
editor means no stored rubric can differ from some past seed.
`PlanAuthoringTests.testARevisionThatDeclinesKeepsTheStoredRubricBands` pins the decline
against a rubric only a test can construct. **If a band editor ever ships, the default must be
revisited** — at that point a stored rubric means something, and `adoptingCurrentRubric(false)`
is the behaviour to make the default. That is written into `PlanAuthoringSession`'s own doc
comment, beside the argument it would invalidate.

**One assertion was deliberately reversed.**
`PlanAuthoringTests.testRevisionCarriesTheStoredRubricBandsRatherThanReseeding` asserted the
old behaviour unconditionally — "the seed must not leak into a revision". That turned out to
be the defect. It is now `testARevisionThatDeclinesKeepsTheStoredRubricBands`, pinning what
remains true regardless: a rubric an athlete settled on is still reachable and still preserved,
by declining. `StandardPlanSeed`'s own doc had three paragraphs asserting the invariant this
ticket changes ("Revisions do not re-read it", "cannot reach a stored plan, and does not try
to"); all three are corrected rather than left as a false invariant a future reader would trust.

**What CI proves.** A revision of a plan carrying pre-MAX-132/146 bands adopts all three lift
rows and `rest.ranAnyway`'s condition, and `bands(for: .lift)` goes from
`[skipped, fallback.recorded]` to the five rows it should have been. **D8 with fixtures:** the
same lift on the same day under version 1, evaluated against a calendar with and without the
adopting version, produces an identical whole `RubricEvaluation` — same plan, same resolved
day, same band, same permitted range — and an easy run is asserted the same way so the proof is
not only about the defect. MAX-011 still refuses a back-dated version. A plan already carrying
the current rules yields an empty update, a nil notice and byte-equal adopt/decline plans; a
first plan has nothing to adopt. **The stored-payload no-op:** nothing here is persisted —
`adoptsCurrentRubric` and `PlanRubricUpdate` live on `PlanAuthoringSession`, never written to
disk — so a stored plan round-trips unchanged and its JSON gains no key.

**What CI cannot prove, and the owner action that is the whole deliverable.** CI never draws a
pixel, so the section's appearance, its Dynamic Type behaviour, its VoiceOver reading and its
degradation under Reduce Transparency are unverified. More importantly: **shipping the
mechanism is not the same as the fix being in effect.** The owner has to open Plan → revise →
Save, choosing the start date deliberately, before any lift is judged by the corrected rules.
Until they do, every device still carries the old bands. MAX-168 depends on that having
happened, not merely on this being merged.

**`swift build`/`swift test` were not run** — no Swift toolchain in this container (R1). CI is
the compiler.
## MAX-168 — the lift ingestion gate, opened on three conditions

**What the owner sees the next time they open the app: nothing new is scored.** Not one
lift on the device can pass the gate today. Every historical lift is missing A22's
muscle-group entry (condition 2), and the seeded week prescribes no lift day, so even one
that had an entry would land on the rubric's catch-all rather than on a lift band
(condition 3). The launch-time `backfillDistanceSplits()` sweep still re-enriches up to 25
workouts and still reaches `applyScore`, and for a lift it now returns one line earlier
than it used to, with a different reason and the same outcome. **No run score moves, no
stored score is touched, and there is no backfill, rescore or new scoring pass in this
ticket** (D8). The first lift that scores will do so because the owner did three things
deliberately: answered *"Tell me what you trained"*, authored a revision that prescribes a
lift day, and let that revision adopt the current rubric (MAX-173's section).

**The three conditions, and where each is checked.**

1. **`ActivityType.isScoreable`** — `isRun || discipline == .lift`. MAX-111's predicate was
   `isRun`, and the four places that asked it ("will a score ever be reached?") were right
   only while the rubric's whole vocabulary was running vocabulary. A ride, a hike and a
   walk are still `false`, and permanently: they occupy the run slot by A17 without being
   runs, `Discipline` is closed at two cases, and there is no band editor with which an
   athlete could ever author a rule naming one.
2. **A22's entry**, read from `MuscleGroupEntryRepository`, before the context is built.
3. **`RubricEvaluation.bandNamesItsDiscipline`**, after the rubric has been applied.

**Condition 3 is the ticket's real decision, and it is a question asked of stored data.**
The brief's options were: gate on the effective plan's rubric carrying a lift-safe
`rest.ranAnyway`, score anyway, or prompt. What is implemented is the first, generalised
so that it needs no reference to `StandardPlanSeed` — which matters, because *"nothing on
the scoring path consults this file"* is the property that makes D1 true rather than
aspirational. Instead of comparing a stored rubric to the seed, the gate asks the
evaluation what it matched: `RubricBand.names(_:)` is true only when the band carries an
`.actualDiscipline` condition naming this workout's discipline. Two failures collapse into
that one question:

- **A stale rubric.** A plan saved before MAX-146 carries an unconditional `rest.ranAnyway`,
  which matches any discipline routed to it — which every unprescribed lift is — and would
  stamp a strength session *"Ran on a scheduled rest day."* at 50–75, permanently.
  `testALiftUnderAStaleRubricIsLeftUnscoredRatherThanCalledARun` asserts the refusal **and
  the band that would otherwise have matched**, so the hazard is pinned rather than implied.
- **A current rubric with no ask.** The day prescribed no lift, so what matches is
  `fallback.recorded`. That row is the seed's honest answer for a *run* it has no rule for;
  it is not an opinion about unscheduled lifting. **MAX-146 explicitly declined to write
  that opinion** — *"it would need its own score range, and choosing one is a product
  opinion about how much an unscheduled lift should count for, which is not this ticket's
  to make."* Scoring here would write the unmade decision into a permanent record, at
  40–69, on every lift the athlete does outside their plan. Under D8 that is unrecoverable;
  declining to score is not. The catch-all is therefore **not** admissible, which is what
  makes the gate open onto MAX-132's bands and nothing else.

**A22 was a precondition the brief did not name, and honouring it is why the pipeline
grew a repository.** MAX-145's write-up states it plainly: *"A lift cannot be scored at
ingestion any more … a lift waits: not awaiting a model, not permanently unscoreable, but
awaiting the athlete."* MAX-145 could not implement it, because MAX-111's gate made it
moot, so what shipped was the header state and the sentence *"This lift isn't scored until
you set the muscle groups it worked."* Opening the gate without condition 2 would have
reversed an owner amendment silently and made that shipped sentence false. It is also the
conservative direction under D8 — a score not yet written can still be written; one
written blind cannot be taken back — and the day the fact sheet or the rubric learns to
read the groups (neither does today: `RubricCondition` has no case for them and the
scoring prompt carries only the *prescribed* groups), every lift scored before would have
been judged without them, forever. `WorkoutDetailModel.setMuscleGroups` now finishes
through `scoreIfNeeded()` rather than `load()`, so the answer unblocks the score on the
visit the athlete gives it.

**Four surfaces moved together, because "can this ever be scored?" had four readers.**
`WorkoutIngestionPipeline`, `WorkoutVerdict`, `ScoreCalendar` and `ChatModel` all split on
`ActivityType.isRun`; leaving three of them there would have had the app say *no verdict is
coming* about a lift it was in the middle of scoring. `.noVerdict` now holds exactly what
was always permanent — a ride, a hike, a walk — and its copy stopped saying *"the plan
scores runs"*, which had become the wrong half of the truth. **A22's state is checked
before the general wait** in `WorkoutVerdict`, deliberately: asking `isScoreable` first
would collapse `.awaitingMuscleGroups` into `.awaitingScore` and take the question off the
screen that asks it. **No calendar cell already drawn moves**: the day's speaking workout
is still a run wherever one was recorded — the picker gained a middle step rather than
having its first one replaced.

**What CI proves.** A lift on a day prescribing one lands on `lift.completed` (75–100) or
`lift.short` (40–74) with the ask's own duration as the reference; a lift on a day
prescribing none is left unscored with `fallback.recorded` named as what was refused; the
same lift under pre-MAX-132/146 bands is left unscored with `rest.ranAnyway` named; a
prescribed lift under a rubric with no `lift.*` rows is left unscored; a lift is not scored
until A22's entry exists and *is* scored through the existing
`completeIngestion(forWorkout:)` path once it does; a failed muscle-group read resolves as
"not yet" and recovers; a ride, a hike and a walk are never scored and never reach the
model; and the run path is untouched — the same easy Thursday under the shipped rubric,
with a lift prescribed alongside it, still scores 92 against `easy.onCap.lowDrift`. The
newly scored lift is also asserted **not** to be one of MAX-143's miscategorised scores,
since it was judged against the lift slot.

**What CI cannot prove.** That the calendar cell for an unscored lift now reads as a wait
rather than a settled absence, that the verdict header's three scoreless states still read
as three, and — the one check that actually demonstrates the gate — that authoring a
revision with a lift day, adopting the rubric, and setting a session's muscle groups
produces a score with a lifting rationale on the visit it is given. Added to
`docs/DEVICE-CHECKS.md` as 4.7a and 4.29–4.31.

**Reported, not done.** `WorkoutClassifier` still answers `.other` for every non-run, so a
scored lift stores `actualClassification == .other` while being judged by a band that names
`.lift`. Nothing is wrong today — the rubric reads the *discipline*, a fact, and never the
classification, a judgement — but a lift's verdict header will read "Other" as what
happened, and `WorkoutClassification.lift` remains a case nothing produces. That is a
classifier ticket, not this one's.

**`swift build`/`swift test` were not run** — no Swift toolchain in this container (R1). CI
is the compiler.

## MAX-159 — a settled miss outranks a pending score

MAX-135's reported defect, taken. `ScoreCalendarDayState` gains
`.missedWithUnjudgedSession(scheduledKind:recorded:)`; `ScoreCalendar.dayState`,
`ScoreCalendarGlyph`, `ScoreCalendarCopy` and `isDrawnHollowAtHeatmapDensity` in the core,
`ScoreCalendarPalette`/`ScoreCalendarFormatting` in the app. **No stored score,
classification or tally changed** — this is a display precedence and nothing else. D8 is
untouched, and `TalliesCalculator` was not opened.

### The decision

**A settled outcome on one obligation outranks a pending one on another.** The old rule
was that a recorded-but-unjudged workout outranked everything, which is right *within* one
obligation — a day holding a lift and an unscored run is about to become a band, so
"awaiting" is the true thing to say — and wrong across two, because the score that cell
waits for will never say anything about the other obligation's miss. A miss is a fact; a
missing score is not yet anything. It is §7.2's own rule (*"`.scored` no longer outranks a
different obligation's miss"*) with the tenses swapped in.

**It takes a state, not a reordering, and the state takes a shape.** Letting `.missed`
simply win would have swapped one half-truth for its mirror: an "×" on a day the athlete
trained. Both halves are true and neither implies the other, so the cell has to say both.
The fill is D9's red — the same token `.missed`, `.partiallyMet` and
`.scored(.ineffective, _)` already draw, so **1.00:1 against all three, computed in
`WCAGContrastTests` rather than asserted** — and the whole separation is the glyph:
`xmark.circle`, which is `.missed`'s own mark inside the enclosure this vocabulary already
uses for *the same thing, plus more* (`.long` takes `figure.run.circle`). Shape survives
greyscale, every kind of colour vision, Increase Contrast and Reduce Transparency alike.
`testNoTwoCalendarCellsAreDistinguishedByHueAlone` was **extended**, not duplicated, and
`testTheThreeRedCalendarStatesShareOneToken…` is now `…TheFourRed…`.

### Which historical cell shapes now render differently

The owner will see this on their own device. Exactly one shape moves:

- **A prescribed run day whose only recorded workout is a strength session, with the run
  unforgiven by the weekly budget.** Was: a neutral cell, glyph `figure.strengthtraining
  .traditional`, spoken *"Strength training, recorded. Not scored — the plan scores runs.
  Planned: easy run."* Now: D9's red, glyph `xmark.circle`, spoken *"missed easy run.
  Strength training recorded, not scored — the plan scores runs."* At year density it goes
  from a solid neutral mark to a hollow red one. **The tallies already counted that run as
  a decided, unmet obligation** — the cell was the half that disagreed, which is §7.3's
  drift with a colour attached.
- The two-obligation versions of the same shape (a skipped run beside an unjudged lift, or
  a skipped lift beside a run awaiting its score) move too, but cost nothing historically:
  every plan on disk rests its lift slot, so no such day exists yet.

**A ride on a missed-run day does *not* move**, and MAX-135's report named it as the case
that would. `Discipline` makes a ride `.run` **by slot** (A17: cycling is an `.other`
session in the run row, not a third discipline), so a ride recorded on a prescribed run day
leaves that obligation `.awaitingVerdict` — something *was* recorded against it — and never
`.missed`. There is no settled outcome on such a day for anything to outrank.
`testARideOnAPrescribedRunDayDoesNotMove` pins it.

**Nothing else moves**, and the fixtures say so rather than the prose:
`testTheWeekMovesInExactlyOnePlace` resolves the fixture week with D9 off and asserts all
seven cells; a run awaiting its score, a session on a day the plan asks nothing of, a plain
miss, a `.scored` day and a forgiven miss are each pinned separately.

### Rejected

- **A plain reordering** (`.missed` ahead of the recorded session) — the mirror-image
  half-truth, above.
- **Drawing the recorded activity's own figure on the red fill**, which was the cheaper
  option and reads well for a lift. It collapses the moment the recorded session is a
  *run*: an activity figure on this red is already `.scored(.ineffective, _)`'s cell, so
  "ran badly" and "skipped the ask, ran anyway" would become one drawing. The mark is the
  state's for that reason, which is also why `WCAGContrastTests` lists one representative
  rather than two.
- **A tenth fill token.** MAX-084 and MAX-087 spent the contrast budget; MAX-135 measured
  the reds at 1.00:1 deliberately, and this state joins them on the same terms.
- **Widening `.missed`'s payload** instead of adding a case. `.missed` means an empty day,
  and a reader of a state that sometimes carries a recorded session has to check which.
- **Reusing `.partiallyMet`**, with its met half made optional. Those are different facts —
  one half *counted*, here neither did — and an always-nil field is a representable state
  that cannot occur.
- **Moving the neighbouring case: a *scored* session on a day another obligation was
  missed.** Reported, not done — see below.

### Reported, not done

- **A scored session whose own slot the plan rested still outranks a settled miss on the
  other slot.** The real instance is a pre-MAX-111 lift carrying a running-rubric score
  (A21/MAX-143) on a day the run was skipped: that cell shows the stored band and says
  nothing about the miss, which is the same precedence question one tense further on. It
  was left alone deliberately — it would recolour the cells of *stored scores*, which is
  wider than this ticket's scope and cuts against MAX-143's decision that those scores keep
  being reported. `testAScoredSessionStillOutranksAMissedObligationOnTheSameDay` pins
  today's answer so the boundary is on the record.
- **A ride's run obligation is `.awaitingVerdict` forever.** Nothing will ever score a ride
  (MAX-111), so that obligation is permanently undecided and silently drops out of the
  effective ratio's denominator — the `.awaitingScore`/`.noVerdict` distinction the
  calendar makes and `ObligationOutcome` does not. It is a tallies question (out of scope
  here, and `Tallies/` was not touched), and it is what makes the ride case above genuinely
  unmoved rather than merely unexamined.
- **`ScoreCalendarCopy` and `ScoreCalendarFormatting.kindLabel` disagree on one word**:
  `.other` is "other" through `PlanCopy` and "session" in the app's own label. Predates this
  ticket (MAX-135 inherited it) and belongs to MAX-104's copy pass.

### What CI can and cannot prove

CI can prove: the core compiles, the app target compiles and links, the precedence resolves
as specified over every fixture above, the cell and the effective-obligations tile agree
about the same day, no two day-grid cells are left on hue alone, the four reds measure
1.00:1 and carry four distinct marks, and no future day reaches the red state.

CI cannot prove the half that matters here: whether a ringed "×" reads as *"missed it, but
trained"* rather than as a close button at ~42pt; whether a red cell over a day the athlete
did train feels honest or punitive; and whether the sentence is the right length to hear
cell after cell. **`swift build`/`swift test` were not run** — no Swift toolchain in this
container (R1). See the PR's device list.
## MAX-169 — a store that will not open is a designed state

The highest-consequence path in the app that nothing has ever executed.
`PersistenceComposition.modelContainer` opens the one SwiftData store; MAX-154 made its
failure *logged* rather than silent, but the failure itself was still not a state the app
had. `store` was nil, and each of the nine `LoadFailureSurface` cases independently said
its own content could not be loaded — five screens' worth of local problems, none of them
naming the single fact behind all five, and none of them mentioning the invisible half:
that ingestion had nowhere to write either.

### What it is now

**One state, named in the core.** `StoreAvailability` — `.open`, `.couldNotOpen(failure)`,
`.openedAfterTryingAgain` — with `FailureCopy.storeAvailability(_:)` supplying every word
and `StoreAvailabilityTests` holding both. The app layer's whole remaining job is to call
`MaximizeModelContainer.makeOnDisk()`, turn what came back into a `StoreOpenOutcome`, and
render the result.

**It replaces the app rather than sitting on top of it.** `MaximizeApp` switches between
`StoreUnavailableView` and `RootTabView`. That is the "say it once, in one place" half of
the ticket, and it also does the mechanical work that makes a retry honest: no screen's
model is constructed while the store is shut, so none of them captures the nil, and a
retry that succeeds is picked up by every screen built afterwards. `SettingsModel.shared`
is the one exception by construction — the app root builds it at launch — so it now
resolves `PersistenceComposition.store` at each use rather than in `init` (see R13).

**A failure is not an absence, one level up.** "No workouts yet", "your workouts could not
be loaded" and "Maximize could not open your history" are three different worlds, and
before this the third rendered as several simultaneous instances of the second — and, on
the workouts tab, as the *first*. `FailureCopyTests` now holds all three apart.

### The route out, and its honest limits

Investigated rather than assumed, since the ticket asked for the truth rather than a
button:

- **A retry is genuinely available for three of four classified reasons.** The strongest
  case is real, not theoretical: the store is `.completeUntilFirstUserAuthentication`, so a
  HealthKit background wake on a phone that rebooted overnight and has not been unlocked
  since cannot read it — and if iOS then foregrounds that same process, the athlete is
  looking at an app whose store failed an hour ago on a phone that is now unlocked. A
  second attempt clears it. Out of space is the other actionable one: the athlete can free
  space between the two presses.
- **The reason a retry cannot clear gets no button and says why.** A store this build
  cannot open is the same attempt against the same bytes. Offering a control there would
  be a second thing that does not work.
- **Nothing offers to delete, reset or rebuild the store** (A8 — it is the only copy), and
  no sentence suggests doing it by hand. `StoreNoticeAction` has two cases and a test
  asserts it, so a third has to be argued for rather than added.
- **A retry that succeeds does not restore everything, and the copy says so.** The
  ingestion pipeline is assembled once from `didFinishLaunchingWithOptions`, against
  whatever store existed then — none. Reads work from the moment it opens; new workouts
  are collected on the next launch, and none are lost while they wait, because with no
  store the sink pins the HealthKit anchor rather than acknowledging the batch (R9/R12).
  `.openedAfterTryingAgain` exists precisely so that is stated rather than discovered as a
  run that never appeared.
- **No diagnostic reaches the screen.** The domain, the code and now the classified reason
  are `.public` in the log (a sysdiagnose is where they are read); the `Error` itself stays
  `.private`, because a Core Data error's `userInfo` can carry stored row values. The
  classification is derived in the core from two scalars — a domain string and an integer —
  which cannot carry a workout.

### The migration conclusion: no stage, and the argument for it

`MiscategorisedScoreLabelRecord` (MAX-143) and `MuscleGroupEntryRecord` (A22) are the
first shape change to land on a schema that may already have a store behind it, and
`MaximizeMigrationPlan.stages` is empty. **It stays empty.** The full argument is written
where the next person will look for it — `MaximizeMigrationPlan`'s doc comment — and in
short:

1. Both are *new entities*, which Core Data's lightweight migration infers; no row of any
   existing model is read, rewritten or re-typed. The two harder cases (a new nullable
   column, a new defaulted column) were already taken by `DerivedMetricsRecord` and
   `ChatThreadRecord`, and neither took a stage either.
2. A stage could not carry it: `MigrationStage` maps between two `VersionedSchema`s with
   different identifiers, so writing one means a V2 holding a second copy of twelve model
   classes, with a `.lightweight` stage asking SwiftData for the inference it already does.
3. A `.custom` stage has no work to do — the new tables start empty and every property is
   non-optional with a default, so there is no value to invent for an old row.
4. Adding a record type is the one shape change that stays legal after a CloudKit schema
   is promoted, so this does not expire when A8 is lifted.

**This is an argument, not an observation.** No test and no device in this project has
opened a pre-existing store with the new shape. If it is wrong, Core Data says so with
`NSPersistentStoreIncompatibleVersionHashError` / `NSMigrationError` /
`NSInferredMappingModelError`, which this ticket classifies as
`.shapeThisBuildCannotOpen` — the state that offers no retry, says the history is still on
the device, and offers nothing that would remove it. That is the designed landing place
for the argument being wrong.

**One cost recorded, not paid.** Several genuinely different on-disk shapes now all report
themselves as schema version 1.0.0 (pre-MAX-046, pre-MAX-093, pre-MAX-143, and this one).
That is free while every step is additive and inferable, but a future `.custom` stage keyed
`1.0.0 → 2.0.0` cannot tell which of those it has been handed. The first change that is not
inferable is therefore also the last moment at which versioning is cheap.

### What CI can and cannot prove

CI can prove: `MaximizeCore` compiles and the suite passes, including
`StoreAvailabilityTests` (classification of nine documented Cocoa error codes, the retry
being offered exactly where it could work, the two-case action enum, every transition of
the state machine) and the `FailureCopy` whole-set rules extended over the new copy; and
that the app target still compiles and links.

CI cannot prove **the entire subject of this ticket**. It has never opened a store, never
failed to open one, and never drawn a pixel. Specifically unverified: that a real store
failure produces the error codes classified here; that the retry re-opens anything; that
the app's screens actually come back after a successful retry; that the notice reads well
at any Dynamic Type size; and that the additive schema change is in fact inferable on a
store written by a previous build. See the PR's **Needs device verification** section — that
check is the point of the ticket, not a footnote to it.

**`swift build`/`swift test` were not run** — no Swift toolchain in this container (R1).

---

## MAX-175 — the app does not invent

Two rules worth taking came out of the competitive read (MAX-174): *no night of data means
no score*, and *if you have never logged strength work, it will say so rather than invent a
per-muscle story*. This app mostly behaves like both already and had stated neither, which
is the whole problem — nothing stops the next ticket from violating a rule nobody wrote
down.

### The premise this was dispatched on was wrong, and the correction is the interesting part

The brief said: *"`ChatInstruction.swift` contains no honest-refusal constraint at all."*
That sentence is true of the file and false about the app, and it came from grepping one
file. **`ChatInstruction` holds no task text by design** — its `task` has no default, and
its own doc comment says why: what to ask Claude to do in a chat turn is the chat feature's
product decision, not the transport's. Looking for the rule there is looking in the one
file deliberately built not to hold it.

The rule was already in the three files that own prompt words, and it is good:

- `ChatModel.workoutTask` — *"Never invent a number, split, or detail the fact sheet does
  not state; when something was not measured, or the fact sheet says it does not apply, say
  so rather than guessing."*
- `ChatModel.trainingTask` — the same, plus name-the-window, never-re-score, no medical
  advice.
- `PlanProposalInstruction.taskDescription` — *"Do not invent facts about the athlete.
  Where the conversation is silent…"*

MAX-174 checked the claim and returned it corrected before this ticket built on it; the
coordinator then rescoped mid-flight. **No second constraint was added to any chat prompt.**
Adding one would have duplicated a rule in the place that already owns it — the opposite of
what this ticket is for.

### What was actually missing, and what changed

**1. No test held the prompts to the rule as a set.** Four independent good sentences are
not an invariant; they are four sentences, and a reword that dropped the clause from any
one of them changed nothing CI could see. `HonestRefusalAcrossPromptsTests` now holds all
four together, each pinned by the phrase *that* prompt uses — the words stay with their
owners, because a fact sheet, a summary, a conversation and a record are four different
things to be honest about, and collapsing them into one shared literal would have replaced
four accurate sentences with one that is slightly wrong in three places.

**2. The scorer's prompt genuinely lacked the rule** — checked directly rather than taken
on faith, since the brief's other claim had not survived that treatment.
`WorkoutScorer.absenceRule` is the one line of prompt text this ticket adds, shared by both
discipline branches:

> The record you are given states its own absences. Where it says a figure was not
> recorded, does not apply, or was not computed, do not supply one and do not reason as
> though you had it: score and justify from what is stated.

It is a prohibition rather than a refusal, and that is deliberate: **this call has no
refusal available to it.** The reply is a JSON object carrying a score inside a range the
rubric already fixed, so "I do not have that" would be a failure, not a decline. The
concrete hazard is the *rationale* — free prose that `RationaleContract` asks to cite the
numbers that decided the score, stored immutably under D8 and shown in the verdict header.
A run whose splits were never recorded getting a header that quotes a second-half split is
the per-muscle story in one line, and unlike a chat turn, nobody can ask it to take that
back. This also closes MAX-174's G3, which asked that the scorer's exemption be a recorded
decision rather than an omission nobody had noticed; the answer turned out to be that it
should not be exempt.

**3. "No score" is now a rule with a test.** `NoJudgementWithoutDataTests` states it and
pins it at six seams: the rubric refusing rather than defaulting when no plan governed the
day or when the deciding metric was never measured; a model reply outside the permitted
range rejected rather than clamped; an empty rationale refused rather than backfilled; an
unscored window reporting no average rather than `0.0`; and the strictest form of it in
the codebase — **an unscored run has no conversation to open at all**, because a thread
would need a classification and the only classification that exists is the one the scorer
recorded.

### The invariant, stated

> **Where the data required for a judgement is absent, the app produces no judgement
> rather than a degraded one.** An absence is named — and where it matters, which *kind*
> of absence it is — rather than filled, at every boundary: the stored record, the fact
> sheet, the prompt, the tallies, the calendar and the screen.

It is recorded in the decision log rather than as a PRD amendment, because it amends
nothing: it is how PRD §10 already behaves, and A26–A28 are proposed by MAX-174 and in
review, so taking a number here would collide with a document already being read. A25 —
felt-ratings before scores — is the amendment this ticket does write, and it is the
rejected design rather than the invariant.

**No behaviour changed for it.** MAX-130 stopped fabricating a cadence for a lift; MAX-136
omits the figures a lift was never measured by and says once why; MAX-168's ingestion gates
fail closed; `.awaitingScore` and `.noVerdict` are designed states; `Tallies.averageScore`
refuses to report `0.0` for "nothing has been scored". Six correct decisions taken six
times were already there. What did not exist was the seventh author inheriting them, and
that is what the statement and the tests buy.

### A25 — a felt-rating is collected before the score is revealed, or not at all

The rejected design, recorded: the athlete sees a score, then rates how the day felt, and
the model re-weights against that rating. The rating is taken after the anchor, so a low
score primes a worse report and the model learns that the weighting which produced it was
correct. The label is downstream of the output it grades, so no observation can contradict
it. D8 already has the honest ordering — auto-score fixed first, correction stored
additively beside it, divergence as the measurement — which is why the amendment is a
clarification rather than a new principle. Nothing in the app collects a felt-rating today;
the rule exists so that whoever adds one inherits it.

### Reported and deliberately not taken — and it is worse than filed

MAX-174's **G2** (filed as **MAX-181**): `TrainingFactSheet`'s plan block renders
`entry.session` and leaves `entry.liftSession` unrendered, so a training thread's model is
shown the run prescription for each weekday and silently not the lift one. The renderer's
own comment claims the lift slot "arrives for free the moment `WeeklyTemplate` grows one" —
`WeeklyTemplate` grew one in MAX-109, and it did not.

**The severity is higher than G2 records, and this ticket found the reason.**
`PlanProposalInstruction.taskDescription` — the prompt that drafts a *new plan version* —
instructs the model: *"restate each weekday's lift ask from the fact sheet exactly as it
stands unless the conversation asks you to change it."* Plan drafting from a training
thread is handed that same `TrainingFactSheet`. So the model is told to carry over lift
asks it was never shown, and can only comply by inventing them or by proposing rest for
every lift day. The second is the quiet one: an accepted proposal is a new plan version, so
a drafting conversation could silently delete the athlete's entire lift schedule, and the
authoring screen would show it as a change they did not ask for only if they read seven
weekdays carefully.

Not taken here for four reasons, and this is a judgement call the overseer can overrule:
this ticket's own brief forbids changing what context is assembled; the fix needs a
rendering decision about a two-slot template line that MAX-181's author should make with
§10.2's economy rules in view; MAX-174 sequenced MAX-181 *after* MAX-175 precisely so it
lands against the stated invariant; and a prompt-contents change with pinned byte-level
tests is the worst thing to write in a container with no Swift toolchain. **Recommend
MAX-181 be re-tiered and taken next**, with the plan-drafting consequence in its brief.

### What CI can and cannot prove

CI can prove: the package compiles; `HonestRefusalAcrossPromptsTests`,
`NoJudgementWithoutDataTests` and the extended `ScorerTaskTextTests` pass; the scorer's task
text is byte-identical to its pinned literal in both discipline branches; and that no prose
prompt half carries a digit.

CI cannot prove the thing that actually matters: **that Claude obeys the sentence.** No
test in this repo can. What the tests buy is that the sentence is present in every prompt
that should carry it, and that the app never asks for a judgement it has no data for — the
half that is ours rather than the model's.

**`swift build`/`swift test` were not run** — no Swift toolchain in this container (R1).

---

## MAX-176 — per-workout strain, and what its number means

Everything the app measured before this ticket answers one question: *did you execute the
ask*. Time above the cap, drift, cadence against the band, and the score that reads them
are all comparisons against a prescription. None of them answers *what did it take out of
you*, and the two come apart constantly — a disciplined easy hour and a disciplined easy
three hours score identically and cost wildly different amounts. Strain is the second
question, stored as its own figure, and it is deliberately not a verdict: no rubric band
references it, nothing compares it to a prescription, and a big strain is neither good nor
bad on its own.

**The weighting: Edwards' summated heart-rate zone score.** Each zone counts for its own
ordinal — zone 1 once, zone 5 five times — multiplied by the time spent there. Three
reasons it is that and not something invented here. It reads the distribution the record
*already carries*: `zoneSplits` is cut at every boundary the piecewise-linear curve
crosses, so `Σ weight(z)·seconds(z)` **is** `∫ weight(HR(t)) dt` exactly, not an
approximation, and the tile and the zone chart therefore cannot disagree about the same run
(D2). It introduces no second set of thresholds — the one modelling choice is where the
zones sit, and that is already made once, in `HeartRateZoneModel`, anchored to the plan's
cap (D1), with the plan version stored beside the figure. And linear weights are less blunt
than they look, because the bands are not equally wide: cap-anchored they are ≤0.90×,
≤1.00×, ≤1.08×, ≤1.16× of the cap and then open, so the response to *heart rate* is already
convex above the cap.

**The unit, which is now permanent in stored data: points, where one point is one minute in
zone 1** — zone-weighted minutes — **unbounded above.** There is no ceiling to be near. Two
anchors: an hour held just under the cap is exactly **120 points**; an hour climbing 120 →
180 bpm under a 150 bpm cap is exactly **159**. A bigger number means longer, or harder, or
both, and it deliberately cannot tell those apart — a hard half-hour and an easy hour both
come to 120. `zoneSplits` is what says which it was, and any surface showing strain should
be able to reach it.

**What was rejected, and why.** A bounded 0–21 scale (Whoop's, and Helix's copy of it)
needs a personal ceiling to anchor the top — a rolling maximum, or heart-rate reserve from
resting and maximum HR. This app ingests no daily health data (§8.1's decline, proposed
A27) and holds neither the athlete's age nor their resting HR, so the ceiling would be an
arbitrary constant made permanently invisible inside every stored number. Banister's TRIMP
falls to the same missing inputs plus a sex-specific constant. A continuous weighting of
`HR / cap` was rejected as a curve this repository would be inventing, and as a *second*
reading of the same curve that could drift from the zone splits stored beside it.

**A lift's strain is heart-rate only, and the type says so.** HealthKit carries no load for
a strength workout — no sets, no reps, no weight (A20) — so a lifting session's strain is
the cardiovascular cost of the hour and nothing else. Two sessions with the same curve have
the same strain whatever was on the bar, and the zone boundaries it is cut against are
anchored to the plan's *run* cap (tracker gap **P2**, already true of `zoneSplits` and made
no worse by totalling it). `WorkoutStrain`'s own doc comment states this so MAX-179 and
anything after it cannot read the figure as more than it is.

**Absence is first-class.** A workout with no heart-rate curve has **no strain** — nil,
never zero, because a zero reads as "this session cost nothing" and would be summed into
MAX-178's rolling load as a real day of training (A18, MAX-175's invariant). The case is
added to `NoJudgementWithoutDataTests` rather than to a parallel file, and `DerivedMetrics`
refuses to be constructed with a strain and no heart rate at all. A curve that exists but
covers no span — a single sample — gets `0`, which is the same reading
`timeAboveCapSeconds` already takes of that case: there is a measurement, and it truthfully
contains nothing.

**What a person will see for their history.** Nothing changes and nothing is rescored (D8).
`strainPoints` is a nullable column added to `DerivedMetricsRecord`; SwiftData's lightweight
migration gives every existing row NULL, which reads back as no strain and says so. A past
workout gains a strain only if something puts it back through the existing metrics path —
this ticket adds no backfill and no sweep. So on the device today, strain appears on
workouts ingested after this build and on nothing before it, until a backfill ticket decides
otherwise. **`MaximizeSchemaV1` is not promoted**, per MAX-169's conclusion: an added
nullable attribute is Core Data's canonical lightweight-migration case and needs no version
bump while no schema has been promoted to CloudKit production.

**What MAX-177 and MAX-178 should read.** Both read `DerivedMetrics.strain`, a
`WorkoutStrain?`, whose one figure is `.points` in zone-weighted minutes. **MAX-177**
(built — see the MAX-177 section below): the tile and the fact-sheet line render
`strain?.points`; nil is the absence state and must say which absence it is — the workout
has no heart-rate curve — rather than showing a dash or a zero, and the fact-sheet half
should state the unit, because a bare number with no unit is exactly what A18 warns a
model will reason confidently from. **MAX-178**: sum
`strain?.points` over the window, skipping nil rather than treating it as zero, and say in
the caption how many sessions in the window carried no strain — a 7-day sum missing two
strapless runs is not the same fact as a 7-day sum of everything that happened. The column
`StoredDerivedMetrics.strainPoints` is a real nullable `Double` column, not a JSON blob,
precisely so that summing a month of it does not oblige a decode per workout.

### Two limits written into the type rather than left to be discovered

Both came out of the code review and neither is a defect in this ticket; they are
properties of reading a heart-rate curve, and the fix for each is worse than the property.

- **Strain counts paused time.** Within the span the curve covers, a stop at a level
  crossing is interpolated across and weighted like any other stretch, so forty minutes of
  running either side of a twenty-minute stop costs about what a clean easy hour costs.
  Every other seconds-valued figure in the record already reads the same way —
  `timeAboveCapSeconds` and `zoneSplits` are cut over exactly this span — and correcting
  for it would mean scaling by `durationSeconds / coveredSeconds`, which invents a
  distribution the curve does not contain and breaks the exact identity with `zoneSplits`.
  If it distorts real numbers, the fix is to record pauses as gaps at ingestion, which is
  the fix `HeartRateCurve` already names for dropouts.
- **A zero-span curve reads as recorded strain and unrecorded zone splits.** A
  single-sample series gives strain `0` and empty splits, so `isRecorded(.strain)` is true
  while `isRecorded(.zoneSplits)` is false. One fact, not two in tension — "measured, and
  containing nothing" — pinned by a test and stated in `WorkoutStrain` so **MAX-177 does
  not draw them as a contradiction**. **Confirmed: it does not** — see that ticket's own
  section for the test and the wording.

Also raised and deliberately not taken (at the time): nothing at `WorkoutFactSheet`'s call
site recorded that `strain` was intentionally absent from the prompt. That file was
MAX-177's, running in parallel, and a comment there would have been a merge conflict
bought for a note MAX-177 would delete the moment it added the line — which is exactly
what happened; no such placeholder comment existed for it to remove.

### What CI can and cannot prove

CI can prove: the package compiles; the strain over four hand-computed curves is the value
claimed, by arithmetic written out in the test rather than captured from the
implementation; a workout with no curve has no strain and one with a zero-span curve has
zero; ordering by duration and by intensity; that a pre-change `DerivedMetrics` payload and
a pre-change stored row both decode unchanged with no strain, and that a record with no
strain re-encodes without the key.

CI cannot prove anything about how the number reads to a person — no tile existed at the
time this ticket landed (MAX-177 added it after), and no unit was drawn on screen by this
ticket. It also cannot prove the migration: CI never runs SwiftData (tracker **R2**), so
"an existing row gains a NULL column" is verified only as the pure mapping in
`StoredDerivedMetrics`, and the SwiftData half is a two-line field copy in `MaximizeSchema`
with no branches in it.

**Needs device verification:** install over an existing build with workouts already stored,
confirm the store still opens (the migration is inferred, and an inferred migration that
fails presents as an unopenable store — MAX-169's screen), and confirm an older workout's
detail screen is unchanged.

**`swift build`/`swift test` were not run** — no Swift toolchain in this container (R1).

---

## MAX-177 — strain on the detail view and in the prompt

Two surfaces, both reading `DerivedMetrics.strain` directly (D2) and never recomputing it.

**The tile.** `SummaryTileData.strain` is `Tile?`, built the same way `averageHeartRate`
and `maximumHeartRate` already are: read straight off `metrics?.strain`, unguarded by
discipline, because `DerivedMetricKind.strain` is `.anyDiscipline` — a lift's strain is not
gated to nil the way `distance`, `heartRateDrift` and `gradeAdjustedPace` are. It is
appended to `tiles` *after* FR-1.5's own six rather than interleaved into their stated
order, since strain is a MAX-176 figure that postdates the spec and the six are a closed
list this type does not reorder. The caption is `"strain pts"` rather than a bare
`"strain"` — deliberately, so the tile cannot be misread as a bounded 0–21-style rating the
way Whoop's figure is; `WorkoutStrain`'s own doc comment names that as the exact
misreading this app rejected the shape of. `SummaryTilesView` needed no code change at
all: it lays out `data.tiles` generically and the new tile reuses `tileView(_:)` exactly,
so there is no second tile convention to review. Only its doc comment was updated to name
the new tile and its position.

**The fact-sheet line.** One new line in `WorkoutFactSheet.factSheet()`'s `## Measured`
section, both disciplines, right after `Time in zones`. It states the unit
("zone-weighted minutes"), that the figure is unbounded and not a 0–100 score, that a
bigger number can mean longer, harder, or both without saying which, and that it is
heart-rate only — "on a lift or otherwise", so the caveat is not read as implying a run's
strain *does* carry load information by omission.

**Two absences, worded apart — the same distinction `driftLine` already makes, and a case
this ticket found rather than assumed.** `metrics.strain == nil` is not one fact:

- **No heart-rate data at all** (`hasHeartRateData == false`) — the same "not
  applicable" wording `timeAboveCapLine`/`driftLine`/`zoneLine` already use.
- **Heart-rate data present, strain not yet computed.** MAX-176 rescored nothing already
  stored (D8): a workout ingested before it shipped has average/max heart rate on the
  sheet two lines above and no strain, which is a real, common, non-contradictory state —
  not the same fact as "no heart-rate series exists." The line reads "not yet computed for
  this workout" rather than reusing the no-data wording, or the fact sheet would tell
  Claude a workout has no heart-rate series when it plainly does.

**The zero-span case is handled without contradicting the zone-splits line above it.**
`WorkoutStrain`'s doc comment names a curve that exists but covers no time span (a single
sample) as a *recorded* strain of `0` alongside *empty* zone splits — one fact ("measured,
and containing nothing"), not two in tension. The strain line is guarded on
`metrics.strain` directly, never on `zoneSplits` being non-empty, which is what keeps a
zero-span workout from reading as "0 zone-weighted minutes" beside "not applicable — no
heart-rate data" on the line above as if the two disagreed; the zero branch spells out
which of the two facts it is rather than leaving that inference to the reader.

**Not touched: `TrainingFactSheet`.** The roll-up is a different renderer (§3.3 already
excludes several per-workout figures from it) and was not named in this ticket's file
list; whether the training roll-up should carry a strain figure of its own — a sum, an
average, something else — is a separate product question this ticket did not decide.

### What CI can and cannot prove

CI can prove: the package compiles; `SummaryTileData.strain` reads `metrics.strain`
verbatim and is never gated by discipline, unlike the three run-only tiles beside it; a
lift's stale pre-MAX-130 metrics do not resurrect a discipline-gated tile the way they do
for the guarded three (strain was never one of them); the fact-sheet line is pinned as a
literal for both the present and the two-absence cases; the zero-span case renders `0`
rather than either absence wording, and does not print `"Strain: not applicable"` beside
it; and a lift's line carries the same load disclaimer a run's does, asserted directly
against a lift-discipline context rather than inferred from the wording being unconditional
in the source.

CI cannot prove how the tile reads at largest Dynamic Type, in either colour scheme, or
with the strain absence state actually on screen next to the other six tiles — no device
or simulator runs HealthKit or SwiftUI here (tracker **R1**/**R2**).

**Needs device verification:** the tile — largest Dynamic Type, light and dark, with a
strain figure present and with the tile correctly absent (a workout whose curve predates
MAX-176, or has none at all).

**`swift build`/`swift test` were not run** — no Swift toolchain in this container (R1).

---

## MAX-179 — per-muscle fatigue, and the argument it is written against

A decay model over the `MuscleGroupEntry` records A22 already collects — the cheapest of
MAX-174's four features precisely because its input was already paid for. New files only:
`Domain/MuscleFatigue.swift` and `Metrics/MuscleFatigueCalculator.swift`, plus tests.

### The shape

For each session the athlete said worked a group:

```text
weight   = min(durationSeconds / 2700, 1)      // 45 minutes counts as a full session
decay    = pow(0.5, elapsedSeconds / 172800)   // 48-hour half-life, measured from the end
fraction = weight * decay                      // fresh once decay itself falls below 0.01
```

Exactly one session sets a group's figure — nothing is summed — and **it is the session
that reads highest, not simply the latest.** This is the one place the implementation
departs from the brief's wording ("the last session that worked it"), and it is
deliberate: taken literally, that rule makes the app punish honesty. A 90-minute leg day
on Monday evening reads about 0.82 on Tuesday morning; logging a 10-minute mobility
session that also touched legs on Tuesday morning drops the same athlete to about 0.22 —
*more* logged data, *less* reported fatigue, from work that was added rather than
removed. Taking the highest candidate still uses exactly one session, still sums nothing,
and is monotone: logging can never lower a figure. It reduces to "the last session"
whenever sessions are of comparable length, which is the case the brief describes.
`MuscleFatigue` therefore carries two instants — `sessionEndedAt` (where the figure came
from) and `mostRecentlyWorkedAt` (what a screen means by "last worked").

**The 48-hour half-life is chosen against the interval a split repeats a group at, not
against a physiological measurement** — a group trained Monday reads half-fatigued on
Wednesday, the day a plan would next ask for it, and about a twelfth as fatigued the
following Monday. 72 hours is equally defensible and is not more correct; the model is
coarse enough that the gap between the two is smaller than the gap between a hard session
and a token one, which neither can see at all.

The 1% floor is applied to **the decay factor, not the finished figure**, which puts the
`.fresh` boundary at about 13 days and 7 hours *whatever the session's length*. Applying
it to the figure would call a mis-started fifteen-second workout `.fresh` a minute after
it ended — putting "enough time has passed" on screen about something that just happened,
because the figure was small rather than old.

**The constants are code, not plan data, and that is a decision rather than an oversight.**
D1 protects the reproducibility of *stored scores*, and this model produces none — nothing
scores, gates or judges from it. The type states the line in advance: if a fatigue figure
ever reaches the scorer, its constants become plan data in the same change.

### What it cannot know, and why that is the ticket

MAX-174 predicted this is the feature most likely to attract a *"just add a weight field"*
follow-up, so the type meets that argument rather than leaving it to be re-derived. There
are no sets, reps, load or exercises here because **the record does not contain them** —
A20's wall — and the doc comment carries A20's own cost sentence rather than paraphrasing
it: forty-five minutes of moving light weights reads exactly like forty-five real minutes.
The governing amendment is stated explicitly: A22 spent the manual-entry non-goal narrowly
and once (*which* muscles a session worked, on one screen, on one kind of workout, and "a
later ticket does not inherit this amendment's permission"); **A20 governs *how much*, and
requires an amendment superseding PRD §3 — never a field arriving inside a lifting
ticket.** The figure is also documented as coarse, in the type, because a number with
three decimal places invites being read as though it had three decimal places.

### Two absences, not one

MAX-175's invariant, applied at a new seam. A group **no session ever named** has no figure
at all: a `0.0` would say *fully recovered*, which is a claim the record cannot support —
the athlete may have trained legs daily and told the app nothing (A22: "I have not told you
yet" is not "I trained nothing"). A group **worked a fortnight ago** is `.fresh` and still
carries its figure, because there recovery is something the app was told enough to judge.
Three reading cases, three sentences in `MuscleFatigueCopy`, and both new cases live in
`NoJudgementWithoutDataTests` rather than a parallel file.

### What was rejected

- **Accumulating sessions.** Three leg days in four read as one of them. A sum's scale is
  anchored to nothing measured, which turns a coarse signal into an arbitrary one.
- **Reading the brief's "last session" literally** — see above. Kept the one-session rule,
  dropped the non-monotonicity.
- **A linear ramp.** It needs an arbitrary zero crossing and then asserts a hard edge at it
  — *fatigued Thursday, recovered Friday* — a sharper claim than "halves every couple of
  days" and no better supported.
- **Scaling duration without a ceiling**, and **normalising to the athlete's longest
  session**. The first reads a three-hour session as 4× a 45-minute one on a scale nothing
  justifies; the second lets one outlier rescale every figure in the app.
- **Clamping the tail to zero at the floor.** The floor is a presentation boundary; the
  figure underneath it still orders, so a fortnight ago and a year ago do not collapse.
- **Admitting a zero-duration session as a zero weight.** Refused at
  `MuscleFatigueSession.init` for the same reason a never-logged group has no figure. The
  builder over stored workouts *skips* such a record rather than throwing, so one malformed
  workout cannot deny the athlete the other five groups.

### The seam a strain weighting swaps into — and what MAX-176 landing changes

Weighting goes through `MuscleFatigueModel.Weighting`, one case today (`.duration`).
MAX-179 shipped duration-weighted deliberately, so it did not depend on work running
beside it, and touched no file MAX-176 owns.

**MAX-176 has since merged**, so the follow-up is now writable: `DerivedMetrics.strain` is
a nullable `WorkoutStrain` in Edwards' zone-weighted minutes, computed once at ingestion.
Adopting it is three edits and one decision — `MuscleFatigueSession` gains an optional
`strainPoints` read straight off the stored record (D2), a `.strain` case joins the enum,
`weight(for:model:)` gains a branch, and **`WorkoutStrain.points` is unbounded above while
a weight here is `0...1`**, so a strain weighting needs its own full-session reference (the
counterpart of `fullSessionSeconds`) and picking that number is a product judgement rather
than a refactor. It is a ticket, not a cleanup.

**`.duration` does not become dead code.** A lift whose strap dropped has no strain (A18,
and `DerivedMetrics` enforces it), and MAX-175 forbids judging such a session on a
fabricated one — so duration stays as the honest fallback and the choice stays the
caller's.

### What MAX-180 should read

- `MuscleFatigueMap.ordered` — all six groups in canonical order, **total by construction**:
  a group with no session is present as `.neverLogged`, never missing, so a region cannot be
  silently dropped by a lookup that returned nil.
- `MuscleFatigueMap.hasNoLoggedSessions` — the map's own absence state. One sentence, not
  six regions drawn at zero.
- `MuscleFatigueCopy.modelCaption` — the honest caption, written and pinned by a test.
  `MuscleFatigueCopy.detail(for:)` gives the per-group sentence, and the never-logged and
  fresh wordings are deliberately different.
- `MuscleFatigue.fraction` for the band; `sessionWeight`, `elapsedSeconds`,
  `sessionEndedAt` and `mostRecentlyWorkedAt` for the detail a dense screen wants. There
  is deliberately **no `elapsedDays`**: "3 days ago" is a calendar question needing the
  athlete's time zone, so the label resolves both instants through `CalendarDay` and calls
  `days(until:)`, as `ChatThreadListPresentation` already does.
- **The three reading cases must stay three on screen**, and fatigue bands need a non-hue
  channel that extends the existing score-band accessibility test rather than a parallel
  one.

### What CI can and cannot prove

CI can prove the package compiles and that the curve is the one documented: every expected
figure in `MuscleFatigueTests` is hand-computed from the half-life, so each elapsed time is
a whole or half number of half-lives and each expectation is a written-out power of two —
including the floor asserted from both sides (13 days is fatigue at 2^-6.5, 14 days is fresh
at 2^-7) and from both session lengths. A test that asserted whatever `compute` returned
would pass against the wrong curve. Monotonicity has its own case: logging the mobility
session must leave the figure exactly where the leg day put it.

CI cannot prove the half-life is the right one. That is a product judgement no test reaches,
and its first honest check is an athlete reading a map after a real training week — which
needed MAX-180, drawn below. That first real-week check itself still has not happened;
MAX-180 only made it possible.

**`swift build`/`swift test` were not run** — no Swift toolchain in this container (R1).

---

## MAX-180 — the muscle map, drawn

`Sources/MaximizeCore/Accessibility/MuscleFatigueMark.swift` (new),
`App/Workouts/MuscleMapView.swift` (new), `App/Workouts/WorkoutDetailModel.swift`,
`App/Workouts/WorkoutDetailView.swift`, `App/DesignSystem/Layout.swift`, plus tests in
`Tests/MaximizeCoreTests/MuscleFatigueTests.swift` and
`Tests/MaximizeCoreTests/WCAGContrastTests.swift`.

### Five bands, from MAX-179's three reading cases

`MuscleFatigueReading` stays three cases; `MuscleFatigueBand.of(_:)` bands it into five for
drawing: `.notLogged` (`.neverLogged`, unchanged), `.fresh` (unchanged), and `.fatigued`'s
continuous fraction split into equal thirds — `.light`/`.moderate`/`.high`. Equal thirds
rather than a named physiological threshold, because `MuscleFatigueModel`'s own doc comment
already says this figure "has roughly one bit of real information"; three even tiers claim
no more precision than that. `MuscleFatigueMark.mark(for:)` is the one place a reading
becomes a band, a label, and a non-hue mark — the view never compares a fraction to a
threshold of its own.

### The non-hue channel: fill fraction, on one neutral ink

Every band draws in the same two tokens regardless of level —
`Color.chartSeriesPrimary` filled bottom-up over `Color.surfaceInset`, `Color.surfaceBorder`
for the outline. **No new saturated hue was added.** FR-4.3 reserves the three score-band
colours for the calendar and verdict header, and the accent's own documented meaning
("on-plan / effective") is not what a fatigued muscle group is — so rather than picking a
fourth saturated colour and re-litigating what it means, the level is carried entirely by
how much of a region's own shape is filled, plus whether its outline is solid or dashed
(`.notLogged` only) plus a glyph (`.notLogged` only, so an empty *known* group cannot be
misread as an empty *unknown* one). `WCAGContrastTests` holds `.light`/`.moderate`/`.high`
at the literal same ink — 1.0:1, no contrast at all — and still requires every band to read
apart on the geometric channel alone. Fill fraction and dash style are geometry, not opacity
or lightness, so Reduce Transparency and Increase Contrast have nothing to weaken here
(MAX-070): there is no translucency in the view to degrade in the first place.

### Extended, not duplicated

`WCAGContrastTests.testNoTwoCalendarCellsAreDistinguishedByHueAlone` gained a third
representation (`muscleMapCells()`) alongside the day grid (MAX-084) and the year heatmap
(MAX-087), the same way MAX-087 added the second one to the same test rather than writing
`ScoreBandHeatmapMarkTests` as its own suite. A sibling `testEveryFatigueBandCarriesItsOwnMark`
sits next to `testEveryScoreBandCarriesItsOwnMark`, in the same class. No new test file
duplicates this invariant. Ordinary unit coverage of the pure banding/label/fraction mapping
(`MuscleFatigueMarkTests`) was appended to the existing `MuscleFatigueTests.swift`, matching
how `ScoreBandMarkTests`/`ScoreBandHeatmapMarkTests` already sit inside `ScoreBandTests.swift`
rather than in files of their own.

### The absence MAX-179 was explicit about

A group `.neverLogged` draws dashed, unfilled, and glyphed — never the fill colour at zero,
which would silently read as "fully recovered." `MuscleMapView.hasNoLoggedSessions` is the
map's *own* absence, drawn as MAX-179's `MuscleFatigueCopy.noSessionsHeadline`/`.noSessionsDetail`
sentence rather than six regions all saying the same "not logged" thing.

### Where it hangs

`WorkoutDetailView` composes `MuscleMapView` unconditionally, directly under
`MuscleGroupEntryView`, on every discipline's screen — unlike the run-only sections (MAX-139),
it is not gated by `SummaryTileData.showsRunOnlySections`, because the map is the athlete's
whole-body state as of *now*, not a fact about the workout being viewed.
`WorkoutDetailModel.muscleFatigueMap(...)` fetches the trailing 21 days of workouts and their
muscle-group logs (no batch API exists on `MuscleGroupEntryRepository`, so this is one read
per candidate workout, the same cost the rest of that method already pays for HR series and
routes) and hands them to `MuscleFatigueCalculator.compute`.

### What CI can and cannot prove

CI can prove the package compiles, that `MuscleFatigueBand.of(_:)` bands the thirds where its
own doc comment says it does (including both boundaries, from both sides), and that no two of
the five marks — asserted against `MuscleFatigueMark`'s actual output, not against a
restatement of its thresholds — share a non-hue signature in either `MuscleFatigueMarkTests`
or the widened `WCAGContrastTests`.

CI **cannot** prove any of the following, all of which needs a device (§9: "the whole thing"):
that the schematic body layout reads as a figure rather than as six unrelated tiles; that the
fill-fraction channel is legible at the map's actual on-screen size; that the middle row's
switch to a vertical stack at accessibility Dynamic Type sizes actually prevents the overflow
it is written to prevent, rather than merely compiling; that Reduce Transparency and Increase
Contrast leave the map visually unchanged (expected, since nothing here is translucent, but
unverified); and that the caption reads as honest rather than as hedging. The App target was
not built — no Xcode toolchain in this container, and `App/` is outside the SwiftPM package
`swift test` covers (R1); the CI job that does build it (`ios-app`, an unsigned Simulator
build via `xcodegen`) runs only in GitHub Actions, not here.

**`swift build`/`swift test` were not run for `MaximizeCore` either** — no Swift toolchain in
this container (R1, same as MAX-179 and every ticket before it).

---

## MAX-181 — the fact sheet renders the lift slot

MAX-174 §5.3's G2: `TrainingFactSheet`'s plan block iterated `plan.weeklyTemplate.entries`
and rendered only `entry.session`, the run slot. `entry.liftSession` — the lift ask
`WeeklyTemplate` has carried since MAX-129 — sat unrendered. A training thread's model was
told the week's run prescription and silently not its lift one: a live instance of the
exact failure MAX-175's absence rule forbids, landing against that rule rather than beside
it, as MAX-174 sequenced it to.

### What changed

`Context/TrainingFactSheet.swift`'s weekly-template loop now renders both slots. The run
ask stays first and unlabeled, byte-identical to what it printed before this ticket — it
is the wire-compatible slot every plan ever authored already prescribes
(`WeeklyTemplate.Entry`'s own doc comment). A lift ask, when the plan prescribes one, is
tagged `Lift:` and follows on the same line:

```
Weekly template, Monday first. A day names a lift ask (tagged "Lift:") only when the plan
prescribes one — a day with no lift clause prescribes no lifting that day.
Monday: rest
Tuesday: easy, 8.0 km · Lift: lift, 45m 0s, muscle groups: chest, shoulders
Wednesday: hard, (6 × 800m)
...
```

A day whose lift slot is rest gains no clause at all — not "Lift: rest", not a line of its
own. Seven such lines every call is exactly the noise LIFTING-SPEC §10.2's omission rule
exists to prevent, and it is not a new decision here: `PlanFormatting.weekdayLines`
already made it for the screen at MAX-138, and this ticket follows that precedent rather
than inventing a second one.

**One combined line per weekday, not the screen's two rows.** `PlanFormatting`/`PlanCopy`
render a day with both slots as two rows inside one visually-grouped card, where nothing
repeats the weekday name — the grouping does that work for free. A flat prompt has no such
grouping; a second line would have to restate the day's name to say what already followed
it, spending tokens for zero new information. So the fact sheet stays terser than the
screen by design, on one line, and says so in its own comment.

**Closing rule 2's gap — telling "no lift this week" from "a lift I cannot see."** The
per-line omission above is exactly the shape MAX-175's absence rule forbids if left
unexplained: a model reading seven lines with no `Lift:` clause has no way to tell "the
plan asks no lifting" from "the renderer dropped something." So the convention is stated
once, in the header line above the template, rather than per weekday — the same trade the
sessions section already makes with *"A field missing from a line was not recorded for
that session."* One sentence, paid once regardless of how many of the seven days carry a
lift, closes the gap for every day at once.

**`FactSheetFormatting.liftPrescription` moved from `WorkoutFactSheet`,** exactly where
that private function's own doc comment said it would the day this ticket landed: "It
moves the moment `TrainingFactSheet`'s plan block carries the lift slot and becomes its
second caller." A12 rule 3 is why — `WorkoutFactSheet` already had a lift-prescription
renderer (MAX-136), and inventing a second one for the roll-up would have let the two
prompts spell the same measurement two ways. The function itself is unchanged; only its
address moved, and both call sites now read `FactSheetFormatting.liftPrescription(_:)`.

### The severity was higher than G2 recorded, and this closes that too

MAX-175's report flagged the real consequence and declined to fix it: plan drafting reads
the same `TrainingContext.factSheet()` this ticket corrects
(`ChatModel.send`/`draftPlan` both pass `context.factSheet()` straight into the
instruction, and `PlanProposalInstruction.factSheet` is documented as `ContextBuilder`'s
output verbatim), and `PlanProposalInstruction.taskDescription` tells the drafting model:
*"restate each weekday's lift ask from the fact sheet exactly as it stands unless the
conversation asks you to change it."* Before this ticket, the fact sheet never stated a
lift ask, so the model could only comply by inventing one or by proposing rest for every
lift day — and an accepted proposal is a new plan version, so a drafting conversation could
silently zero out an athlete's whole lift schedule. **Rendering the lift slot is the fix
for both problems at once**: the model can now actually see what it is being told to
restate.

No test pinned a drafting output that assumed the lift slot was invisible —
`PlanProposalInstructionTests` and `PlanProposalDraftingTests` construct their fact sheets
as hand-written literals passed directly to `PlanProposalInstruction`, never through
`TrainingContext.factSheet()`, and `ChatPlanDraftingTests`'s end-to-end drafting test uses
a fake model client that returns a fixed reply regardless of what the real fact sheet says.
So this ticket changed no drafting test's expectation; it closed a live gap nothing was
exercising.

### Tests

`Tests/MaximizeCoreTests/TrainingFactSheetPlanBlockTests.swift`, new — three cases, each
pinning whole rendered lines (not loose substrings) so a future edit cannot silently drop
the slot again the way MAX-136 found it dropped: a week with lifts on some days, a week
with none (asserting the convention sentence is present and no line anywhere carries
`Lift:`), and a weekday prescribing both slots on one line with every field
`liftPrescription` renders — duration, muscle groups and a note.

### Security review

Required — this is a prompt-contents change (D3). Posted as a PR comment before merge.
**No new field of health data enters the prompt.** Every value the new `Lift:` clause
renders — `ScheduledSessionKind`, `durationSeconds`, `muscleGroups`, `note` — was already
stored on `ScheduledSession` (MAX-129/131/137) and already reached a Claude prompt through
`WorkoutFactSheet`'s lift branch (MAX-136). This ticket renders an existing field in a
second place the athlete's own plan already governs; it adds no new health data and no new
data source.

**`swift build`/`swift test` were not run** — no Swift toolchain in this container (R1).

---

## MAX-178 — acute vs. chronic load balance

Rolling 7-day and 28-day sums of `DerivedMetrics.strain.points` (MAX-176), and their ratio,
in `LoadBalanceCalculator` — matched to `TalliesCalculator`'s own shape: an `*Input` struct
carrying an explicit `anchor` (never `Date()`), a `*Calculator` enum, one `compute` entry
point. New files only: `Sources/MaximizeCore/Tallies/LoadBalanceCalculator.swift` (the
calculator, `LoadBalanceInput`, `LoadBalance` and `LoadBalanceReading` together — one file,
matching the ticket's own file list rather than splitting the output type into `Domain/` the
way `Tallies` and `MuscleFatigue` are split, since nothing else reads `LoadBalance` on its
own). `TrendTileData.swift` and `TrendTilesView.swift` gained the tile; `TrendTilesModel.swift`
was also touched, to resolve `LoadBalanceInput` from the stores and call the calculator — not
in the ticket's own file list, but load-bearing: nothing renders without it, and it touches no
file MAX-177 owns.

### The two decisions the ticket asked for, and why

**Nil strain is skipped, never zeroed, and the coverage gap is counted.** A workout with no
strain figure — no heart-rate curve, or metrics simply not yet computed — contributes nothing
to either sum (A18/MAX-175's invariant, restated at this seam: a zero here would read as "this
session cost nothing" and would be summed into the rolling load as a real day of training).
What it does do is increment `acuteWorkoutsWithoutStrain` / `chronicWorkoutsWithoutStrain`, so
`TrendTileData`'s caption can say "N sessions this week without strain" rather than presenting
a 7-day sum silently missing coverage as though it were a sum of everything that happened —
MAX-176's own instruction for this ticket, quoted in `LoadBalanceCalculator`'s doc comment.

**The ratio's denominator is the chronic sum scaled to a week, not the raw 28-day total.**
`acuteStrainPoints / (chronicStrainPoints / 4)`, not `acuteStrainPoints / chronicStrainPoints`.
Dividing two raw sums of unequal windows makes steady, unchanging training read as roughly
0.25 forever — 7 days of a total against 28 days of the same total is always about a quarter,
independent of whether the athlete is undertrained, holding steady, or overreaching. Scaling
the chronic sum to the acute window's length turns it into "a typical week over the last
month", so the ratio reads as how this week compares to the athlete's own recent normal —
steady training sits near 1.0. This is the standard acute:chronic workload ratio construction
from the sports-science literature the feature is modelled on, the same way Edwards' zone
weighting was borrowed rather than invented for MAX-176.

**Partial history is `.buildingHistory`, not a truncated sum.** Fewer than 28 days between
`LoadBalanceInput.historyStart` (the earliest day the app can vouch for — the earliest
recorded workout, resolved by `TrendTilesModel`, never assumed) and the anchor, inclusive,
and `compute` returns the designed absence state instead of a `LoadBalance`, however few or
many workouts happened to fall in that short span. Nine days of hard training on a six-day-old
account reads "6/28 days — building load history", not a ratio a reader would take at face
value. `historyStart` is resolved from the same `WorkoutRepository` the sums already read —
no new repository method, no `Date.distantPast` query: `TrendTilesModel.loadBalance` probes a
bounded range (2010-01-01 onward) only when the chronic window's own earliest workout has not
already proven sufficiency, so most calls make exactly one repository read beyond the window
itself.

### A third decision, found in review rather than specified

The ratio and `chronicWeeklyAveragePoints == 0` are the same fact stated two ways —
`LoadBalance.init` now rejects a `ratio` that disagrees with a zero baseline, the same
cross-field discipline `DerivedMetrics` already applies to strain-without-heart-rate. Nothing
outside this ticket's own files depends on it; recorded because MAX-176's write-up flagged
that this project's review culture expects illegal states to be unrepresentable where the
type system allows it, not merely undocumented.

### What is deliberately not here

No verdict, no colour, no "high"/"low"/"risk" wording anywhere in `LoadBalanceCalculator`,
`TrendTileData` or `TrendTilesView` — the figure is reported, not interpreted. The doc comment
argues this at length so a future change that adds a threshold does not read the file as
having left room for one. `TrendTileDataTests.testLoadBalanceTilesNeverEditorialise` pins it
by scanning every state's rendered value/caption for a short list of coaching words.

### What CI can and cannot prove

CI can prove: the package compiles; every sum in `LoadBalanceCalculatorTests` matches
arithmetic worked out by hand in the test's own comment, never captured from `compute`'s
output; the anchor day is included in both windows; a workout outside the chronic window is
excluded even when handed to the calculator; the `.buildingHistory` boundary is exact at 27
vs. 28 days; a zero chronic baseline withholds the ratio without dividing by zero;
`TrendTileData` renders all three `LoadBalanceReading` shapes without ever leaving `tiles`
without a load-balance entry.

CI cannot prove anything about how the tile reads on a real screen — no device has shown it
yet, and no verification exists that a genuine six-day-old install or a genuine four-week
history renders legibly at every Dynamic Type size and in both colour schemes. See the PR's
own "Needs device verification" section.

**`swift build`/`swift test` were not run** — no Swift toolchain in this container (R1).

---

## MAX-184 — an audit of the chat surface and its context continuity

`docs/CHAT-AUDIT.md`. **An audit. No source is changed, no behaviour moves.** Dispatched on
the owner's words: *"How's our chat features — let's try to emulate a top shelf chat
interface. Also have the interactions with plans and workouts in the chat be seamless. Keeps
context for both. Really sus out any potential issues."*

**Nothing dangerous was found.** No data loss, no health data leaving the device that should
not, no crash, no unreachable-state trap. The nearest thing to a privacy finding is that
`MaximizeStore.threadSummaries()` decodes every stored transcript into memory to render a list
that shows none of them — an in-memory exposure against the rule `ChatThreadSummary`'s own doc
comment states, not a leak. Worth fixing; not an emergency.

### What was verified, and what was not

There is no Swift toolchain in this container (R1), so nothing was built, no test was run and
no pixel was seen. Every claim about code is cited `file:line`; every claim about what a
person would *experience* is inference from view structure, and the four inferences that could
not be pinned down are quarantined in the document's §7 and deliberately excluded from its
ranking.

**Three of the audit's own line citations were wrong on first pass** because they had been read
from a concatenated `cat` of two files; all were re-grepped and corrected before commit. Worth
recording as a method note for the next auditing ticket: cite from a single-file read or a
`grep -n`, never from a concatenation.

### The three worst defects

1. **"New chat" is inert on the ordinary path.** `ChatSheet.startNewTrainingChat()` assigns
   `opening = .subject(.training(currentScope))`, which on the common route is the value
   `opening` already holds — so `.id(opening)` does not change and the view is not recreated;
   and even if it were, `thread(for:newThreadID:at:)` resolves an unchanged scope to the thread
   already open. No new thread, no response, no explanation. A second-order consequence: the
   repository deliberately allows several threads per training scope and the UI has no door to
   one.
2. **The workout screen's chat card is not tappable and never refreshes.** It has no tap
   target of any kind, and its `.task` does not re-fire when the chat sheet dismisses — so
   having a conversation about a run returns the athlete to a card still showing the
   invitation. That is the exact defect MAX-098 says the card exists to fix.
3. **The plan proposal card outlives the save it caused.** Nothing clears
   `ChatModel.planDrafting` when the authoring screen it opened stores a version, so Back
   returns to a diff describing a change that has already been applied, with **Accept this
   plan** still live — a second tap writes a duplicate version. D1 is not violated; the screen
   is telling an untruth.

### The position taken on context continuity

**The two-subject split is right and should not be merged.** §3.1's argument against
concatenating N workout contexts holds. Three separate things were being conflated:

- **The highest-value fix is not the one the ticket was dispatched on.** Strain (MAX-177),
  acute:chronic load balance (MAX-178) and per-muscle fatigue (MAX-179) are computed, stored
  and drawn on a tile — and reach **no prompt on the training side at all**. So a training
  thread asked *"am I ramping too fast?"* correctly refuses, under `trainingTask`'s
  never-invent rule, to answer a question the app has already answered one tap away. Fixing it
  is two lines in the tallies block and one field per session line, every figure through the
  function the dashboard tile already reads, so §3.6(a) holds by construction. **MAX-192.**
- **A workout thread should learn which week it is in, as aggregates only.** A fixed-size
  block — the Monday-first week, its arc week and prescribed long run, that week's tallies, the
  ratio as of that day, the session count — and **no sibling session lines**, because a block
  that grows with training volume is `TrainingContext` arriving by a side door. It is O(1),
  built from the dashboard's own functions, and adds no new *category* of data. It is still a
  widening, so it is **an amendment (A29) before it is a ticket**. **MAX-193, blocked.**
- **The reverse direction should stay a navigation problem.** Depth on one session from a
  training thread is already handled: the prompt states its own exclusions, `trainingTask`
  tells the model to point at that run's conversation, the runs strip pushes that run's detail
  screen, and that screen's Ask bar opens that run's thread. The loop closes; only the copy
  connecting the model's refusal to the strip is missing.
- **`canDraftPlan`'s training-only gate is correct and should not be removed.** A `PlanProposal`
  drafted from one run's fact sheet would be inventing most of its fields. The defect is the
  absence of a route from a run's conversation to the plan's — **MAX-194**, which reuses the
  reassignment mechanism `ChatSheet` already has.

### What the audit says not to touch

`ChatReplyPhase` / `ChatReplyProgress` (MAX-152, MAX-170) — the stall rule that calibrates
against the stream rather than a constant is named as the standard the rest of the feature
should be held to. `ChatFailureNotice`'s exhaustive, code-free, retry-gated copy. MAX-081's
`safeAreaInset` composer and MAX-153's `ChatTranscriptFollow`. The shimmer's
words-first/Reduce-Motion-and-Transparency-off treatment. `TrainingScope` freezing and
`ChatScopeNotice`. The runs strip's bounds and its refusal to carry a measured figure.

### Proposed tickets

**MAX-185–191** (defects), **MAX-192–194** (continuity), **MAX-195–201** (craft — Markdown and
selectable replies, VoiceOver speaker attribution, cancellation, draft survival, haptics,
conversation starters, thread-list search). Tiers, collisions and a dispatch order are in the
document's §8. Three collisions to respect: 192 before 193 (`ContextBuilder.swift`), 188 before
201 (the thread list), and 185 → 194 → 190 in sequence (all three are `ChatSheet.swift`).


## Risks

| # | Item | Impact | Status |
|---|---|---|---|
| R1 | No Swift toolchain in the dev container; `download.swift.org` blocked | CI is the only gate | Accepted — mitigated by fat-core architecture + macOS CI |
| R2 | No device/simulator in the loop | HealthKit flows, UI, on-device performance unverified until a human checks | Accepted per direction. PRs must list what needs device verification |
| R13 | App-layer wiring is compiled but never executed | A defaulted parameter silently selected a no-op store — in **two** files, the second added the same hour the first was found; nothing in CI could see either | The stub is deleted, so there is nothing to default to. No production call site may default to a repository that can resolve to a no-op. **MAX-169 kept that rule while making one resolution lazy**: `SettingsModel` now reads `PersistenceComposition.store` at each use rather than capturing it in `init`, because `shared` is built at launch and would otherwise be the one holder still carrying nil after a retry succeeded. The fallback is still `PersistenceComposition.store` and nothing else. That ticket also added the largest single piece of app wiring nothing has ever run — the store-failure screen and its retry — so every decision inside it was pushed into `MaximizeCore` (`StoreAvailability`) where the suite does run |
| R14 | CI is a hosted-minutes dependency | The whole merge gate vanished mid-session when the Actions allowance ran out — every job, including Ubuntu, failed in 2s with no runner | Repo is public, so standard runners are free and uncapped. Core suite moved to Linux (1x) so only `xcodebuild` needs macOS |
| R3 | Anthropic key on-device | Weakens PRD §6 | Accepted for single-user (A5). **Tripwire: blocks any distribution** |
| R5 | HealthKit background-delivery entitlement key | Wrong key means the wake silently never fires | **Resolved** at MAX-030 — `com.apple.developer.healthkit.background-delivery` confirmed against Apple docs; the PRD's guess was right. Base HealthKit entitlement and `NSHealthShareUsageDescription` also in place; all three fail the same silent way |
| R6 | Scoring correctness; auto-vs-manual divergence is the quality signal | Loop loses trust fast if scores disagree with judgment | D8 telemetry + MAX-071 fixtures; revisit rubric after real runs |
| R7 | Claude's *judgment* can't be unit-tested, only the rubric plumbing | Scoring regressions could pass CI green | MAX-071: fixture runs with known-good expected bands |
| R8 | Background-delivery wake windows are short; scoring makes a network call | Scoring may not finish in the wake window (PRD §2 p50 < 2 min) | MAX-033 to score lazily on first view if the wake budget is exceeded. Compounded: MAX-030 notes `.immediate` frequency is a *request* iOS may clamp, so the p50 target has a second uncontrolled factor |
| **R9** | **MAX-030 acknowledges every background wake, including failed ones — so iOS never retries.** This is only safe because a missed wake is recovered by the next anchored fetch | If MAX-031 lands a fetch that is not anchored or not idempotent, missed workouts are lost permanently and silently | **Constraint on MAX-031, not a risk to monitor.** The reasoning is documented in `WorkoutObservationCoordinator`; if the anchor guarantee changes, that decision must be revisited |
| **R11** | **A permanently unacceptable workout wedges the whole pipeline.** If the sink throws deterministically for one workout, the anchor never advances past it, so it is refetched and rethrown on every pass forever — and every later workout queues behind it | Zero-touch capture stops entirely, and the symptom is silence | **MAX-033 must handle this.** Found by MAX-031, which deliberately did not build a poison-pill escape: "give up on this workout" is a data decision belonging to whoever owns the store. The obligation is documented on `WorkoutIngestionSink` |
| R12 | The anchor write and the workout write are two separate stores, so the window between them exists by construction | A crash between them re-delivers the batch — absorbed by dedupe, so this is the safe side | **Accepted permanently. Do not "fix" this.** ~~MAX-020 can close it by moving the anchor into the same SwiftData transaction~~ — that earlier note was wrong and MAX-020 correctly refused it. See below |
| **R15** | **No failure state in the app offers a retry, and a whole-store failure is never named as one.** Every `.failed` state is terminal until the view is rebuilt — including the ones a second attempt would plainly clear (a scoring call that timed out, a Keychain read during the moment the device was locked). And when the *store* is what failed, every screen independently says its own content could not be loaded, which reads as five separate problems rather than the one that it is; nothing tells the athlete that nothing at all is being saved | An athlete's only recovery from a transient failure is to guess that backing out and re-entering a screen will help, and their only signal for a permanent one is that the whole app looks broken in five different ways | **The store half is closed by MAX-169; the per-screen half is still open.** MAX-154 made every failure legible and put the store-open reason in the log (it previously went nowhere), but deliberately did not add controls or an app-level banner. MAX-169 added both, for the store only: an unopenable store is now one named state (`StoreAvailability`) said once at the app root instead of nine surfaces each reporting their own read, it says plainly that nothing is being saved and that nothing has been deleted, and it offers a retry on the reasons a second attempt could clear and none on the reason it could not. **Still open:** every other `.failed` state is terminal until its view is rebuilt — a scoring call that timed out, a Keychain read taken while the device was locked, a plan version that would not save. Each has a retry that would plainly work and no control for it. Found by MAX-154 |
| **R16** | **A first plan dated later than the history already on the device destroys that history, permanently and silently.** Three individually correct behaviours compose into it: the ingester backfills 90 days on its first pass, the authoring screen suggested this week's Monday as a first plan's effective date, and a workout on a day no plan governs is stored with no derived metrics and reported as `.workoutPredatesEveryPlan` — a reason that **never resolves**, because MAX-011 rightly forbids a later version from opening before an earlier one | An athlete accepting the suggested date on install day stranded roughly 89 days of their own training: stored, but never measurable, never scorable, never in a tally, and never mentioned on any screen. Silent, permanent, and invisible in CI because each part was correct in isolation | **Closed by MAX-165 (A23)** for the first plan, which is where it was reachable: the suggestion now covers the earliest captured workout, and the screen states in figures what any candidate date would exclude. **The class is not closed.** A workout that syncs *after* the first plan is saved but is dated before its effective date — a late Watch sync, a Health import from another app — is stranded the same way, still silently. Named in FIRST-RUN-SPEC §7.4; not yet a ticket |
| **R17** | **A fix written into `StandardPlanSeed` does not reach anybody who already has a plan.** D1 makes the seed authoring *input*: it supplies the bands a first plan starts from and is then out of the loop forever. That is the property that keeps thresholds out of code — and it also means a corrected band, a new band, a reordering, or any future seeded plan field is delivered to precisely nobody until an athlete authors a new version. Every half is correct in isolation, which is why it took MAX-168 refusing to open a gate to notice | Two corrections sat undeliverable for four tickets: MAX-132's lift adherence bands and MAX-146's `rest.ranAnyway` condition, the second of which stamps every unprescribed lift *"Ran on a scheduled rest day."* A seed edit reads like a fix and lands like a no-op, and nothing in CI can tell the difference — the seed's own tests pass, because they test the seed | **Mitigated, not closed, by MAX-173.** There is now a route: authoring a revision adopts the current bands, stated on screen, as a new version. **The route still needs a human to walk it** — merging a seed fix changes no device until the owner opens Plan → revise → Save, so "shipped" and "in effect" remain different words. **The class recurs by construction:** the bands were the one plan field `PlanDraft` deliberately does not carry, which is exactly why they had no route — every other seeded value (the cap, the cadence band, the two thresholds, the arc, the week, the duration floor) is editable on the authoring screen, so an athlete can reach a new seed value by typing it. The next plan field added without either a draft field or an adoption path is stranded the same way, silently. Any ticket editing `StandardPlanSeed`, or adding a field to `Plan`, must say how its change reaches a plan that already exists — or say plainly that it does not. **MAX-168 adds the other half of the mitigation for the two stranded corrections:** the scoring path now asks the *stored* rubric whether the band it matched names the workout's discipline, and declines to write a permanent score when it does not. So a device that has not walked the route can no longer be harmed by not having walked it — it is left with no score rather than a wrong one |
| R10 | The app cannot know whether Health *read* access was granted — `authorizationStatus(for:)` reports share status only, by Apple's design | No UI can honestly display "Health connected"; a permission problem is indistinguishable from "no workouts recorded yet" | Accepted, Apple-imposed. Found at MAX-030. Any future settings or onboarding UI must not claim read access it cannot verify. **MAX-161's spec §9 turns that into a rule with a structural defence and a test, and MAX-162 built it**: `FirstRunStep` models no per-step completion and the Health step has no completed state, so there is no value a view could draw a tick from; `FailureCopyTests.testNoHealthCopyClaimsAccessWasGrantedOrRefused` was extended over `FirstRunCopy` rather than duplicated. The rule now binds MAX-163's cover and MAX-164's card by construction rather than by review. (This row appeared twice after MAX-161; the duplicate is removed) |

## Overseer failure modes

Failures the orchestration itself caused, recorded so the next context window does not
re-derive them. These are not risks to monitor; they are mistakes with known signatures.

**A ticket is done when it is merged, not when the overseer decides it is.** MAX-086 sat
open while the board said shipped, so an appearance fix the board claimed was on the
device was not. Tick a row against a merge commit, never against memory.

**Two PRs that each pass CI can break the base branch together.** Each was tested against
a base that did not contain the other; the merge is textually clean and semantically
broken; no review catches it because neither diff is wrong alone. The signature is
distinctive — *every* open branch fails at once, including ones touching nothing near the
error, because one bad file fails a whole test module. After a wave where two merges touch
overlapping types, re-check that the base branch still builds.

**Two parallel tickets can define the same type twice, and a merge will keep both.**
MAX-137 nested an `ObligationSummary` inside `PlanDraft.DayDraft`; MAX-138 introduced the
shared one in `Domain/ScheduledSession.swift` and wrote the app's formatter against it.
Both merged green. The next branch to merge main resolved the conflict by keeping both, so
the nested twin shadowed the shared type and the formatter overload stopped matching —
surfacing as `no exact matches in call to static method 'describe'` in a branch whose own
diff touched neither file. **Decomposition owns this**: when two tickets in one wave answer
the same question, one of them writes the type and the other imports it, and the brief
says which. Naming the files each ticket touches is what makes the collision visible before
it is a merge conflict.

**A worktree's `cd` persists across shell calls.** A branch created from the overseer's
shell while its working directory had drifted into an agent's worktree inherited that
agent's unmerged commits, and merging it shipped a ticket's partial work. Pass absolute
paths; check `git log --oneline -1` before branching.

**Put the push instruction last in an agent brief.** Agents that were asked to run a
security review *after* the push line ran the review and never pushed — twice. The commits
sat in a local worktree and the failure was silent.

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
| 2026-08-18 | **MAX-175**: where the data required for a judgement is absent, the app produces **no** judgement rather than a degraded one — and an absence is named, not filled, at every boundary (record, fact sheet, prompt, tallies, calendar, screen) | The behaviour was already right in six places and written down in none, so a seventh ticket inherited nothing. Recorded here rather than as a PRD amendment because it amends nothing — §10 already behaves this way — and because A26–A28 are proposed by MAX-174 and in review. Two consequences are not obvious and are the reason it is worth stating: an absence must say *which kind* it is ("never measured", "does not apply here", "not shown to this reader") because a model reasons confidently from an undifferentiated gap; and a refusal must not be softened into a degraded answer, so an unscored run gets no chat rather than a quieter one |
| 2026-08-04 | **MAX-034**: `WorkoutIngestionPipeline.enrich` extracts and stores samples (HR series, route) before resolving the plan, not after | Fixed a permanent-data-loss bug: `enrich` previously returned before `WorkoutSampleExtractor.extract` ran whenever no plan governed the workout's day, so every run predating the athlete's first plan version kept no HR curve — and MAX-031's advancing anchor never revisited it. The curve is a fact about the run, not the plan; only derived metrics (§9, measured against the plan's cap) stay gated on plan coverage. `IngestionPipelineDiagnostic.storedWithoutPlan` now documents that samples are stored either way. Found in the same pass: `.workoutPredatesEveryPlan` can never be completed later — MAX-011's version/`effectiveFrom` ordering forbids a plan from ever back-dating earlier than one that already exists — unlike `.noPlanAuthored`, which the lazy path does complete once a first plan is authored |
| 2026-08-20 | **MAX-178**: the acute:chronic ratio's denominator is the chronic sum scaled to a week (÷4), not the raw 28-day sum | The two are not interchangeable — dividing raw sums of unequal windows makes steady training read as a constant ~0.25 regardless of load, carrying no information. Scaling the chronic sum to the acute window's length is the standard sports-science acute:chronic workload ratio construction, and reads as "this week vs. the athlete's recent normal" with steady training near 1.0 |
| 2026-08-20 | **MAX-178**: the first 28 days of an athlete's recorded history is `.buildingHistory`, a designed absence tile, not a ratio computed from a short window | A ratio computed from four days of data is a confident-looking number over almost nothing. `LoadBalanceInput.historyStart` — the earliest day the app can vouch for — is what tells a real, zero-load rest period apart from a window the app simply has not observed yet; a day before it is never read as a free zero |

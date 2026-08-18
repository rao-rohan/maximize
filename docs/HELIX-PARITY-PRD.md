# Helix Parity — PRD

**Ticket:** MAX-174
**Status:** Proposal, for the owner's decision. **No source is changed by this document.**
**Owner's direction, verbatim:** *"Look at this app https://www.projecthelix.app/docs/ai-coach
I want our feature set/ui to match this exactly. Get to work complete a prd and create tickets."*

---

## 0. Read this first — the primary source could not be reached

**All three primary sources are blocked by this environment's network egress proxy.**
Verified by both `WebFetch` and `curl`; each returns `EGRESS_BLOCKED`, not a 404 or a
paywall:

| URL | Result |
|---|---|
| `https://www.projecthelix.app/docs/ai-coach` — **the page the owner sent** | ❌ blocked |
| `https://www.projecthelix.app/` | ❌ blocked |
| `https://apps.apple.com/us/app/helix-ai-fitness-coach/id6789951372` | ❌ blocked |

So **nothing in this document is verified against Helix's own pages.** Everything about
Helix below is reconstructed from web search results that quote or paraphrase those pages.
Search returned a lot — several passages appear to be near-verbatim marketing copy, and the
same claims recur across independent queries, which is decent corroboration — but it is
second-hand, and a parity spec built on a guess about the competitor is worse than one that
says where its knowledge stops.

Every Helix claim below therefore carries a confidence marker:

- **[S-high]** — recurred across multiple independent searches in near-identical wording;
  reads as quoted marketing copy. Treat as very likely accurate, still unverified.
- **[S-med]** — returned once, or paraphrased rather than quoted.
- **[S-none]** — *I could not establish this at all.* Named explicitly because the gaps
  matter as much as the findings.

**What I could not establish, and it is the important half:**

- **The actual content of `/docs/ai-coach`** — the specific page the owner pointed at.
  Everything I have about the AI coach is one sentence of marketing copy. I do not know
  what the coach's UI looks like, what it can be asked, whether it is proactive or
  reactive, whether it writes to the app's own state, or what its onboarding is. **[S-none]**
- **Any screenshot or UI description.** The owner asked for the **UI** to match "exactly"
  and I have not seen a single pixel of it. Every UI statement in this document is
  therefore about *information architecture* inferred from feature names, never about
  layout, and no ticket below claims to reproduce a Helix screen. **[S-none]**
- **Pricing, subscription model, free tier.** **[S-none]**
- **Whether the Apple Watch app is required or optional**, and what it does beyond "live
  readiness". Search explicitly declined to answer this. **[S-none]**
- **The exact wording of the privacy claim on the docs page**, as opposed to the home page
  sentence quoted below. This matters because §3.5 compares it to ours line by line. **[S-med]**

**If the owner can open those pages, the single highest-value next action is to paste the
`/docs/ai-coach` text into this repo.** §2's table is the part that would change, and
§3.5's privacy comparison is the part most likely to be wrong.

---

## 1. Helix, as reconstructed

Positioning: *"the complete engine for an athlete"* — it *"measures every system of your
body — sleep, strain, recovery, strength, and blood — and turns it into your next move."*
Runs on *"the Apple Watch and iPhone you already own, with nothing to buy and nothing new
to wear."* **[S-high]**

| # | Capability | What search says | Conf. |
|---|---|---|---|
| H1 | **Morning recovery score** | Built from *"HRV, resting heart rate, respiratory rate and wrist temperature, compared against your own baseline — not a population average."* One score each morning | S-high |
| H2 | **Sleep** | Duration vs need, efficiency, deep/REM, latency, sleep debt across the week, sleep regularity. Can *"estimate your night from your iPhone even without a watch"* | S-high |
| H3 | **Strain per workout** | *"Every workout earns a strain score from heart-rate load, so hard days count and easy days stay easy"* | S-high |
| H4 | **Strain ceiling for the day** | Strain expressed as *"a percentage of what your body can handle today… measured against today's recovery-adjusted ceiling"* | S-high |
| H5 | **Load balance** | Acute vs chronic training load; shows the *"sweet spot"* and when you are *"piling on risk"* | S-high |
| H6 | **VO2max lab** | Guided Cooper test plus interval work | S-high |
| H7 | **Strength lab / muscle map** | Per-muscle recovery, a full muscle map; *"models fatigue for every muscle group, so your chest can be fried while your legs are fresh"* | S-high |
| H8 | **AI coach** | *"reads your numbers and tells you what they mean."* Runs on OpenAI **and** Claude | S-high |
| H9 | **Physique scan** | *"physique and gym equipment scans powered by AI"* | S-med |
| H10 | **Gym-equipment scan** | As above | S-med |
| H11 | **Bloodwork analysis** | *"upload lab results and see them in context"* | S-med |
| H12 | **Nutrition logging** | Barcode scanning and meal-photo scanning | S-med |
| H13 | **Menstrual cycle awareness** | Used for training guidance | S-med |
| H14 | **Energy plan** | *"schedules the day around your body"* | S-med |
| H15 | **Apple Watch app** | *"standalone"*, with live readiness | S-med |
| H16 | **Widgets / Smart Stack / Live Activities** | Named together in one result | S-med |
| H17 | **Game Center leaderboards + badges** | *"earn badges and climb Game Center leaderboards as your fitness improves"* | S-med |
| H18 | **Privacy** | *"no backend… everything computed and stored on your iPhone"*; *"no account to create by design"*; *"no ads, no trackers"*; the models *"only ever receive anonymized numbers: never your name, never your raw records"* | S-high |

---

## 2. Feature-by-feature comparison

"What we have today" is read from this repo — `docs/PRD.md`, `docs/PRD-AMENDMENTS.md`
(A1–A24), `PROJECT_TRACKER.md`, and the source under `Sources/MaximizeCore/` and `App/`.
That column is **verified**; the Helix column is not.

| # | Helix capability | Maximize today | Gap | Verdict |
|---|---|---|---|---|
| H1 | Morning recovery score from HRV, RHR, respiratory rate, wrist temp vs personal baseline | **Nothing.** `HealthDataType` authorises exactly six types — workout, heart rate, distance, active energy, steps, route. No HRV, no RHR, no respiratory rate, no body temperature. Every stored record is keyed to a workout or a plan day; there is no daily-health record type at all | New sample types, a **non-workout-anchored** ingestion path, a new daily record, a baseline model, a new surface | **Build** — the highest-value item on the list |
| H2 | Sleep: stages, efficiency, latency, debt, regularity | Nothing. Sleep is not read, stored or mentioned anywhere | As H1, plus `HKCategoryType` handling (we read only quantity + workout types today) | **Build, after H1** |
| H3 | Per-workout strain from HR load | **Adjacent but different.** We compute average/max HR, time-above-cap, HR drift, zone splits, GAP, cadence, distance splits (`DerivedMetrics`), and a plan-relative 0–100 effectiveness score. We measure *"did you execute the ask"*; Helix measures *"how much did that cost you"* | A cost metric — TRIMP or a zone-weighted integral — from the HR curve we already store | **Build** — genuinely cheap, see §3.1 |
| H4 | Recovery-adjusted daily strain ceiling | Nothing. Our plan prescribes sessions (`ScheduledSession`), not a daily load allowance | Depends entirely on H1 and H3 | **Build, third** |
| H5 | Acute vs chronic load balance | Nothing. `TalliesCalculator` counts obligations, effective days, streak, average score — no load figure exists to ratio | Pure arithmetic over H3, once H3 exists | **Build** — trivial after H3 |
| H6 | VO2max lab: guided Cooper test, intervals | Nothing, and it is a **different product mode**. PRD §3 non-goal: *"Live / in-workout coaching. Post-workout only."* A guided test is a live, in-workout, timed protocol; it also implies writing a workout to HealthKit, which §3 lists as a separate non-goal | Live session UI, timers, a Watch surface to be usable, HealthKit write | **Decline** (§7.1) |
| H7 | Per-muscle recovery + muscle map | **Closest of anything here.** `MuscleGroup` is a closed six-case core vocabulary with a `fullBody` set and canonical ordering; A22 has the athlete entering groups per lift on the detail screen; `MuscleGroupEntryRecord` is in the schema; A17 lets a plan prescribe groups; A20 scores lifts on adherence | A decay model over the entries we already collect, and a rendering. **No new HealthKit data, no new capture, no manual entry beyond what A22 already admitted** | **Build** — best effort-to-value ratio in the whole table (§3.2) |
| H8 | AI coach that reads your numbers | **We have this, and arguably better.** Streaming chat (D10), per-subject threads (A11/A12), one context builder feeding scorer and chat (D3), Claude-drafted plan proposals (A13), Ask on every screen (A10) | Ours is strictly reactive by rule (A14: *"no unattended chat call, ever"*). If Helix's coach is proactive, that is the delta — and it is a rule change, not a feature | **Adapt** — feed it the new numbers; do not make it proactive (§7.4) |
| H9 | AI physique scan | Nothing | Camera capture, a vision model call, and a **claim about a person's body** | **Owner decision required** (§8.1) |
| H10 | AI gym-equipment scan | Nothing | Camera + vision call. Harmless, and also pointless without an exercise library we deliberately do not have (A20) | **Decline** (§7.2) |
| H11 | Bloodwork analysis | Nothing. HealthKit does expose some lab-adjacent types, but we read none | Document/photo ingestion, and **interpretation of clinical values** | **Owner decision required** (§8.2) |
| H12 | Nutrition logging, barcode + meal photo | Nothing, and it is doubly excluded: PRD §3 non-goal *"Diet / nutrition tracking"*, and §3's *"Manual entry… the thing being killed"* | An entire logging product | **Decline** (§7.3) — this one contradicts the north star |
| H13 | Menstrual cycle awareness | Nothing | A HealthKit category type, and plan logic that reads it | **Owner decision required** (§8.3) — single-user app; only the owner knows if it applies |
| H14 | Energy plan — schedules the day | Nothing. Our plan is a weekly prescription by (weekday, discipline), not an intraday schedule | Depends on H1/H2/H4 | **Defer** (§7.5) |
| H15 | Standalone Apple Watch app | **No Watch target exists.** `project.yml` builds one iOS app target plus the core package | A new target, a new build config, a WatchConnectivity or shared-HealthKit story, and a second UI to design | **Decline for parity; revisit only for H1** (§4) |
| H16 | Widgets, Smart Stack, Live Activities | Nothing | A widget extension. Cheap *once there is a daily number worth glancing at* — today there is not | **Defer until H1 ships** (§7.6) |
| H17 | Game Center leaderboards, badges | Nothing, and pointedly so: `RootTab`'s own doc comment describes a dense, quantitative app for one comfortable athlete; PRD §5 says the UI *"can be dense and quantitative, not hand-holdy"* | Game Center entitlement, an achievement design | **Decline** (§7.7) — and leaderboards need other people, which a single-user no-account app does not have |
| H18 | Privacy: on-device, no account, anonymised numbers to the model | **Equal on structure, weaker on one specific.** A1: no backend, everything on-device. No account, no trackers, no analytics. A5 puts the Anthropic key in Keychain. **But our prompt is not anonymised** — `WorkoutFactSheet` opens with `Date: <day> (<weekday>)`, and carries plan goal statements the athlete typed free-form | Date de-identification and a goal-statement policy, if we want to match the claim | **Adapt** — see §3.5, and it is a real finding |

---

## 3. What our architecture makes cheap, and what it makes expensive

### 3.1 Cheap: anything computed from a stored HR curve

D2 says derived metrics are computed once at ingestion and stored; D7 stores the HR series
as a blob on the workout. `DerivedMetricsCalculator` already walks that curve five times —
average, maximum, time-above-cap, drift halves, zone splits.

**Strain (H3) is a sixth walk of the same array.** It is an optional `Double` added to
`DerivedMetrics` (additive, defaulted, CloudKit-clean per A8), one function in the
calculator, one `DerivedMetricKind` case so absence stays first-class per A18, one line in
`WorkoutFactSheet`. It is pure Swift in the core, which means CI proves it end to end. This
is about as cheap as a new metric gets in this codebase.

**Load balance (H5) is arithmetic over stored strain**, in the shape `TalliesCalculator`
already has: a pure function over a date-ranged set of records. No new capture, no new
schema.

### 3.2 Cheap and nearly finished: the muscle map (H7)

This is the finding worth the most. A22 already spent the manual-entry non-goal to have the
athlete tag muscle groups on a lift; `MuscleGroupEntryRecord` is already in the schema and
already mirrored by `StoredMuscleGroupRecords`. What a muscle map additionally needs is:

1. **A decay function** — per group, fatigue from the last session of that group decaying
   over hours. Pure core, fully testable, no device needed.
2. **A load input per group.** Here is the honest wall: A20 established that HealthKit
   carries **no sets, reps or load**, so per-group "fatigue" can only be a function of
   *session duration and heart-rate cost*, divided across the groups tagged. Helix's copy
   implies something richer. **We can build a muscle map; we cannot build Helix's muscle
   map without breaking A20**, and A20's tripwire is explicit that sets-and-reps must
   arrive as an amendment, never inside a ticket.
3. **A rendering.** A body diagram is new drawing work and is the one part of this that CI
   cannot check.

So: build it, and state its limits in the UI rather than implying a precision we do not have.

### 3.3 Expensive: everything daily rather than per-workout

This is the structural cost and it is worth being exact about, because it is easy to
underestimate.

Every ingestion path in this app is **anchored to a workout**. `HKObserverQuery` watches
`HKWorkoutType`; `WorkoutQueryAnchor` persists a position in *workout* change history;
every fetch request in `WorkoutSampleFetching` is `(workoutID, windowStart, windowEnd)`;
every stored record is keyed by `workoutUUID`, a plan version, or a calendar day override.
There is no record type in `MaximizeSchema` that means *"here is a day"*.

Recovery (H1), sleep (H2) and the strain ceiling (H4) are **daily** facts that exist on
days with no workout at all. Concretely, H1 needs:

- **Four to six new `HealthDataType` cases**, which widens the HealthKit permission sheet.
  Note the cost `HealthDataType`'s own doc comment already flags: the sheet is presented
  once per newly requested type, so this is a **second permission prompt** for every
  existing install — the exact thing the route type was bundled early to avoid.
- **A `HKCategoryType` path** for sleep. Today we read quantity types and workouts only.
- **A second observer and a second anchor.** The tracker's *"Why the HealthKit anchor must
  never share a store with workouts"* section applies again, for the same reason.
- **A new daily record type** in `MaximizeSchema`, and MAX-169's additive-schema question
  gets asked again.
- **A baseline model.** *"Compared against your own baseline"* means a rolling personal
  window with a warm-up period and a defined behaviour when there is not enough history —
  which, per this codebase's standards, is a designed absence state, not a blank.
- **A new surface.** Three tabs is already the argued-for maximum in `RootTab`'s doc
  comment; a morning-readiness view does not obviously belong on any of them.

That is roughly the size of the original ingestion phase, done again. It is worth it — H1
is the feature the rest of Helix's engine hangs off — but it should not be costed as "add
some HealthKit types".

### 3.4 Expensive and off-shape: live protocols and camera work

The VO2max lab (H6) is not a hard algorithm — a Cooper test is twelve minutes and a
distance. It is expensive because it is a **different product mode**. This app is
post-workout by rule (PRD §3), it does not write to HealthKit by rule (PRD §3), and it has
no live-session UI, no timer infrastructure, and no Watch. Every one of those is a
first-of-its-kind in this repo.

Scans (H9, H10) break a different invariant: they send an **image** to a model. Every Claude
call today goes through the single context builder (D3), which renders a deterministic text
fact sheet from stored numbers. An image is not a fact sheet, and A12's *"one module, one
entry point, one renderer"* has no branch for it. That is not fatal, but it is an amendment,
not a ticket.

### 3.5 The privacy claim: where we are stronger, and the one place we are weaker

**Structurally we are equal or better.** Helix says no backend, on-device, no account, no
ads, no trackers — that is A1 verbatim, arrived at independently. We have no analytics and
no crash reporting. Helix calls **two** providers (OpenAI and Claude); we call one. Helix's
"no account" is our position too. On the substrate, there is nothing to catch up on.

**On prompt contents, Helix's stated bar is stricter than our actual behaviour**, and this
is the concrete finding. Their claim is *"anonymized numbers: never your name, never your
raw records."* Ours, read from `WorkoutFactSheet.factSheet()`:

- The first line of every prompt is `Date: <calendar day> (<weekday name>)`. A dated series
  of workouts is not an anonymised number; it is a re-identifiable record of a person's
  movements in time. Helix's claim, taken literally, forbids this.
- `Goals: <statements>` renders free text the athlete typed into the plan authoring screen.
  Nothing stops that text containing a name, a race entry, or a clinical detail.
- Splits (MAX-068) and the route are the next candidates, and MAX-068 is still open with a
  `/security-review` attached for exactly this reason.

**Recommendation: do not adopt Helix's wording, and do close the gap partway.** Dates are
load-bearing — *"you drifted on the long run three Sundays running"* is the product — so
stripping them would damage the app to match a competitor's marketing sentence. But the
goal-statement passthrough is an unexamined channel, and it should get the same treatment
MAX-068 is getting. That is MAX-186 below, and it needs `/security-review` per CLAUDE.md.

---

## 4. The recommendation, stated plainly

**I do not recommend matching Helix exactly, and I think doing so would make Maximize a
worse product.** The owner can overrule this; here is the reasoning to overrule.

Helix is a **broad** app: sleep, blood, food, physique, cycle, equipment, leaderboards. Its
value proposition is coverage — *"every system of your body"*. Maximize is a **deep** app
about one question: *did I execute my plan, and is my aerobic efficiency improving?* The
tracker names the drift overlay (MAX-062) as *"the ticket that justifies the project"*,
because *"no other app can draw it"*. Helix, as far as I can tell, cannot draw it either —
it has no notion of a versioned training plan, and nothing in any search result suggests it
scores a workout against a prescription.

Chasing coverage spends the thing we have that they do not. PRD §13 already names this:
*"Scope discipline is the top execution risk, not any technical unknown."*

**What Helix genuinely has that we should take is one idea, not fifteen: the body's cost is
measured, not just its output.** We measure what the athlete produced (pace, drift, cadence,
adherence). Helix measures what it cost (strain, recovery, per-muscle fatigue) and closes
the loop by adjusting tomorrow's ask. That is a real gap in our product and it is the
coherent 80% of Helix's value. It is H1, H3, H4, H5, H7 — five items — and every one of them
composes with our existing plan-versus-actual spine rather than sitting beside it.

**On the Apple Watch (H15), honestly:** we need no Watch target for any of the five. Every
input arrives in iPhone HealthKit after Watch sync; that is how the whole app already works.
A Watch app would buy a glanceable readiness number and nothing else on the recommended
list — and Helix's own copy concedes iPhone-only operation is viable (*"can estimate your
night from your iPhone even without a watch"*). A Watch target costs a new build target,
signing (which `docs/DEVICE-BUILD.md` already describes as the fragile part), a second UI to
design against the same standard in `CLAUDE.md`, and a second surface CI cannot verify. It
is the single worst effort-to-value item in the table. **Decline it, and note that H6
(guided Cooper test) is the only capability that genuinely needs it** — which is a further
argument for declining H6.

---

## 5. Recommended sequence

Highest value per unit of effort first. Each row's effort is stated concretely.

| Order | Tickets | Why here | Effort, concretely |
|---|---|---|---|
| **1** | MAX-175, MAX-176 | **Per-workout strain (H3).** Unlocks H4 and H5, needs no new HealthKit data, no new schema record, no new screen. Pure core arithmetic CI proves | One optional field on `DerivedMetrics`, one calculator function, one `DerivedMetricKind` case, one fact-sheet line, one tile |
| **2** | MAX-177, MAX-178, MAX-179 | **Muscle map (H7).** The A22 entries already on disk become a model. No new capture at all | One core decay type, one presentation type, one body-diagram view. New drawing work, no new data |
| **3** | MAX-180 | **Load balance (H5).** Falls out of MAX-175 | One pure function beside `TalliesCalculator`, one chart |
| **4** | MAX-181 … MAX-184 | **Recovery (H1).** The big one; sequenced fourth because it is the only item that needs a whole new ingestion path, and because 1–3 keep delivering while it is in flight | New sample types + permission re-prompt, second observer + second anchor store, new daily record, baseline model, new surface |
| **5** | MAX-185 | **Strain ceiling (H4).** Only meaningful once both H1 and H3 exist | One core function, one number on the day's surface |
| **6** | MAX-186 | **Prompt-contents review (§3.5).** Small, and it should not wait behind the big ingestion work | Core-only; `/security-review` required |
| **7** | MAX-187, MAX-188 | **Sleep (H2)**, if the owner wants it after seeing recovery land. Reuses MAX-181's pipeline | A category-type read path, added to an existing daily record |
| — | MAX-189 | **Amendments** (§9). Lands with or before MAX-175 | Document only |

**MAX-189 must land first or alongside**, because MAX-175 and MAX-177 both touch decisions
the amendments record. A ticket that quietly widens `DerivedMetrics` or the prompt without
the amendment behind it is exactly the drift `docs/PRD-AMENDMENTS.md` exists to prevent.

---

## 6. Proposed tickets

Ticket IDs continue from the current maximum (MAX-173 merged; MAX-174 is this document).
Tiering follows `PROJECT_TRACKER.md`'s policy; the Haiku tier stays empty, on purpose.

### Track A — strain and load

**MAX-175 — Per-workout strain, computed at ingestion (Opus)**
A zone-weighted integral of the stored HR curve, stored once per D2. Must state its own
limits: a lift's strain is measured from HR only, which A20's reasoning already establishes
is all we get. Absence is first-class — a workout with no HR curve has no strain, and says so.
*Files:* `Sources/MaximizeCore/Domain/DerivedMetrics.swift`,
`Sources/MaximizeCore/Domain/DerivedMetricKind.swift`,
`Sources/MaximizeCore/Metrics/DerivedMetricsCalculator.swift`,
`Sources/MaximizeCore/Persistence/StoredWorkoutRecords.swift`,
`App/Persistence/MaximizeSchema.swift`, tests.
*Note:* additive optional field with a default — A8's CloudKit discipline is binding.

**MAX-176 — Strain reaches the detail view and the prompt (Sonnet)**
A summary tile, and one fact-sheet line. The fact-sheet half is a D3 decision about what
Claude sees and inherits MAX-068's `/security-review` obligation.
*Files:* `Sources/MaximizeCore/Metrics/SummaryTileData.swift`,
`Sources/MaximizeCore/Context/WorkoutFactSheet.swift`,
`App/Workouts/SummaryTilesView.swift`, tests.

**MAX-180 — Acute vs chronic load balance (Sonnet)**
Rolling 7-day and 28-day strain sums and their ratio, over stored values. A designed
absence state for the first 28 days, in the existing voice.
*Files:* new `Sources/MaximizeCore/Tallies/LoadBalanceCalculator.swift`,
`Sources/MaximizeCore/Metrics/TrendTileData.swift`, `App/Dashboard/TrendTilesView.swift`, tests.

### Track B — the muscle map

**MAX-177 — Per-muscle fatigue from the entries we already collect (Opus)**
A decay model over `MuscleGroupEntry` records: last session per group, decayed by elapsed
time, weighted by that session's duration and strain. **Must state in its own doc comment
what it cannot know** — no sets, no reps, no load (A20) — so a later ticket does not read
the model as more precise than it is.
*Files:* new `Sources/MaximizeCore/Domain/MuscleFatigue.swift`, new
`Sources/MaximizeCore/Metrics/MuscleFatigueCalculator.swift`,
`Sources/MaximizeCore/Domain/MuscleGroup.swift` (read only), tests.

**MAX-178 — Muscle-map presentation data (Sonnet)**
Per-group fatigue → a band and a non-hue channel. **Extends the existing score-band
accessibility test rather than writing a parallel one** — CLAUDE.md is explicit, and this
codebase has already found a real 1.02:1 hue-only failure.
*Files:* new `Sources/MaximizeCore/Accessibility/MuscleFatigueMark.swift`,
`Sources/MaximizeCore/Accessibility/DesignPalette.swift`, tests.

**MAX-179 — The body diagram (Sonnet)**
A six-region figure on a flat content surface (no glass over data, FR-4.2), `@ScaledMetric`
throughout, tokens only. **Needs device verification** — nothing about a drawn diagram is
provable by CI. Should also carry the honest caption about what the model does not know.
*Files:* new `App/Workouts/MuscleMapView.swift`, `App/Workouts/WorkoutDetailView.swift`.

### Track C — recovery

**MAX-181 — Daily health ingestion: a second pipeline (Opus)**
New `HealthDataType` cases (HRV SDNN, resting HR, respiratory rate, wrist temperature); a
daily observer and a **separate** anchor store, for the reason the tracker already records
about anchors and CloudKit; a new daily record in the schema. Must state plainly that this
re-presents the HealthKit permission sheet on existing installs.
*Files:* `Sources/MaximizeCore/Ingestion/HealthDataType.swift`, new
`Sources/MaximizeCore/Ingestion/DailyHealthIngestionPipeline.swift`, new
`Sources/MaximizeCore/Domain/DailyHealthSnapshot.swift`,
`Sources/MaximizeCore/Persistence/Repositories.swift`, `App/Persistence/MaximizeSchema.swift`,
`App/HealthKitWorkoutObserver.swift`, new `App/HealthKitDailySampleFetcher.swift`, tests.

**MAX-182 — Personal baselines (Opus)**
A rolling personal window per signal, with an explicit insufficient-history state. *"Not
enough history yet"* is a designed absence, in one voice, on one surface.
*Files:* new `Sources/MaximizeCore/Metrics/PersonalBaseline.swift`, tests.

**MAX-183 — The recovery score (Opus)**
Composition of the four signals against baseline into one 0–100 morning figure. **This is a
plan-data question, not a code question (D1):** the weights and thresholds belong in a
versioned plan block, exactly as the scoring rubric does, or historical recovery scores stop
being reproducible the first time the formula is tuned.
*Files:* `Sources/MaximizeCore/Domain/Plan.swift`, new
`Sources/MaximizeCore/Metrics/RecoveryScore.swift`, `Sources/MaximizeCore/Plan/StandardPlanSeed.swift`, tests.

**MAX-184 — Where recovery lives on screen (Opus)**
An IA decision, not a layout one: `RootTab`'s doc comment argues three tabs is the maximum
and gives the test a tab must pass. A fourth tab must either pass that test or the surface
goes on the Dashboard. **Recommendation: Dashboard, not a fourth tab** — recovery is a
number you consult, not a mode you inhabit, which is the same test that kept Settings out.
*Files:* `Sources/MaximizeCore/Dashboard/`, `App/DashboardView.swift`. Needs device verification.

**MAX-185 — The strain ceiling (Sonnet)**
Today's recovery-adjusted allowance, and where the day stands against it. Depends on
MAX-175 and MAX-183.
*Files:* new `Sources/MaximizeCore/Metrics/StrainCeiling.swift`, `App/DashboardView.swift`, tests.

### Track D — privacy and prompts

**MAX-186 — What the goal statements put in the prompt (Sonnet, 🔒)**
`WorkoutFactSheet` and `TrainingFactSheet` render athlete-typed free text into every prompt.
Decide the policy and enforce it in the one place D3 allows. `/security-review` required by
CLAUDE.md; the ticket must also record, in `docs/SECURITY-REVIEW.md`, the honest position on
dates (§3.5) rather than quietly adopting Helix's wording.
*Files:* `Sources/MaximizeCore/Context/WorkoutFactSheet.swift`,
`Sources/MaximizeCore/Context/TrainingFactSheet.swift`, `docs/SECURITY-REVIEW.md`, tests.

### Track E — sleep, if wanted

**MAX-187 — Sleep ingestion (Opus)** — a `HKCategoryType` read path, which is a first for
this app, added to MAX-181's daily record.
**MAX-188 — Sleep metrics (Sonnet)** — duration, efficiency, latency, stage split, weekly
debt, regularity, over MAX-187's samples.

### Documents

**MAX-189 — Amendments A25–A28 (Opus)** — see §9. Document only.

---

## 7. What to decline or defer, and why

### 7.1 Decline: the VO2max lab (H6)

A guided Cooper test is a live, timed, in-workout protocol. PRD §3 makes *"Live /
in-workout coaching. Post-workout only"* a non-goal, and `PROJECT_TRACKER.md` records that
this non-goal is now **load-bearing** rather than incidental: A14 makes *"no unattended chat
call, ever"* an invariant, so proactive/live behaviour is a decision against a written rule,
not an extension of existing work.

It also needs the Watch to be usable — nobody runs a twelve-minute maximal test holding a
phone to read a timer — which drags H15 in with it, and it implies writing a workout to
HealthKit, a third named non-goal. Three non-goals for one feature.

**The alternative that loses:** estimating VO2max passively from HR-and-pace on ordinary
runs. It loses because Apple already computes and publishes `HKQuantityTypeIdentifier
.vo2Max` from exactly that data, so we would be reimplementing Apple — PRD §13's named
anti-pattern. If the owner wants a VO2max *number* on screen, read Apple's, in one line,
and skip the lab entirely. That is a fine small ticket; it is not H6.

### 7.2 Decline: gym-equipment scan (H10)

Point a camera at a machine and get… what? Helix presumably returns exercises that machine
supports. We have no exercise library, no sets-and-reps model, and A20 forbids acquiring one
without an amendment. The scan's output would have nowhere to land. Declined not because it
is hard but because it is inert in this product.

### 7.3 Decline: nutrition logging (H12) — and this is the clearest case

The owner's word was "exactly", and this is where I think "exactly" is wrong.

PRD §3's non-goals include both *"Diet / nutrition tracking"* and *"Manual entry, editing,
or a general logging UI. **The thing being killed**."* PRD §2's north star is *"Never
hand-type a workout log row again"* with a target of **zero** manual entries.

Barcode scanning and meal photography are better manual entry, but they are manual entry as
a **core daily loop** — several taps a day, forever, or the data is worthless. This app's
entire thesis is that a loop like that decays, and that the days you skip logging are the
days worth analysing. Building the thing the product exists to kill, as a core loop, is not
a scope question; it is a contradiction.

A22 shows the shape a legitimate exception takes: **one field, on one kind of workout,
entered after the fact on a screen you are already looking at**, recorded as an amendment
that explicitly refuses to generalise. Nutrition logging cannot be scoped that way, and A20's
tripwire — *"'It is only two numbers' is how the thing the product exists to kill comes
back"* — is written about precisely this pressure.

**If the owner wants nutrition anyway, it must arrive as an amendment superseding §3 with a
scoped answer to what else the app then owes the athlete** — not as a ticket.

### 7.4 Decline: a proactive coach

If Helix's `/docs/ai-coach` describes a coach that speaks first — a morning briefing, a
nudge — that is forbidden by A14's *"no unattended chat call, ever"*, which exists for cost
discipline in a bring-your-own-key app, and by A24's finding that *"first run is a state
problem, not an interpretation problem"*. **I could not verify whether Helix's coach is
proactive [S-none].** If it is, this is a rule change with a cost the owner should price,
not a ticket.

Note the cheaper thing that is *not* forbidden: a deterministic morning summary, computed in
the core from stored numbers with no model call at all. That is MAX-184's surface, and it
delivers most of what a briefing feels like for zero tokens.

### 7.5 Defer: the energy plan (H14)

Meaningless before H1, H2 and H4 exist; it is a presentation of them. Revisit after MAX-185.

### 7.6 Defer: widgets and Live Activities (H16)

Genuinely cheap **once there is a daily number worth glancing at**. There is not one today —
a widget showing "your last run scored 82" is not a reason to build an extension. Revisit
immediately after MAX-183; at that point it is a small, well-shaped ticket.

### 7.7 Decline: Game Center and badges (H17)

Leaderboards require other people. This app has no account and one user, by design. Badges
for an athlete who reads grade-adjusted pace and aerobic decoupling misjudge the audience —
PRD §5 says the UI *"can be dense and quantitative, not hand-holdy"*, and the whole design
standard in `CLAUDE.md` is built around numerals doing the hierarchy work. This is the one
Helix feature I would call actively wrong for Maximize.

### 7.8 Decline for parity: the Apple Watch app (H15)

Argued in §4. Costs a new target, signing work on the fragile part of `docs/DEVICE-BUILD.md`,
a second UI held to the same standard, and a second surface CI cannot verify — and buys
nothing on the recommended list, because every input already arrives in iPhone HealthKit.

---

## 8. Owner decisions required — not ordinary tickets

These three make claims about a person's body and health. I am not scoping them as tickets
and I do not think an agent should decide them.

### 8.1 Physique scan (H9) — what is the app willing to assert about a body?

A photo-derived body-composition or physique assessment is a health claim delivered from an
image, with known failure modes around body image, and no ground truth to check it against.
Beyond the substance, it breaks two structural rules: an image is not a fact sheet, so it
cannot pass through the D3 context builder as designed, and it would send a **photograph of
the athlete** to a model — a categorically different disclosure from the anonymised numbers
Helix advertises and the dated metrics we currently send.

**My recommendation: decline.** If the owner wants it, it needs an amendment stating what
the app asserts and what it refuses to, and a `/security-review` on the new disclosure.

### 8.2 Bloodwork analysis (H11) — clinical interpretation

*"Upload lab results and see them in context"* is, depending on the wording, either a
reference-range lookup or medical interpretation. The distance between *"your ferritin is
below the reference range"* and *"your ferritin is low, eat more iron"* is the distance
between a table and clinical advice, and only the owner can decide which side this app sits
on. PRD §12 already deferred anomaly flags with the reasoning *"deliberately deferred; not a
diagnostic tool"* — that sentence is the existing position and bloodwork walks straight into
it.

**My recommendation: decline for now**, or take only the narrowest version (store values,
display against published reference ranges, refuse to interpret) with an amendment that says
so explicitly.

### 8.3 Menstrual cycle awareness (H13)

Not an ethics question — a scope question with one owner. Single-user app; only the owner
knows whether this applies to them. If it does, it is a well-shaped feature: HealthKit
already carries the category type, and cycle phase would be a genuine input to the plan's
ask. If it does not, building it is pure waste.

---

## 9. Amendments this proposal implies

Proposed as MAX-189, to be written into `docs/PRD-AMENDMENTS.md` if the owner accepts §5.
Drafted here as intent, not final text.

**A25 — The app measures cost, not only output.** Amends PRD §9's derived-metric
definitions and §7.3's dashboard. Records that strain, load balance, recovery and per-muscle
fatigue are in scope, and that this is a deliberate widening of what the app claims to know
rather than a set of tiles that arrived one at a time. States the boundary: the app measures
cost and reports it; it does not prescribe rest, because prescribing is what the plan does
(D1) and a plan is authored, not inferred.

**A26 — Recovery thresholds are versioned plan data.** Extends D1 to the recovery composite.
The weights over HRV, RHR, respiratory rate and temperature, and the bands over the result,
live in a plan block. Changing a weight is a new plan version, never a code change —
identical reasoning to the scoring rubric, and if it is not written down now it will be
violated by the first tuning pass.

**A27 — Daily health data is a second ingestion path, and the anchors stay separate.**
Amends A1's on-device architecture and FR-0. Records that non-workout-anchored ingestion
exists, that it has its own observer and its own anchor store for the reason
`PROJECT_TRACKER.md` already gives about anchors and CloudKit, and that the widened
permission sheet re-prompts existing installs — a real cost, stated rather than discovered.

**A28 — The prompt carries dated records, and we say so rather than claiming otherwise.**
Clarifies A5 and the §3.5 finding. Records that Maximize's Claude prompt is **not**
anonymised — it carries calendar dates and athlete-authored goal text — that this is a
deliberate choice because dated series are the product, and that the app must never adopt
"anonymised numbers only" as a claim while that is true. Names the goal-statement passthrough
as the one channel that was never examined (MAX-186), and re-states the A5 tripwire: this
whole position is conditional on the app never being distributed.

---

## 10. Summary of verdicts

| Verdict | Items |
|---|---|
| **Build** | H1 recovery · H3 strain · H4 strain ceiling · H5 load balance · H7 muscle map |
| **Adapt** | H8 AI coach (feed it the new numbers; stays reactive) · H18 privacy (close the goal-statement channel; do not adopt their wording) |
| **Defer** | H2 sleep (after H1) · H14 energy plan · H16 widgets (after H1) |
| **Decline** | H6 VO2max lab · H10 equipment scan · H12 nutrition logging · H15 Watch app · H17 Game Center |
| **Owner decision** | H9 physique scan · H11 bloodwork · H13 cycle awareness |

**One line, if only one is read:** take Helix's insight that training has a *cost* and build
the five features that measure it; decline the coverage-chasing half; and do not claim their
privacy wording until our prompt earns it.

---

## Sources

Helix claims are reconstructed from web search results only — see §0. The pages themselves
were unreachable from this environment.

- [Helix — The complete engine for an athlete](https://www.projecthelix.app/) — **blocked**, quoted via search results
- [Helix: AI Fitness Coach — App Store](https://apps.apple.com/us/app/helix-ai-fitness-coach/id6789951372) — **blocked**, quoted via search results
- `https://www.projecthelix.app/docs/ai-coach` — **blocked, and not quoted by any search result**

Maximize claims are read from this repository: `docs/PRD.md`, `docs/PRD-AMENDMENTS.md`
(A1–A24), `docs/LIFTING-SPEC.md`, `docs/CHAT-FIRST-SPEC.md`, `docs/FIRST-RUN-SPEC.md`,
`PROJECT_TRACKER.md`, `CLAUDE.md`, and the source under `Sources/MaximizeCore/` and `App/`.

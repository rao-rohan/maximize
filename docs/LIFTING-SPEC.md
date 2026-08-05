# Lifting — product specification

**Ticket:** MAX-109
**Date:** 2026-08-05
**Status:** proposal. Nothing here is built.
**Deliverable:** this document plus amendments **A16–A21** in
[docs/PRD-AMENDMENTS.md](./PRD-AMENDMENTS.md), plus §14's ticket breakdown. **No Swift
file changes in this PR.**

---

## What this document is, and what it cannot be

**I have not seen this app.** There is no Swift toolchain in this container, no simulator,
and no device anywhere in this project's CI (tracker R1, R2). Every claim below about what
the app does today is read from source — `Sources/MaximizeCore/`, `App/`, the PRD, the
amendments, MAX-090's chat-first spec. Every claim about what a lifting session's data
*looks like* is inference from HealthKit's documented surface, not from a recorded
workout. The owner is the only person who has both used the thing and lifted.

Where a conclusion depends on something I could not verify — what HealthKit records for a
strength workout in the iOS 26 SDK, whether a two-discipline calendar cell reads or turns
to mush, whether the athlete's lifting sessions produce a legible heart-rate shape at all
— it says so in the text and appears again in §15.

I separate **decisions** (where I resolved a tension and will defend it) from
**recommendations** (where I have a view and the owner should overrule me freely). Where I
am arguing against a reading in the brief, it is marked and says why.

---

## 0. The shape, in seven sentences

Lifting is not a new feature bolted onto a running app: **strength workouts are already
being captured, already being scored, and the scores are already wrong and already
immutable** (§1.0). The single structural decision is that **a day's prescription is
indexed by discipline** — the weekly template gains a second slot per weekday, a run is
judged against the run ask and a lift against the lift ask, and nothing is ever judged
against the other discipline's rubric. From that one change everything else falls out
mechanically: the plan stays one record with one version (§4), the tallies count
**obligations rather than days** (§6), and the calendar's cell gains one state rather than
a fourth visual channel (§7). Derived metrics stay one stored record, but the calculator
stops computing run metrics for lifts — because a fabricated cadence is not the same thing
as an honest absence, and the app currently fabricates one (§3). Lifting is scored on
**adherence, not volume**, because HealthKit cannot tell us what was lifted and asking the
athlete to type it is the exact thing the north star exists to kill (§8). D1, D2, D3 and D8
all survive intact; there is exactly one escalation, and it is about scores that already
exist (§11.4).

---

## 1. What I checked, and where the brief needs correcting

The overseer's brief listed seven places this reaches and asked me to confirm or correct
each. Here is that pass. Three are confirmed, three are confirmed but understated, and one
is wrong in a way that makes the problem *smaller*.

### 1.0 The finding that reframes the ticket: this is already happening

**Nothing in the pipeline filters to runs.** `HealthKitWorkoutObserver` watches
`HKWorkoutType`; `HealthKitWorkoutFetcher.coreActivityName` maps
`.traditionalStrengthTraining` to a first-class `ActivityType`;
`WorkoutIngestionPipeline` has no activity-type branch anywhere in it; and
`WorkoutSampleExtractor` fetches the heart-rate series for every workout regardless of
type. So every lift the athlete has done since MAX-033 landed is:

- **stored**, with its full heart-rate curve (MAX-034 made sample extraction
  unconditional);
- **enriched** with derived metrics computed against the *running* plan's HR cap;
- **classified** `.other` — correctly, `WorkoutClassifier` short-circuits on
  `activityType.isRun`;
- **scored**, because `StandardPlanSeed`'s final band `fallback.recorded` is
  unconditional and always matches, at **40–69 points against an effective threshold of
  70**;
- and that score is **immutable** (D8).

Two consequences worth stating before anything else. First, this ticket is not "add
lifting"; it is "stop scoring lifting as if it were running", which is a different and more
urgent shape of job. Second, **there is a live wrong-answer path with no floor on it**:
`StandardPlanSeed`'s `easy.wellOverCap` band carries *no* `.actualClassification`
condition, only `averageHeartRateBPM > cap + 8`. A hard lifting session on a day the plan
scheduled as an easy run therefore matches it and is permanently recorded as **20–45,
"Well above the easy cap for the whole run."** That is not a hypothetical about a future
feature; it is a defect in merged code, and §14's MAX-114 fixes the seed while §11.4 raises
what to do about the scores already written.

### 1.1 Classification — the brief's reading is wrong, and the truth is better

> *"Classification (§10.2, MAX-013) reads a heart-rate profile against pace to decide
> easy/hard/long."*

**It does not read pace.** `WorkoutClassifier`'s own documentation names cadence, pace and
energy as things it deliberately does not read, on the reasoning that grade-adjusted pace
is absent indoors so a rule consuming it would classify the same effort differently
depending on GPS availability. What it actually reads is (a) the fraction of the
heart-rate curve's *covered* time at or above zone 4, for hardness, and (b) *distance*
against the week's long-run arc entry, for length.

This matters twice. It means the classifier has no pace dependency to unpick for lifting.
And it means the classifier is **already discipline-safe**: line 174 is
`guard workout.activityType.isRun else { return .other }`, which fires before any heart
rate is consulted. `WorkoutClassifierTests` already pins that a
`.traditionalStrengthTraining` workout classifies `.other`.

So classification is the *least* damaged part of the system, not the most. What it does not
do is say anything useful — `.other` is the residual, and §9 argues that a discipline whose
prescription is a goal cannot be the residual.

### 1.2 Derived metrics — confirmed, and worse than stated

> *"Most are running metrics. What is the lifting equivalent?"*

Confirmed, with one correction of degree. Of the five §9 metrics, on a lift:

| Metric | On a lift, today | Honest? |
|---|---|---|
| HR drift | **nil** — gated on `classification.driftIsMeaningful`, false for `.other` | ✅ correct absence |
| Grade-adjusted pace | **nil** — no route | ✅ correct absence |
| Distance splits | **nil** — no route, no distance | ✅ correct absence |
| Time above cap | **computed**, against the *running* cap | ⚠️ a real number anchored to the wrong plan field |
| Zone splits | **computed**, against cap-anchored zones | ⚠️ same |
| Average cadence | **computed**, from step count ÷ duration | ❌ **fabricated** |

The last row is the one that matters and the brief does not mention it.
`DerivedMetricsCalculator` derives cadence from HealthKit step count over the workout's
duration with no discipline gate. A lifting session records steps — walking between racks,
to the water fountain — so the app will compute something like 20 steps/min and hand it to
a detail view that draws it against a 165–170 band, and to a fact sheet that prints it to
Claude as "Average cadence". **That is not absence-as-first-class. It is a wrong number
that looks like a measured one**, which is the exact failure mode D2 exists to prevent,
arriving through a metric nobody thought to gate.

**Is there a lifting equivalent worth computing?** §8 answers this properly. The short
version: from what HealthKit actually provides, the honest candidates are session duration,
active energy, and heart-rate *shape* — and only the first two are defensible without
validation data nobody in this pipeline has.

### 1.3 The plan record — confirmed, and the harder constraint is not the arc

> *"The plan record prescribes a weekly template of sessions against a distance arc.
> Lifting has no distance."*

Confirmed. But the arc is the *easier* half. The harder constraint, which the brief does
not name, is that **`WeeklyTemplate` is one `ScheduledSession` per weekday and
`PlanDay.scheduledSession` is singular**. `WeeklyTemplate`'s own documentation makes the
totality a load-bearing property:

> *"Every weekday has an entry — rest is an explicit `ScheduledSession`, not a missing key
> — so resolving a calendar day to its scheduled session is a total function. A partial
> template would push an 'I don't know what today is' case into the scorer, which PRD §13
> names as the load-bearing risk."*

That is the sentence §2 has to preserve while making a Tuesday able to say two things.

One piece of good news for the cost of changing it: **`PlanDay` is not stored.**
`PlanCalendar`'s documentation says storing one "would add a second source of truth with
nothing to gain" — it is resolved from the plan record on every read. And the plan record
itself is a **JSON blob** (`StoredPlan.payloadJSON`), not a column set. So the shape change
in §2 is a `Codable` compatibility problem, not a SwiftData migration.

### 1.4 The rubric — confirmed, plus a live defect

Confirmed: every band in `StandardPlanSeed` is written against a distance, an HR cap, or a
cadence band. Two additions the brief does not have:

- The `easy.wellOverCap` shadow described in §1.0. It is a merged-code defect, not a
  design tension.
- **`RubricMetric` cannot name anything a lift has that a run does not.** It is a closed
  enum of eight cases and `activeEnergyKilocalories` is not among them, even though
  `Workout` stores it. So a rubric author today literally cannot write a band about a
  lifting session's energy cost. That is a code change, not a plan version — one of the
  few places where D1's "changing a threshold is a new plan version" runs out, and it is
  exactly the shape of tracker gap P1–P4.

### 1.5 Tallies — confirmed, with two side effects nobody has counted

Confirmed: `TalliesCalculator` produces workout-days, effective-days and a streak. Three
observations:

- **A day is already effective if *any* of its workouts is** —
  `dayLedgers.contains(where: \.isEffective)`. So today, adding lifting to the record
  cannot make a day *worse*. §6 argues that this generosity is right for two attempts at
  one obligation and wrong for two separate obligations, and that the distinction is the
  answer to question 4.
- **`averageScore` is per-workout, not per-day.** Every lift scored 40–69 by
  `fallback.recorded` is currently dragging the dashboard's average-score tile down, and
  nothing on screen says why.
- **`TrendTileData`'s workout-days tile is captioned literally `"days run"`.** A cosmetic
  thing, but it is the caption the athlete reads on a day they only lifted.

### 1.6 The rest-day budget — confirmed, and it ranks lifting cheapest

Confirmed. `RestDayBudgeting.costTier` ranks `.other` as **the least costly thing to
forgive**, ahead of `.easy`. A lifting day expressed as `.other` — which is the only way to
express one today — is therefore the first day the weekly budget spends itself on. For an
athlete whose lifting is a stated goal, that is precisely backwards, and it is an argument
for §2's decision to give lifting its own `ScheduledSessionKind` rather than reusing
`.other`.

### 1.7 The context builder — confirmed, and the timing is lucky

Confirmed: `WorkoutContextBuilder` is the single assembler, A12 generalised it over a
closed subject set, and `WorkoutFactSheet` renders it. One correction of emphasis:
**MAX-095's `TrainingContext` is not built yet.** Its specified shape — "one line per
run: date, weekday, classification, scheduled session, distance, duration, average heart
rate, drift fraction, score, band" — is run-shaped, and every one of those fields except
the first three and the last two is nil for a lift. Colliding with MAX-095 *before* it is
written costs a paragraph in its brief. Colliding after would cost a rewrite. See §14's
collision list; this is the most valuable thing in it.

---

## 2. The one structural decision: the prescription is indexed by discipline

Everything else in this document follows from here.

### 2.1 The problem, stated precisely

The athlete's normal Tuesday is a run *and* a lift. The plan record can express exactly one
session per weekday. Three escapes exist and two are wrong:

- **Make the weekday's session a list.** `PlanDay.scheduledSession` becomes
  `[ScheduledSession]`, and every consumer — the rubric evaluator's `bands(for: kind)`, the
  rest-day budget's `costTier`, the calendar's `.missed(scheduledKind:)`, the verdict
  header, the fact sheet, the authoring form — has to decide what an arbitrary-length list
  means. It also breaks the totality property §1.3 quotes: an empty list is a partial
  template wearing a different hat.
- **Express the lift as a `note` on the run's session.** Free text the scorer cannot read
  and the calendar cannot draw. This is the shape that looks cheapest in a ticket and is
  worthless a week later.
- **Index the prescription by discipline.** ✅

### 2.2 Decision

> **`Discipline` is a closed, two-case core vocabulary — `.run` and `.lift`. A weekly
> template prescribes exactly one `ScheduledSession` per (weekday, discipline) pair, rest
> included and explicit. A resolved `PlanDay` therefore carries exactly two sessions. A
> workout is *only ever* evaluated against the session of its own discipline.**

Concretely:

```swift
public enum Discipline: String, Hashable, Sendable, Codable, CaseIterable {
    case run
    case lift
}

// WeeklyTemplate keeps its `entries` for the run slot and gains a second, optional set.
// PlanDay gains a total accessor rather than a bare stored session.
extension PlanDay {
    public func scheduledSession(for discipline: Discipline) -> ScheduledSession
}
```

**Why two cases and not `n`.** For the same reason `ChatSubject` is a closed set (A12): a
new discipline is a new answer to "what is this app for", and it should cost an amendment.
Cycling, swimming and mobility are not disciplines here; they are `.other` sessions inside
the run slot, exactly as they are today. This is deliberately *not* a general
multi-sport model, and §12 says so plainly.

**Why totality is preserved.** Every (weekday, discipline) pair has an entry, and the
default for the lift slot is `ScheduledSession.rest`. So `scheduledSession(for:)` is total
in both arguments, and "the plan asked for nothing" is still an explicit rest rather than a
missing key. §1.3's load-bearing sentence survives verbatim; it just now applies twice.

**Why the discipline lives on the prescription and not only on the workout.** Because the
matching has to be decidable from the plan alone for a day with *no* workout — that is what
makes a missed lift a missed lift rather than a missed something.

### 2.3 What this costs on disk: nothing, and here is why

`StoredPlan` holds a JSON-encoded `Plan`. `WeeklyTemplate.init(from:)` decodes
`entries: [Entry]`. A version-3 plan authored last month has no lift slot in its payload.

> **Rule: the lift slot decodes with `decodeIfPresent` and defaults to rest on every
> weekday.** A stored plan that predates lifting decodes to "this plan prescribed no
> lifting", which is *exactly what it meant*. There is no migration, no backfill, and no
> historical score changes — because a historical day's run prescription is byte-identical
> before and after.

That is the whole D1 argument for this change, and it is worth writing as an acceptance
criterion rather than an assumption: **MAX-111 must carry a test that a `Plan` encoded
before this change round-trips to a plan whose every lift slot is rest, and that
`RubricEvaluator` produces the identical band for the identical workout under both.**

### 2.4 What it costs in code: a compiler-visible sweep

`ScheduledSessionKind` gains `.lift`, and `WorkoutClassification` gains `.lift`. Both are
`String`-backed `CaseIterable` enums decoded from stored payloads, so adding a case is
additive on the wire — no stored record says "lift" — and *breaking* for every exhaustive
switch, which is the point. The switches the compiler will find:

`RestDayBudgeting.costTier` · `ScheduledSessionKind.init(_:)` ·
`WeeklyTemplate.scheduledRunCount` · `WorkoutClassification.driftIsMeaningful` (a
`==` chain, so it silently answers `false` for `.lift`, which is correct — but MAX-110
should convert it to a switch so the *next* case is not silently answered) ·
`ScoreCalendarFormatting`'s glyph tables · `PlanAuthoringFormatting`'s pickers.

**One ordering trap.** `costTier` returns an ordinal, and rest-day conversion outcomes
depend on the *relative* order. Inserting `.lift` anywhere without reordering the existing
cases leaves every existing comparison unchanged, so no historical day converts differently.
Reordering the existing cases would silently rewrite the calendar's past. MAX-110's brief
must say so.

Recommended tier for `.lift`: **between `.easy` and `.hard`**. A missed lift costs the
week more than a missed easy run (it is a non-fungible stimulus, the same argument the
existing comment makes for `.hard`) and less than a missed quality session or long run.
This is a training judgement I hold loosely and the owner should overrule freely.

---

## 3. Question 1 — one metric set or two?

> *"Does a lifting session get its own metric set and its own rubric, or a shared one with
> absent fields? The codebase has a strong existing stance that absence is first-class
> rather than zero — follow it or argue against it explicitly."*

### 3.1 The stance is right and it is being violated already

The codebase's stance is real and consistently applied: `DerivedMetrics`' optionality is
documented as meaningful, `ScoreCalendarDayState` has six cases rather than three,
`DistanceSplits` distinguishes "no track to cut" from "never asked" with a whole extra
boolean, and CLAUDE.md's UI standard makes absence a designed state.

But **absence and meaninglessness are different**, and the distinction is the answer here:

- **Absent** — the measurement was not taken. An indoor run has no grade-adjusted pace. A
  watch that dropped its strap has no average HR. `nil` is honest and the UI has copy for
  it.
- **Meaningless** — the measurement *can* be taken and the number does not describe
  anything. A lift's steps-per-minute. That is the cadence bug in §1.2, and `nil` is not a
  workaround for it: `nil` is the correct value, and the calculator computing something
  else is the defect.

So the honest reading of the codebase's own stance is not "share the record and let fields
be absent". It is: **a metric that cannot mean anything for this discipline must not be
computed, and the reason must be legible.**

### 3.2 Decision

> **One `DerivedMetrics` record type. Two computation paths, selected by discipline. New
> lifting metrics are additive optional fields, not a parallel record.**

- **The storage shape does not fork.** `StoredDerivedMetrics` is a column set in
  `MaximizeSchema`; new optional columns are additive and CloudKit-safe (no non-optional
  without a default), which is the discipline A8 requires be kept. A parallel
  `LiftingMetrics` record buys nothing and costs a second join, a second repository
  method, and a second thing `WorkoutDetailModel` has to remember to load.
- **`DerivedMetricsCalculator` gates by discipline.** For `.lift`: no cadence, no
  grade-adjusted pace, no distance splits — all `nil`, all for stated reasons. Time above
  cap and zone splits are the interesting pair: they are computable and they are anchored
  to the *running* cap. See §3.3.
- **`hasHeartRateData` and friends stay as they are.** A lift does have a heart-rate
  series, and it is the one rich signal we get for free.

**Why not "absent fields, shared computation" (the null option).** Because that is what
exists now, and §1.2 is what it produces.

**Why not "its own metric set" (a `LiftMetrics` type).** Because half the metrics are
genuinely shared — duration, average and maximum heart rate, active energy — and a second
type means either duplicating them or a third type holding the common ones. Two types that
must be kept in sync is the shape D2 warns about, wearing a schema's clothes.

### 3.3 The cap, and what "time above cap" means on a lift

`Plan.heartRateCapBPM` is documented as the **easy-run** ceiling. Measuring a lift against
it produces a real number with a meaning nobody asked for: a heavy set puts most people
over 150 bpm, so "time above cap" on a lift measures how hard you were working, which is
not the discipline metric it is on a run.

Two candidate answers:

- **(a) Do not compute it for a lift.** Cleanest. `timeAboveCapSeconds` and `zoneSplits`
  go `nil`/empty for `.lift`, on the grounds that the cap is a run field.
- **(b) Compute it, and let a lift rubric band use it as a session-intensity signal.**

**Recommendation: (a) for `timeAboveCapSeconds`, (b) for `zoneSplits`.** Time-above-cap is
named in §9 as "the primary easy-run discipline metric" and carrying it onto a lift invites
exactly the misreading §1.0 already produced. Zone splits are a neutral description of how
the session's heart rate was distributed, they cost nothing extra (they are computed from
the same curve), and they are the only thing in the record that could ever tell a lifting
session apart from a walk. I hold this one loosely; the owner may reasonably want neither.

**Note the D1 leak this does *not* introduce.** Zone boundaries come from
`HeartRateZoneModel.capAnchoredMultipliers`, which tracker gap **P2** already records as a
modelling choice living in code. Anchoring a lift's zones to a running cap makes P2 worse,
not different. It should be listed under P2 rather than opened as P5, and the eventual
fix — a `zones` block on a future plan version — fixes both.

### 3.4 What lifting metrics are actually worth computing

Deferred to §8, because the answer is entirely determined by what HealthKit supplies.

### 3.5 The rubric: one rubric, new bands, one new condition

> **Decision: one `ScoringRubric` per plan version, with bands that apply to lift days.
> Not a second rubric.**

The rubric is already a filtered, ordered list — `bands(for: kind)` selects by the
scheduled session's kind, and `appliesTo: [.lift]` is a band that only ever fires on a
lift day. A second rubric record would need its own thresholds, its own ordering, and its
own answer to "which one does a day with both use" — and the answer would be "both, on
different sessions", which is what one rubric with `appliesTo` already gives you.

Three code changes the rubric *vocabulary* needs (none of them a threshold, so D1 is not
touched):

| Change | Why |
|---|---|
| `RubricMetric` += `activeEnergyKilocalories` | `Workout` already stores it; it is the only measured intensity proxy a lift reliably has, and today a rubric cannot name it |
| `RubricCondition` += `.discipline(oneOf: [Discipline])` | So a band can say "this is a lift" without going through `WorkoutClassification`. Also the belt-and-braces that would have prevented `easy.wellOverCap` from ever matching a lift |
| `RubricReference` += `.scheduledDuration(fraction:)`, and `ScheduledSession` gains `durationSeconds` | A lift is prescribed in minutes, not metres. **This closes tracker gap P3** ("`Plan` records no durations at all"), which MAX-013 reported and nobody has picked up |

That P3 closure is a genuine side benefit and MAX-113 should be told to take it
deliberately rather than half of it.

---

## 4. Question 2 — one plan or two?

> *"Does D1's plan record grow a second arc, or does 'the plan' become two plans under one
> version?"*

### 4.1 Decision: one plan record, one version, one `effectiveFrom`

> **The plan stays a single versioned record. It grows a second prescription slot (§2) and,
> if a lifting progression is ever wanted, a second progression alongside `longRunArc`.
> There are never two plan records in effect on one day.**

D1's guarantee is stated in terms of *the version in effect on the workout's date*.
`Score.planVersion`, `DerivedMetrics.planVersion`, `WorkoutContextBuilder`'s coherence
check (`metrics.planVersion != plan.version`), `PlanCalendar.plan(on:)` and
`PlanAuthoringSession`'s no-back-dating rule are all singular and all lean on that. Two
plan records means:

- `Score.planVersion` becomes ambiguous, or becomes two fields;
- `PlanCalendar` becomes two calendars with independent `effectiveFrom` ordering, and
  MAX-011's no-back-dating rule has to hold across both;
- the context builder's coherence guard — the one that catches "these metrics were computed
  against a cap the plan did not have" — needs a version pair;
- and "what plan was I on in March" stops having one answer.

That is a large amount of D1 machinery spent to buy one thing: revising your lifting block
without restating your running block. And **that cost is already paid by every other field
in the record.** Changing the HR cap today authors a new version that also restates the
weekly template, the arc, the rubric and the goals. `PlanAuthoringSession` carries them
forward verbatim precisely so that restating is free. Lifting is not special.

### 4.2 The lifting arc: recommend shipping without one

`LongRunArc` is week-index → metres. Its lifting analogue is week-index → *load* or
*volume*, and §8 concludes that neither is obtainable. A progression whose target nothing
can measure produces a dashboard tile that reads `— / 12,000 kg` forever, which is worse
than no tile.

> **Recommendation: v1 ships no numeric lifting progression.** The plan expresses lifting
> as (a) lift sessions in the weekly template, with a prescribed duration and a note, and
> (b) goal statements in `PlanGoals`, which is already free text and already reaches the
> scorer and chat. If the owner overrules §8's non-spend on manual entry, a
> `LiftingArc` of week-index → prescribed weekly *sets* becomes possible, and it is
> additive to the record in the same way §2.3's slot is.

This is the largest thing I am scoping down and §12 restates it as such.

### 4.3 What "the plan accounts for lifting goals" means, then

Concretely, after this spec:

- The weekly template says *"Tuesday: easy run 8 km; and a lift, 45 minutes, lower
  body"*, and both halves are real prescriptions the app can miss.
- `PlanGoals.statements` carries the lifting goal in the athlete's own words, and it is
  already in every prompt the scorer and chat see.
- Missing the lift costs a rest-day conversion or a red day (§6, §7), which is what makes
  it a goal rather than a wish.
- Chat can answer "am I on plan" about both, because the training context carries both
  (§10).

That is the whole ask, met, without a lifting arc. If it reads thin, the thing that is
missing is measurement, not plan structure — see §8.

---

## 5. Question 3 — a day that prescribes both

Answered by §2: a day prescribing both is the normal case, not an edge case, and it is
expressed as two slots rather than a list. This section records the consequences that do
not fit elsewhere.

**Matching a workout to its ask.** `RubricEvaluator.evaluate` currently reads
`planDay.scheduledSession.kind` and filters bands by it. It becomes:

```
discipline = Discipline(workout.activityType)
session    = planDay.scheduledSession(for: discipline)
bands      = plan.rubric.bands(for: session.kind)
```

A run is never shown a lift band and a lift is never shown a run band. That single change
is what makes `easy.wellOverCap` unable to fire on a lift, independently of the seed fix.

**Two workouts of the same discipline on one day.** Unchanged, and it must stay unchanged.
A warm-up jog plus a real run is two attempts at one obligation, and the existing
generosity (`contains(where: \.isEffective)` for tallies, `bestScoredPair` for the
calendar) is right. §6 turns on keeping this distinction sharp.

**A workout of a discipline the day did not prescribe.** A lift on a day whose lift slot is
rest. This already has an answer in the rubric — `rest.ranAnyway`, `appliesTo: [.rest]` —
and it now applies per discipline, which is the correct generalisation: lifting on a
prescribed lift-rest day is a judgement about lifting, not about the run you also did.

**`Score` gains nothing.** It already stores `scheduledSession`, which is now the session
of the workout's own discipline. Provenance stays exact.

---

## 6. Question 4 — the effective day when the disciplines disagree

> *"You ran well and skipped the lift. D9's rest-day budget, the streak, and the calendar's
> colour all need one answer, and D4 colours a day by its score."*

This is the question I expect to be argued with, so here is the full reasoning.

### 6.1 Why today's rule cannot simply be extended

`TalliesCalculator.effectiveDayTally` counts a day as effective when
`dayLedgers.contains(where: \.isEffective)`. The reason, in the code's own words, is that a
day with two workouts should be "judged by its best session, not dragged down by a warmup
or a second, worse effort."

That reasoning is about **two attempts at one obligation**. Extend it unchanged to two
disciplines and it says something entirely different: *a day with two obligations is
satisfied by meeting either one.* Which makes lifting free — you can skip every lift for
sixteen weeks and your effective-day rate never moves, as long as you ran. An athlete
asking for their plan to "account for both" is asking for exactly the opposite.

### 6.2 Decision: the unit of account is the obligation, not the day

> **`EffectiveDayTally` counts prescribed sessions, not days.** A Tuesday prescribing a run
> and a lift contributes **two** to `eligibleCount`. Each is effective independently, by
> the same ledger rule as today (manual annotation where present, else the auto-score),
> against the workouts of its own discipline. Converted-to-rest obligations are excluded
> from both counts, exactly as converted days are today.

And the property that makes this safe to land:

> **On any day prescribing at most one session, per-obligation counting and per-day counting
> produce identical numbers.** Every day in the athlete's history prescribes at most one
> session, because there is only one slot. So **no historical figure moves.** That is an
> acceptance criterion for MAX-116, not a hope: the ticket must carry a fixture suite of
> single-discipline days asserting byte-identical tallies before and after.

The type's *name* is now wrong, and renaming it is part of the ticket —
`EffectiveDayTally` → something that says obligations. The public field names
(`effectiveCount`, `eligibleCount`) can stay; it is the doc comment and the tile caption
that carry the meaning.

**The tile.** FR-3.4's "effective days" tile reads `4/5`. Post-change it reads `6/8` on a
week with three lifts. That is a visible change in a number the athlete knows, and it needs
one line of copy explaining that the denominator is sessions. This is the honest cost of
the decision and I am not going to hide it behind "the semantics are cleaner".

### 6.3 The streak

The streak walks days backward, and a day is one of four things (extends / breaks /
neutral-no-ask / neutral-not-yet-judged). Generalise per obligation and roll up:

> **A day breaks the streak if *any* of its prescribed obligations was missed-and-unconverted
> or scored below threshold. A day extends the streak if it had at least one obligation and
> every obligation was met. A day with no obligations is neutral, as today.**

This is AND at the day level, deliberately, and it is the opposite of §6.1's generosity —
because those are different questions. "Was every attempt at my run good" is answered
best-of; "did I do everything the plan asked today" is answered all-of. The streak is the
second question. A streak that survives skipping every lift is not a streak of following
the plan.

A day where the lift was missed but the run was scored *below* threshold breaks it either
way, so nothing subtle happens at that intersection.

### 6.4 The rest-day budget (D9, A6)

> **Decision: the budget converts missed *obligations*, not missed days.** N per week stays
> N conversions per week. `RestDayBudgeting.costTier` gains `.lift` (§2.4). The adjacency
> rule ("a missed day next to a scheduled rest day is cheaper to forgive") generalises to
> adjacency within the same discipline's row.

Why: converting a whole day would forgive the run you also skipped, which is a budget that
buys more than it was sold for. And on a single-obligation week, obligations and days are
the same thing, so the setting's meaning is unchanged for every week in the athlete's
history — the same no-op property as §6.2, and it should be tested the same way.

**One thing this does change for the future.** A week prescribing three runs and three lifts
has six obligations against the same budget of N. If the athlete's `restDayBudget` was
chosen against a five-run week, it is now proportionally stingier. That is a settings
value, it is one number, and the fix is that the athlete changes it — but the plan screen
or settings should say what the budget is now counting. Flagged as copy work in §14.

### 6.5 What I considered and rejected

| Option | Why not |
|---|---|
| **Day-level AND, keeping days as the unit** | Simplest change, and it loses the ability to say *which* half was missed — so the calendar cannot render the difference and the rest-day budget cannot spend itself precisely. It also makes a two-obligation day exactly as expensive to fail as a one-obligation day, which under-counts the week |
| **Day-level OR (extend today's rule unchanged)** | §6.1. Lifting becomes decorative |
| **Weight the disciplines** (a run is worth 2, a lift 1) | Invents a training judgement the app has no standing to make, and puts a number in code that D1 says belongs in the plan. If it is ever wanted it is a plan field, not a constant |
| **Two separate streaks and two separate rates** | Honest, and it doubles the dashboard's tile count to answer a question the athlete asked as one question. Recommend against, but it is a defensible product and the owner may prefer it |

---

## 7. Question 5 — what the calendar cell shows

> *"It already carries a date, a state glyph and a score-band mark, and MAX-105 is adding
> the prescription. A second discipline is a fourth thing."*

### 7.1 The brief is right that this is the binding constraint

A ~42pt cell in the month grid currently carries: the date numeral, a state glyph, and
MAX-084's corner band mark. The year heatmap carries a ~6pt mark with no corner at all —
MAX-087 had to invent a *size* channel because there was no room for a shape one. MAX-105
is about to add the prescription as a substrate layer. There is no fourth channel
available, and inventing one would spend the contrast budget MAX-084 and MAX-087 both paid
real work to establish.

### 7.2 Decision: the cell does not gain a channel. It gains a state.

> **The cell shows a single day-level verdict, rolled up from the day's obligations by one
> core function. `ScoreCalendarDayState` gains one case for the mixed day, and the full
> truth lives in the VoiceOver sentence and one level down, on the day's detail.**

The roll-up rule, which is the thing that must be decided:

- **Two attempts at one obligation → best wins.** `bestScoredPair`, unchanged.
- **Two obligations → the worse verdict colours the day.** A day where the run scored
  effective and the lift was missed is not a green day.

The second rule reverses the *ordering* of one currently-explicit decision, and I want to be
precise about which. `ScoreCalendar.dayState` today says: *"A workout that actually happened
always outranks the plan's ask for the day — D4 colors by what was done, not by what was
scheduled."* That reasoning was written for a day whose single ask was rest and the athlete
ran anyway, where "what was done" genuinely is the more informative fact. It does not
transfer to a day whose *other* ask went unmet: there, "what was done" is a half-truth, and
a green cell over a skipped obligation is the calendar lying about the week.

So: **`.scored` still outranks the ask for the obligation it belongs to; it no longer
outranks a *different* obligation's miss.**

The new state, roughly:

```swift
case partiallyMet(met: ScoreBand, missedDiscipline: Discipline, scheduledKind: ScheduledSessionKind)
```

rendered on the missed side's colour with the met side's glyph — or however MAX-105's
substrate design ends up wanting it. **I am deliberately not specifying the visual.** I
have not seen the app, MAX-105 is an Opus ticket specifically because the cell's visual
budget is the hard part, and a spec that has never seen a pixel should hand that ticket a
*state*, not a drawing.

### 7.3 This is why §6 and §7 have to be decided together

The brief guessed that question 5 might decide question 4, and it is close to right — the
dependency runs the other way but it is the same edge. The tallies can count obligations
because obligations are countable. The calendar cannot draw two verdicts in one cell, so it
needs a roll-up. Both are the same fact viewed at two resolutions, and A12's rule binds:

> **The day roll-up and the obligation tally must come from one core function.** If
> `ScoreCalendar` computes "was this day fully met" one way and `TalliesCalculator` computes
> it another, the calendar and the effective-days tile will disagree about the same Tuesday
> — which is D2's drift with a colour attached. The shared resolver is an acceptance
> criterion of MAX-116 and a dependency of MAX-117.

### 7.4 The hard collision with MAX-105

MAX-105 is unstarted, Opus, and about to design a cell that draws the day's prescription as
substrate. **If it lands assuming one prescription per day, this spec's §2 invalidates its
central visual.** Two options, and the overseer must pick before dispatching either:

- **(a) MAX-105 waits for MAX-111** and is briefed with the two-slot prescription from the
  start. Costs schedule; produces one design.
- **(b) MAX-105 ships against the single-slot model** and MAX-117 revises it. Costs a
  redesign of the hardest visual in the app, twice.

**Recommendation: (a).** It is the difference between one hard design problem and the same
hard design problem solved twice, and the second solve is against a cell that already spent
its budget.

---

## 8. Question 6 — HealthKit or manual entry

> *"PRD §3 lists manual entry as a non-goal. If lifting requires it, that is an amendment
> to write deliberately — the same way A10 was — not a thing to slip in."*

### 8.1 What HealthKit gives us, and what it does not

Stated with my confidence, because this is the load-bearing factual claim in the document
and **I could not check it against an SDK from this container.**

**High confidence — HealthKit provides, for a strength workout:** start and end, duration,
active energy burned, the per-sample heart-rate series, and (uselessly) step count. The
activity types are `.traditionalStrengthTraining` and `.functionalStrengthTraining`; the
app already maps the first and drops the second into `.other` (a one-line fix, §14's
MAX-110). No route, no distance.

**High confidence — HealthKit has no representation of sets, repetitions, or external
load.** There is no `HKQuantityTypeIdentifier` for weight lifted or reps. watchOS's own
Workout app does not capture them. A third-party lifting app that records them stores them
in its own database and writes only a summary `HKWorkout` to Health.

**Moderate confidence:** `HKWorkoutActivity` (iOS 16+) lets a writing app segment a workout,
and some lifting apps use it per exercise. The segment carries a name and a time range —
not a typed set/rep/load record — so it would tell us *how many blocks of work there were*
and nothing about what was in them. Whether reading them is worth the adapter is a device
question.

**Unknown:** whether iOS 26 added anything here. My knowledge cuts off in May 2026 and this
container has no SDK to check. **The first thing MAX-112's agent should do is check the
current `HKQuantityTypeIdentifier` list for a strength-relevant addition**, and say in the
PR what it found. If Apple has shipped one, §8.3's conclusion changes and this section
should be re-read.

### 8.2 So the choice is stark

Either lifting is scored on **what was captured** — a session happened, it lasted this
long, it cost this much energy, the heart rate looked like this — or the athlete types sets,
reps and load. There is no third source.

Typing them is manual entry. PRD §3 lists it as a non-goal in the strongest terms available
in that document — *"Manual entry, editing, or a general logging UI. **The thing being
killed.**"* — and §2's north star is literally "Never hand-type a workout log row again."
It is not a non-goal like "Claude on the dashboard tab", which A10 spent because a button's
placement made it fall out. It is the product's thesis.

### 8.3 Decision: the non-goal is not spent. Lifting is scored on adherence.

> **v1 scores a lifting session on whether it happened, when, and for roughly how long —
> not on what was lifted.** The rubric bands available to a lift day are adherence bands:
> a prescribed lift performed on the prescribed day, of at least a fraction of the
> prescribed duration, scores well; a short one scores less; a missed one is a missed
> obligation handled by §6 and §7. No band references a load or a volume, because no such
> number exists in the record.

Three arguments, in order of weight:

1. **It is genuinely what the ask needs.** "Plans should account for both lifting goals and
   running goals" is, at its core, a request that skipping the lift *cost something*.
   Adherence scoring delivers exactly that, and it delivers it zero-touch.
2. **A volume rubric would be a logging app.** Once the athlete types sets and reps, the app
   owes them an exercise library, a previous-session recall, a plate calculator and a rest
   timer — because a half-built lifting logger is worse than the one they already use. That
   is a different product, and PRD §13 names scope discipline as the top execution risk
   above any technical unknown.
3. **The scoring the app *can* do for lifting is honest, and the scoring it cannot do would
   be a guess.** §9.

**The cost, stated plainly.** Adherence scoring cannot tell a hard session from a token one.
Forty-five minutes of moving light weights and forty-five minutes of a real session score
identically. Heart-rate zone splits (§3.3) give a weak signal in that direction and I would
not lean on it. If the owner's actual complaint is "my lifting is not progressing", this
design does not address it, and no design that reads only HealthKit can.

**A16's tripwire, stated so it cannot be lost:** if manual entry is ever admitted for
lifting, it must be admitted *as* an amendment that supersedes §3's non-goal, with a
scoped answer to what else the app then owes the athlete — not as a text field that
arrives inside a lifting ticket.

### 8.4 The middle path, named so it is not confused with manual entry

If the athlete already logs lifts in a third-party app that writes to Health, the app reads
that summary workout today, unchanged, with zero taps. That is not manual entry — it is
capture, and it is the product working as designed. It still yields no load data, so §8.3's
conclusion is unaffected; but it is worth saying in the PR, because "use the app you
already use and Maximize will see it" is the honest answer to "why can't I log my sets
here".

---

## 9. Question 7 — what the scorer knows about a lift

### 9.1 The scorer's architecture already handles this

`WorkoutScorer`'s design is: the rubric selects the band deterministically, the model picks
the number inside it and writes the rationale. Four reasons are documented for that split,
and the third — that the effective flag drives tallies, streaks and calendar colour, so a
free score means a hallucination breaks a streak — applies to lifting with full force.

So the question "what does the scorer know about a lift" decomposes:

- **What can a rubric band test?** `durationSeconds` (already a `RubricMetric`),
  `activeEnergyKilocalories` (new, §3.5), classification and discipline (new condition),
  and the scheduled duration as a reference (new, closes P3). That is enough to write
  adherence bands.
- **What does the model add?** The degree within the band and the one-line rationale, from
  a fact sheet that describes a lift honestly (§10).

### 9.2 Decision: the classifier does not read a lift's heart-rate profile

There *is* something readable in a lifting session's HR curve — the sawtooth of sets and
recoveries, from which one could estimate working-set count and time under tension. It is
tempting and I am recommending against it.

> **Decision: `WorkoutClassifier` answers exactly one new question for a lift — is this a
> lift session, and is it long enough not to be a fragment. It does not read the curve.**

Because: (a) nobody in this pipeline has a validated lifting HR dataset, and the classifier
is the component PRD §13 names as poisoning every downstream number when it is wrong; (b)
a peak-counting heuristic would be a modelling choice in code, which is tracker gap P1
repeated deliberately rather than inherited; and (c) the fragment test is the part that
actually pays — a mis-started or HealthKit-split lifting session reaching the scorer
produces an immutable wrong score, and `WorkoutClassifier.isFragment` already has the
shape, it just needs a *duration* floor because a lift has no distance to test. Which is,
again, P3.

**If it is ever wanted**, the honest route is: compute the peak count as a derived metric,
store it, show it on the detail screen for a few weeks, and let the athlete say whether it
matches what they did. Then it can enter a rubric. That is a later ticket and it needs data
that does not exist yet.

### 9.3 `.lift` on `WorkoutClassification`, and why not `.other`

`WorkoutClassification` is the actual-side vocabulary and `.other` is its residual —
"cross-training, strength, mobility", per `ScheduledSessionKind`'s own comment. A discipline
the plan makes goals about cannot be the residual: `Score.actualClassification` would say
`other` for the athlete's second-most-important activity, the rest-day budget would rank it
cheapest, and every band written for lifting would have to be qualified against everything
else that also lands in `other`.

> **Decision: both `ScheduledSessionKind` and `WorkoutClassification` gain `.lift`.**
> `driftIsMeaningful` stays false for it (it already is, being neither `.easy` nor
> `.long`, but MAX-110 should make that a switch rather than an `==` chain so the next case
> added is not answered silently).

`ScheduledSessionKind.init(_ classification:)` maps `.lift → .lift`, and `.other` keeps
meaning what it means today: cross-training the rubric has no opinion about.

---

## 10. What Claude is told (D3, A12)

### 10.1 The fact sheet must not describe a lift in running vocabulary

`WorkoutFactSheet.factSheet()` prints a fixed sequence: distance, classification, the HR
cap, the cadence target, time above cap, drift, average cadence, grade-adjusted pace, zone
splits. For a lift, most of those lines are the string that explains their own absence, and
two of them — the cap and the cadence target — are the *plan's running settings*, printed
under "The plan" as if they governed the session.

> **Decision: `WorkoutFactSheet` branches on discipline, inside the one module and behind
> the one entry point A12 requires.** A lift's fact sheet carries: the day and weekday, the
> type, the duration, active energy, the plan version, **the lift session prescribed for
> that day** (not the run one), the goals, average and maximum heart rate, zone splits if
> §3.3's recommendation is taken, and the heart-rate shape. It carries **no** cap line, no
> cadence line, no pace line, no distance line and no splits section — not as "—", but
> absent, because a heading that exists only to say it does not apply is prompt tokens
> spent on nothing.

This is not a second assembler and not a second renderer entry point. It is one renderer
with a discipline branch, and MAX-094's `FactSheetFormatting` (already merged) means every
figure that appears in both branches is formatted by the same function — which is A12's
rule 3, already satisfied by construction.

### 10.2 `TrainingContext` — the collision to fix before it is built

MAX-095's specified roll-up is "one line per run: date, weekday, classification, scheduled
session, distance, duration, average heart rate, drift fraction, score, band".

> **It must become one line per *session*, discipline-tagged, with the fields that do not
> apply omitted rather than nil-rendered.** And the plan block (`TrainingContext` item 1)
> must carry the weekly template's **lift** slot, or "am I on plan" is answerable about
> half the plan.

MAX-095's `maximumRenderedRuns` bound becomes a bound on sessions. §3.3's privacy argument
is unchanged in kind, but the count roughly doubles for an athlete lifting three times a
week, which is a real widening of what leaves the device per training turn and should be
said in that ticket's security review rather than discovered in it.

### 10.3 Nothing else in A12 moves

The subject set stays closed at two — lifting is not a chat subject, it is a property of
the workouts a subject already covers. One module, one entry point, one shared renderer,
no arithmetic in a context: all unchanged. **This spec does not touch A12.**

---

## 11. The invariants, and the one escalation

### 11.1 D1 — untouched

The plan stays one versioned record (§4). Every threshold added is a plan field, not a
constant: prescribed lift duration lives in `ScheduledSession`, the adherence fraction lives
in a `RubricReference`, the bands live in the rubric. Stored plans decode with their lift
slot defaulted to rest, so no historical prescription changes and no historical score
becomes irreproducible (§2.3).

Two D1 *leaks* are touched and both improve: **P3 closes** (§3.5), and **P2 gets worse in
degree but not in kind** (§3.3) and should be recorded against the existing gap rather than
opened as a new one.

### 11.2 D2 — untouched, and one violation repaired

Lifting metrics are computed at ingestion and stored, like everything else. The repair is
§1.2's fabricated cadence: a number computed from real samples that describes nothing is
the same failure D2 exists to prevent, and it is currently reaching both a chart and a
prompt.

### 11.3 D3 / A12 — untouched

§10. One module, one entry point, one renderer with a discipline branch, closed subject set.

### 11.4 D8 — untouched, and here is the escalation

> **Escalation to the overseer. I am not deciding this.**

Every lifting session already ingested carries an immutable auto-score produced by applying
a running rubric to it (§1.0) — either 40–69 from `fallback.recorded`, or 20–45 from
`easy.wellOverCap` with the rationale "Well above the easy cap for the whole run." Those
scores are in the average-score tile, in the calendar, and in the chat context.

D8 forbids overwriting them, and D8's reason is that the auto-versus-manual divergence *is*
the scorer-quality signal (PRD §2). But these are not scorer misjudgements. The model was
handed a category error and did its job. Counting them as scorer error corrupts the very
telemetry D8 protects — in the opposite direction from the one D8 worries about.

The options, none of which I am taking:

| Option | Consequence |
|---|---|
| **Leave them, unmarked** | The average-score tile stays wrong forever and nothing explains why |
| **Leave them, marked** | The verdict header and the calendar's VoiceOver sentence say "scored before the plan distinguished lifting". Costs one string and a stored-score-predates-`.lift` test. D8-clean |
| **Annotate them** | Additive, D8-compliant *by the letter* — and it is manual, it is a lie about what an annotation means (a human correction), and it poisons the correction-rate metric worse than leaving them |
| **A narrow, recorded exception to D8** for scores whose `scheduledSession.kind` and workout discipline disagree | Honest. Also the first crack in an invariant that has held all project |

**My lean is option 2**, and I want to be clear that it is a lean: it is cheap, it changes
no stored record, and it makes the wrongness legible rather than resolved. But this is the
owner's or overseer's call, not a ticket's, and §14 files it as MAX-125 with no code in it.

### 11.5 D4 and D9 — refined, and the refinement is on the record

D4 ("calendar coloured by score") and D9 (the rest-day budget) are not in the brief's
untouchable set, and this spec does move them: D4's day-level roll-up gains a mixed state
(§7.2), and D9's budget spends on obligations rather than days (§6.4). Both are recorded
as amendments (A19) rather than left as ticket-level decisions, because both change a
number the athlete already reads.

---

## 12. What I am scoping down, and what I refuse

**Scoped down, deliberately:**

- **No numeric lifting progression in v1** (§4.2). The plan prescribes lift sessions and
  states lifting goals; it does not ramp a load curve, because nothing can measure one.
- **No lifting classification from the heart-rate curve** (§9.2). The fragment test only.
- **No per-exercise anything.** No exercise library, no muscle-group model, no
  `HKWorkoutActivity` segment reading in v1.
- **No second dashboard.** Lifting shares the calendar, the tiles and the trend interval.
  Two disciplines is not two dashboards.

**Refused, with reasons:**

- **A general multi-sport model.** `Discipline` is two cases and closed (§2.2). Cycling and
  swimming stay `.other` sessions in the run slot, which is what they are today. A third
  discipline should cost an amendment, not a ticket, for the same reason A12 closes the
  chat subject set.
- **Manual set/rep/load entry** (§8.3), unless the owner overrules — in which case it is
  A16's tripwire and a re-scoped product, not a text field.
- **Weighting the disciplines against each other** (§6.5). A number in code that decides
  how much a lift is worth relative to a run is a threshold, and D1 says thresholds are
  plan data.

**If the owner thinks the ask should be smaller still**, the smallest coherent version of
this document is §2 plus §3 plus §5 — the discipline index, the metric gating, and matching
a workout to its own ask — with §6 and §7 deferred and today's day-level OR left in place.
That delivers "lifting is no longer scored as a bad run" without changing any number the
athlete already reads. It does **not** deliver "the plan accounts for lifting goals",
because skipping a lift would still cost nothing. Named here so the trade is visible.

---

## 13. Amendments

Drafted into [docs/PRD-AMENDMENTS.md](./PRD-AMENDMENTS.md) in this PR:

| # | Supersedes / adds | In one line |
|---|---|---|
| **A16** | §3 non-goal "Strength-training analysis… deferred, possibly permanently"; §12's deferral of strength scoring | Lifting is in scope. The non-goal is spent deliberately, and the manual-entry half of it is **not** spent |
| **A17** | Amends D1's plan shape and §8's `plan_day` | The prescription is indexed by discipline: one plan record, one version, two slots per weekday, totality preserved |
| **A18** | Amends §9 | A metric that cannot mean anything for a discipline is not computed. Absence and meaninglessness are different, and the app currently confuses them |
| **A19** | Amends FR-3.4, D9, and D4's day roll-up | Effective days count obligations, not days; the rest-day budget spends on obligations; a day's colour is its worst obligation |
| **A20** | Reaffirms §3's manual-entry non-goal against new pressure | Lifting is scored on adherence, not volume, because HealthKit carries no load — with the tripwire for the day that changes |
| **A21** | Clarifies D8 | Scores written before the plan distinguished lifting stand. They are labelled, not corrected — pending the §11.4 escalation |

**A16 deserves the same note A10 got.** `PROJECT_TRACKER.md`'s "Deliberately not built"
list names strength analysis, and that list exists "so nobody helpfully adds one". This
amendment is the deliberate spend, and it is written narrowly on purpose: it spends
*strength-training scoring*, and it explicitly does not spend *manual entry*, which the
same PRD sentence group also protects. A future ticket that adds a sets-and-reps field
should be refused on A20's authority.

---

## 14. Proposed ticket breakdown

Ordered. Each is one agent's work. Files are named so the overseer can see collisions; ⚠️
marks a file two tickets both touch. 🔒 = `/security-review` before merge, per CLAUDE.md.

| # | Ticket | Scope, one line | Files | Depends on | Tier |
|---|---|---|---|---|---|
| **MAX-110** | `Discipline`, and `.lift` on both enums | The closed two-case vocabulary; `.lift` on `ScheduledSessionKind` and `WorkoutClassification`; `ActivityType.discipline`; map `.functionalStrengthTraining`; the compiler-visible switch sweep **without reordering `costTier`** | new `Domain/Discipline.swift`; ⚠️ `Domain/ScheduledSession.swift`, ⚠️ `Domain/Workout.swift`, ⚠️ `Domain/RestDayBudgeting.swift`, `App/HealthKitWorkoutFetcher.swift`, `App/Dashboard/ScoreCalendarFormatting.swift`, `App/Plan/PlanAuthoringFormatting.swift`, tests | — | **Opus** |
| **MAX-111** | The per-discipline prescription | `WeeklyTemplate` gains the lift slot; `PlanDay.scheduledSession(for:)`; `PlanCalendar` resolution; **the `decodeIfPresent` no-op test is an acceptance criterion** | ⚠️ `Domain/Plan.swift`, `Domain/PlanCalendar.swift`, ⚠️ `Domain/ScheduledSession.swift`, `Persistence/StoredPlanRecords.swift`, tests | 110 | **Opus** |
| **MAX-112** | Discipline-gated derived metrics | Stop computing cadence / GAP / splits for a lift; decide time-above-cap and zone splits per §3.3; new optional lift fields + schema columns | `Metrics/DerivedMetricsCalculator.swift`, ⚠️ `Domain/DerivedMetrics.swift`, `Persistence/StoredWorkoutRecords.swift`, ⚠️ `App/Persistence/MaximizeSchema.swift` | 110 | **Opus** |
| **MAX-113** | Rubric vocabulary for lifts | `RubricMetric` += energy; `RubricCondition` += `.discipline`; `RubricReference` += `.scheduledDuration`; `ScheduledSession.durationSeconds` — **closes tracker gap P3** | `Domain/ScoringRubric.swift`, ⚠️ `Domain/ScheduledSession.swift`, ⚠️ `Domain/DerivedMetrics.swift` (`value(for:)`) | 110 | **Opus** |
| **MAX-114** | Seed bands for lift days, and the `easy.wellOverCap` shadow | Adherence bands for `.lift`; add the missing `.actualClassification` guard to `easy.wellOverCap`. **Must state in the PR that fixing the seed does not fix a stored plan** | `Plan/StandardPlanSeed.swift`, tests | 113 | Sonnet |
| **MAX-115** | Match a workout to its own discipline's ask | `RubricEvaluator` resolves the session by discipline; `WorkoutScorer`'s guards follow | `Scoring/RubricEvaluation.swift`, `Scoring/WorkoutScorer.swift` | 111, 113 | **Opus** |
| **MAX-116** | Obligations, not days | Tallies, streak and rest-day budget count obligations; **the shared day-roll-up resolver §7.3 requires**; byte-identical fixtures for single-discipline history | `Tallies/TalliesCalculator.swift`, `Domain/Tallies.swift`, ⚠️ `Domain/RestDayBudgeting.swift` | 111, 115 | **Opus** |
| **MAX-117** | The calendar's mixed day | `ScoreCalendarDayState` gains the partially-met case; the roll-up reads MAX-116's resolver, never its own | ⚠️ `Dashboard/ScoreCalendar.swift`, `App/Dashboard/ScoreCalendarFormatting.swift`, `App/Dashboard/ScoreCalendarView.swift` | 116, **MAX-105** | **Opus** — needs device |
| **MAX-118** | Context and fact sheet learn discipline | The lift branch of `factSheet()`; the builder selects the day's lift session; no cap/cadence/pace headings on a lift | `Context/WorkoutFactSheet.swift`, `Context/WorkoutContext.swift`, `Context/WorkoutContextBuilder.swift` | 111, 112 | **Opus** 🔒 |
| **MAX-119** | Plan authoring for two slots | `PlanDraft` gains the lift week; the authoring screen gets a second row set without becoming unusable | `Plan/PlanDraft.swift`, `Plan/PlanAuthoring.swift`, ⚠️ `App/Plan/PlanAuthoringModel.swift`, ⚠️ `App/Plan/PlanAuthoringView.swift`, `App/Plan/PlanAuthoringFormatting.swift` | 111 | Sonnet — needs device |
| **MAX-120** | The plan screen shows both | `PlanDisplayData` carries the lift week; the read-only screen renders it; the rest-day budget caption says what it now counts | `Plan/PlanDisplayData.swift`, ⚠️ `App/Plan/PlanView.swift`, `App/Plan/PlanDetailSections.swift`, `App/Plan/PlanFormatting.swift` | 111 | Sonnet |
| **MAX-121** | Workout detail for a lift | No cadence band, no route, no splits, no cap line — and what stands in their place; verdict header reads the lift ask | `Metrics/SummaryTileData.swift`, `Domain/WorkoutVerdict.swift`, `App/Workouts/WorkoutDetailView.swift`, `App/Workouts/VerdictHeaderView.swift`, `App/Workouts/SummaryTilesView.swift` | 112, 115 | Sonnet — needs device |
| **MAX-122** | Trend tiles, honestly | Effective-days caption says sessions; "days run" caption fixed; decide whether average score is per-workout or per-obligation | `Metrics/TrendTileData.swift`, `App/Dashboard/TrendTilesView.swift` | 116 | Sonnet |
| **MAX-123** | `PlanProposal` covers lift days | The proposal type and its generated schema description gain the lift slot; the enum-coverage test catches it automatically | `Plan/PlanProposal.swift` (from MAX-099) | 111, **MAX-099** | Sonnet 🔒 |
| **MAX-124** | `TrainingContext` is per-session, not per-run | MAX-095's roll-up gains discipline; the plan block carries the lift week; the bound counts sessions | `Context/TrainingContext.swift` (from MAX-095) | 111, **MAX-095** | **Opus** 🔒 |
| **MAX-125** | **Decide what to do with lifts already scored as runs** | §11.4's escalation. No code until it is decided; my lean is the label | — (then a string + a test) | 110 | Owner / overseer |

**110–116 and 118 are core-only and CI-verifiable end to end. 117 and 119–122 are
App-layer, which CI compiles and never executes** (tracker R13) — every one of those PRs
needs a *Needs device verification* list.

### Collisions, called out

- **MAX-105 must land before MAX-117, and must be briefed with §2's two-slot prescription
  before it is dispatched at all.** This is the most expensive collision in the set: MAX-105
  is designing the calendar cell's substrate right now, and a one-prescription substrate is
  the wrong design. See §7.4 for the two options and why (a) wins.
- **MAX-095 must be briefed with §10.2 before it is written.** Its "one line per run"
  roll-up becomes "one line per session". Colliding before it exists costs a paragraph;
  colliding after costs a rewrite of an Opus 🔒 ticket. MAX-124 exists only if 095 lands
  first and unbriefed.
- **`Domain/ScheduledSession.swift` is touched by 110, 111 and 113.** Strictly sequence
  them; they are already in dependency order.
- **`Domain/RestDayBudgeting.swift` is touched by 110 (the `costTier` case) and 116 (the
  obligation change).** 110 must add the case *without reordering*, and its PR should say
  so explicitly — a reorder silently rewrites the calendar's past.
- **`App/Plan/` is touched by 119 and 120.** Different files, but 120 will want to link into
  the authoring screen; sequence 120 first, it is the smaller and read-only one — the same
  ordering the chat-first spec used for 101/102.
- **MAX-104 (copy and absence voice, app-wide) must run after 117–122**, or it will do the
  pass twice. Its brief already says it absorbs MAX-086's half; it should absorb the lifting
  surfaces too rather than a MAX-124-style follow-up existing.
- **Every agent branch rebases onto `main` before its PR opens**, per the tracker's MAX-012
  process note.

### Suggested order

**MAX-105 first, briefed** (§7.4). Then the core spine, strictly sequential because each
link changes a type the next one reads: **110 → 111 → (112 ‖ 113) → 114 → 115 → 116 → 117**.

**118 parallelises with 116/117** once 112 lands. **119 and 120 parallelise with each other
after 111** (120 first). **121 and 122 are last** and parallelise freely. **123 and 124**
depend on chat-first tickets that are not merged and should be folded into those tickets'
briefs rather than dispatched separately if they have not started.

**MAX-125 is a conversation, not a ticket**, and it should happen before 117 — because
whether a historically-mis-scored day is labelled changes what the calendar has to draw.

---

## 15. What I am deliberately not deciding

| # | Question | Who should decide | My lean |
|---|---|---|---|
| 1 | **Whether iOS 26's HealthKit added any strength-relevant quantity type.** The whole of §8 turns on the answer | Whoever builds MAX-112, against a real SDK | Check it first and say what you found in the PR. If it exists, §8.3 is re-opened, not worked around |
| 2 | **Whether a lift should carry time-above-cap and zone splits at all** (§3.3) | Owner | Zone splits yes, time-above-cap no. Held loosely — "neither" is defensible |
| 3 | **Where `.lift` sits in `RestDayBudgeting.costTier`** (§2.4) | Owner — it is a training judgement | Between `.easy` and `.hard`. I have no standing here |
| 4 | **Whether the effective-days tile should split into two** (a run rate and a lift rate) rather than one obligation rate (§6.5) | Owner | One rate. Two tiles answers as two questions what was asked as one — but this is taste and the dashboard has room |
| 5 | **Whether the mixed calendar cell reads at all**, and what it should look like | MAX-105 / MAX-117, on a device | Not specifiable from here. §7.2 hands over a *state*, not a drawing, on purpose |
| 6 | **What a lifting session's heart-rate curve actually looks like** on this athlete's watch, and whether a set-count heuristic would work | Later, with data | Defer (§9.2). Compute it, show it, ask the athlete, *then* consider a rubric band |
| 7 | **Whether the scores already written for lifts are labelled, left, or excepted from D8** (§11.4) | **Overseer / owner — this is the escalation** | Label them. But it is a decision about an invariant and a ticket must not make it |
| 8 | **Whether the whole thing should be scoped to §12's smaller version** (discipline index + metric gating only, no tally change) | Owner | Ship the full version. The smaller one fixes the wrong scoring but leaves lifting costless, which is the half the ask is actually about |
| 9 | **What the plan screen should say the rest-day budget now counts** (§6.4) | MAX-120, with copy from MAX-104 | One line under the setting. The number's meaning changed for two-discipline weeks and silence about it is the MAX-047 defect in a new place |

And one thing explicitly *not* left open: **nothing in this design requires moving D1, D2,
D3 or D8.** D4 and D9 are refined and recorded (A19). The single escalation is §11.4, and
it is about records that already exist rather than about anything this spec proposes to
build. If an implementing ticket concludes otherwise, that is an escalation to the overseer,
not a change to make.

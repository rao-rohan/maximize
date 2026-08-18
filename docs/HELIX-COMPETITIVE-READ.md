# Helix — a competitive and strategic read

**Ticket:** MAX-174
**Status:** Assessment, for the owner's decision. **No source is changed by this document.**
**Supersedes:** the brief this ticket was opened under, which asked for a path to feature
parity. See §0.2.

---

## 0. Provenance — three layers of evidence, and what each is worth

This document has an unusual evidence problem and it is worth stating before anything else,
because two of its three layers are not mine.

### 0.1 The three layers

**Layer 1 — the owner's reading of Helix's own pages. Not verified by me.**
Everything in §1 and §2 comes from the owner, who fetched the docs, privacy, recovery and
App Store pages that this environment cannot reach. **All three URLs are blocked by the
network egress proxy here** — `https://www.projecthelix.app/docs/ai-coach`,
`https://www.projecthelix.app/`, and the App Store listing — confirmed with both WebFetch
and curl, each returning `EGRESS_BLOCKED` rather than a 404 or a paywall. I did not retry
after being told not to. Where this document says something about Helix, it is reporting the
owner's finding, and it says so.

**Layer 2 — web search. Weak, and used only for corroboration.**
Before the owner's findings arrived I reconstructed Helix's feature list from search, which
returned what reads as near-verbatim marketing copy, recurring across independent queries.
That reconstruction survives as the feature column in §3, because it corroborates the
owner's account rather than contradicting it. It is still second-hand and it is marked as
such.

**Layer 3 — this repository. Verified by me, and the only layer I can vouch for.**
Every claim about Maximize is read from `docs/PRD.md`, `docs/PRD-AMENDMENTS.md` (A1–A24),
`PROJECT_TRACKER.md`, `CLAUDE.md`, and the source under `Sources/MaximizeCore/` and `App/`.
**§5 is where this matters most: one of the three "we don't have this" claims handed to me
turned out to be wrong, and I found it by reading the code.**

### 0.2 What changed about this ticket

The brief asked for a parity PRD — a feature-by-feature path to matching Helix. The owner's
own analysis argues parity is the wrong goal. This document's job is now to make or refute
that case. **It makes it.** The feature comparison table is kept, because it remains the
useful spine, but it now feeds a build/decline judgement rather than a backlog.

---

## 1. What Helix is — the owner's reading

Attributed in full to the owner. I have verified none of it.

- An **iOS/watchOS Whoop clone**. Reads HealthKit; computes recovery, strain, sleep and
  stress on-device against **rolling two-month personal baselines**; puts an LLM chat coach
  on top.
- **Free with Pro at $9.99/mo or $59.99/yr** ($34.99 promotional). **v1.8.1**, shipping
  fast. Requires **iOS 26**.
- Built by **Wyreframe Labs (OPC)**, a one-shareholder Bengaluru company whose other
  apps are Snake Identifier, Mushroom Identifier, AI Food Scanner and Bento AI Calorie
  Tracker. A high-velocity AI-wrapper studio.
- **Near-zero traction.** The App Store listing has too few ratings to display a rating
  overview at all — while a large SEO content operation ("Is WHOOP worth it?", "best WHOOP
  alternatives") runs at full tilt. The acquisition funnel is being built before the product
  has users.
- The eight-person **"editorial masthead" has zero photos, credentials or external links
  across all eight names**. The owner's read, which I find persuasive on the facts as
  described: near-certainly LLM-generated E-E-A-T persona construction.

Search corroborates the product surface — *"the complete engine for an athlete"*, recovery
from HRV/resting HR/respiratory rate/wrist temperature against a personal rather than
population baseline, per-workout strain from heart-rate load, a recovery-adjusted daily
strain ceiling, acute-vs-chronic load balance, sleep including regularity and debt, a VO2max
lab with a guided Cooper test, a strength lab with per-muscle fatigue and a muscle map, an
AI coach on OpenAI and Claude, physique and gym-equipment scans, bloodwork, nutrition
logging with barcode and meal photos, cycle awareness, an energy plan, a Watch app with
widgets and Live Activities, and Game Center leaderboards.

**One thing worth naming about that list: it is very long for v1.8.1 from a studio whose
back catalogue is single-purpose identifier apps.** Breadth at that velocity is a claim
about how much of each feature is real. I cannot check it, and neither could the owner
without using the app.

---

## 2. Three claims the owner tested

These are the owner's findings and reasoning. I report them because they change the
strategic read; I have independently verified none of them.

### 2.1 "No backend" is not true as stated

The coach calls OpenAI and Anthropic. Either the keys are embedded in a 36.5 MB client —
trivially extractable, and a terms-of-service problem — or a relay sits in front of them,
**which is a backend**. There is no third option.

The privacy page says nothing is stored server-side *by Helix*. That phrasing carefully
excludes what OpenAI and Anthropic retain, and **both default to roughly 30-day
abuse-monitoring retention**. The page never mentions this.

**Why this matters to us, and it is not schadenfreude.** A1 deleted our backend for a
reason, and A5 records the exact cost of doing so: the Anthropic key lives in Keychain, on
device, *"acceptable only because the app is single-user and never distributed"*, with an
explicit tripwire. **Helix appears to have taken the same shortcut without the tripwire, at
distribution scale.** Our position is the more honest one only because A5 wrote down what it
was buying and what it would cost to ship. That written-down-ness is the whole difference,
and it is worth more than any feature in §3.

**It also means their headline differentiator is weaker than ours, not stronger.** "No
backend" for an app making per-user LLM calls at scale is a claim about where a database is,
not about where the data goes.

### 2.2 The App Store "Data Not Collected" label is weak evidence

Apple exempts data sent for a real-time request and not retained. The label therefore tells
you nothing about the LLM round-trips — which is precisely the part a privacy-conscious
athlete would want to know about. **Noted here as a caution against Maximize ever leaning on
the same label as evidence of anything.** If we ever ship, "Data Not Collected" is not a
defence of our prompt contents, and §5.4 is where our prompt contents actually stand.

### 2.3 The recovery score's learning loop is methodologically contaminated

The athlete rates how a day felt; the model re-weights the recovery score against that
rating. But **the athlete has already seen the score before rating the day.** A 34 in the
morning primes a worse subjective report; the model then learns its weighting was correct.

The loop is self-confirming, trained on anchored labels, with an unpublished weighting, and
it is unfalsifiable — there is no way for the model to be told it was wrong. The owner notes
Whoop and Oura do the same thing; Helix is simply louder about it.

**This is the sharpest finding in the set, and §6 turns it into a rule for us.**

---

## 3. Feature comparison — kept as the spine

The Helix column is Layer 1/2 (unverified). The Maximize column is Layer 3 (verified).

| Helix capability | Maximize today | Verdict |
|---|---|---|
| **Morning recovery score** from HRV, resting HR, respiratory rate, wrist temperature vs rolling personal baseline | Nothing. `HealthDataType` authorises exactly six types — workout, heart rate, distance, active energy, steps, route. No daily-health record type exists in `MaximizeSchema` at all | **Defer** — see §4.2 and §8.1 |
| **Per-workout strain** from HR load | Adjacent but different. We compute average/max HR, time-above-cap, HR drift, zone splits, grade-adjusted pace, cadence, distance splits, and a plan-relative 0–100 effectiveness score. We measure *did you execute the ask*; they measure *what did it cost* | **Build** — §9, MAX-176/177 |
| **Recovery-adjusted daily strain ceiling** | Nothing; our plan prescribes sessions, not a daily load allowance | **Defer** — depends on recovery |
| **Acute vs chronic load balance** | Nothing. `TalliesCalculator` counts obligations, effective days, streak, average score — no load figure exists to ratio | **Build** — falls out of strain, §9 MAX-178 |
| **Sleep**: stages, efficiency, latency, debt, regularity | Nothing. Sleep is not read anywhere | **Decline for now** — §8.1 |
| **VO2max lab**, guided Cooper test | Nothing, and it is a different product mode. PRD §3 non-goals: live/in-workout coaching, *and* writing to HealthKit. Needs a Watch to be usable | **Decline** — §8.2 |
| **Per-muscle fatigue + muscle map** | Closest of anything here. `MuscleGroup` is a closed six-case core vocabulary; A22 has the athlete tagging groups per lift; `MuscleGroupEntryRecord` is in the schema; A17 lets a plan prescribe groups | **Build, narrowly** — §9, MAX-179/180, and read §5.3's warning first |
| **AI coach that reads your numbers** | We have this, and on the evidence a better-disciplined version: streaming chat (D10), per-subject threads (A11/A12), **one** context builder feeding scorer and chat (D3), Claude-drafted plan proposals (A13), Ask on every screen (A10), a hard no-unattended-call rule (A14) | **Already ahead** — §5 |
| **Physique scan** | Nothing | **Decline** — §8.3 |
| **Gym-equipment scan** | Nothing, and no exercise library for its output to land in (A20) | **Decline** — inert here |
| **Bloodwork analysis** | Nothing. PRD §12 already deferred anomaly flags as *"not a diagnostic tool"* | **Decline** — §8.3 |
| **Nutrition logging**, barcode + meal photo | Nothing, and doubly excluded: PRD §3 non-goals list *"Diet / nutrition tracking"* **and** *"Manual entry, editing, or a general logging UI. The thing being killed"* | **Decline** — §8.4, the clearest case |
| **Menstrual cycle awareness** | Nothing | **Decline for this athlete** — §8.5 |
| **Energy plan** — schedules the day | Nothing; our plan is a weekly prescription by (weekday, discipline) | **Decline** — presentation of features we are not building |
| **Standalone Watch app**, widgets, Live Activities | No Watch target. `project.yml` builds one iOS app target plus the core package | **Decline** — §8.2 |
| **Game Center, badges** | Nothing, pointedly. PRD §5: the UI *"can be dense and quantitative, not hand-holdy"* | **Decline** — leaderboards need other people; this app has one user by design |
| **"No backend, on-device, anonymised numbers"** | A1 is the same architecture, arrived at independently and **with the cost written down** (A5's tripwire). We call one provider; they call two. But our prompt is **not** anonymised — see §5.4 | **We are ahead on substance, behind on one specific** |

**Four Build verdicts out of seventeen.** That is the document's actual conclusion, and §7
explains why it is the right number rather than a failure of ambition.

---

## 4. What our architecture makes cheap, and what it makes expensive

### 4.1 Cheap: anything computed from a stored HR curve

D2 computes derived metrics once at ingestion and stores them; D7 stores the HR series as a
blob on the workout. `DerivedMetricsCalculator` already walks that array five times —
average, maximum, time-above-cap, drift halves, zone splits.

**Strain is a sixth walk of the same array.** One optional field on `DerivedMetrics`
(additive, defaulted — A8's CloudKit discipline is binding), one calculator function, one
`DerivedMetricKind` case so absence stays first-class per A18, one fact-sheet line, one tile.
Pure Swift in the core, which means CI proves it end to end. **Load balance is then
arithmetic over stored strain**, in exactly the shape `TalliesCalculator` already has.

This is why strain and load balance are the only two unreserved Builds in §3: they are the
Helix ideas that cost us almost nothing because we already store the input.

### 4.2 Expensive: everything daily rather than per-workout

Every ingestion path in this app is **anchored to a workout**. `HKObserverQuery` watches
`HKWorkoutType`; `WorkoutQueryAnchor` persists a position in *workout* change history; every
request in `WorkoutSampleFetching` is `(workoutID, windowStart, windowEnd)`; every record in
`MaximizeSchema` is keyed by a workout UUID, a plan version, or a day override. **There is no
record type that means "here is a day."**

Recovery and sleep are daily facts that exist on days with no workout. Concretely they need:
four to six new `HealthDataType` cases (which **re-presents the HealthKit permission sheet
on existing installs** — the exact cost `HealthDataType`'s own doc comment says the route
type was bundled early to avoid); an `HKCategoryType` read path we have never had; a second
observer with a **separate** anchor store, for the reason `PROJECT_TRACKER.md` already
records at length about anchors and CloudKit; a new daily record type, re-opening MAX-169's
additive-schema question; a rolling baseline model with a defined insufficient-history state;
and a new surface, on an app whose `RootTab` doc comment argues three tabs is the maximum.

**That is approximately the size of the original ingestion phase, done again.** §8.1 is why
that is not obviously worth it here.

### 4.3 Off-shape: live protocols and camera work

A guided Cooper test is not a hard algorithm; it is a different product mode. Post-workout-
only is a PRD §3 non-goal that `PROJECT_TRACKER.md` now records as **load-bearing** rather
than incidental, because A14 made "no unattended chat call, ever" an invariant. Scans break
a different rule: every Claude call today goes through one context builder rendering a
deterministic text fact sheet from stored numbers (D3/A12). **An image is not a fact sheet**,
and there is no branch for one.

---

## 5. The three things worth taking — checked against the code

I was asked to verify three items rather than accept them. **Two check out. One does not,
and the correction matters.**

### 5.1 The frozen verdict — ✅ we already have it, as D8

**Confirmed, and it should not be proposed as new work.** PRD §4's D8 makes the auto-score
canonical and immutable; manual disagreement is an *additive* `ScoreAnnotation`, never an
overwrite. `ScoreRecord` and `ScoreAnnotationRecord` are separate types in `MaximizeSchema`,
and the schema's own comment notes nothing on the annotation path can reach a score.

Better than that, we have already **defended** the rule under pressure. A21 handles lifts
scored before the plan distinguished lifting: the obvious fix was to rescore them, and the
project explicitly declined, adding a third record type (`MiscategorisedScoreLabelRecord`)
so those scores could be excluded from the scorer-quality metric **without anything being
written to a score**. A21's own words: that is *"a stronger position than a narrow exception,
not a weaker one."* And `ChatModel.trainingTask` closes the loop from the model's side —
Claude is instructed never to re-score a session or offer a score of its own.

So: Helix's frozen-verdict rule is a rule we hold, hold more strictly, and have already paid
to keep. Nothing to build.

### 5.2 "No score" beats a fabricated score — ✅ we behave this way, ❌ it is not written down

**Confirmed as described.** The behaviour is real and repeatedly chosen:

- **MAX-130** stopped `DerivedMetricsCalculator` deriving cadence for lifts. A18 records the
  reasoning in the sharpest available terms: a steps-per-minute figure for someone walking
  between racks, drawn against a running band, is *"a fabricated number that looks
  measured"*.
- **MAX-136** has a lift's fact sheet omit the cap, cadence, pace and splits lines outright
  rather than render them as "—", and say once why the page is short — *"so it cannot reason
  from the shortness."*
- **MAX-168** kept the lift-scoring gate closed rather than score real lifts against a
  rubric that calls them runs, and it declined to open even after being unblocked, because
  the corrected bands were not yet in effect on the device.
- **A22** invented a third state — *awaiting the athlete* — rather than score a lift before
  the muscle groups arrive.
- **A18** draws the distinction the whole rule rests on: *absent* (not measured) and
  *meaningless* (measurable, describes nothing) are different, and only the first is a `nil`.

**But it has never been stated as an invariant**, and that is the real gap. It is four
independent good decisions, not a rule a fifth ticket inherits. **The coordinator is
dispatching this as MAX-175; I am not duplicating it.** What I would add to that ticket from
this reading: A18 already contains the sentence the invariant should be built out of, and
the strongest form is a test over the *set* of model-facing prompts and metric kinds, not
prose in a doc comment — because prose is exactly what we have four copies of already.

### 5.3 Honest refusal in the context builder — ⚠️ **the claim as given is wrong**

I was told: *"I checked: `ChatInstruction` contains no such constraint at all."*

**That is literally true and materially misleading, and MAX-175 should not be scoped on it.**
`ChatInstruction` holds no task text *by design* — its `task` property has no default, and
the type's own doc comment says why: *"what to ask Claude to do in a chat turn is a product
decision belonging with the chat feature, not with the code that moves the bytes."* Looking
for the constraint there is looking in the file that was deliberately built not to hold it.

**The constraint exists, in the file that owns it.** `ChatModel.workoutTask`:

> *"Answer using only the fact sheet and the conversation so far. Never invent a number,
> split, or detail the fact sheet does not state; when something was not measured, or the
> fact sheet says it does not apply, say so rather than guessing."*

`ChatModel.trainingTask` goes further, with four separate refusals: never invent a figure;
name the window any figure was measured over; never re-score a session; no medical advice.
`PlanProposalInstruction` carries *"Do not invent facts about the athlete. Where the
conversation is silent…"*. And `ChatInstruction` itself already contains the *precedent* for
an app-authored refusal — when the transcript cap drops turns, it injects a bracketed notice
telling the model to say it lost that stretch **rather than answer as though it had it**.

So Helix's *"if you have never logged strength work, it will say so rather than invent a
per-muscle story"* is a property Maximize already asserts in three of its four model-facing
prompts. Here is what is **actually** missing, and it is smaller and more useful:

| # | Real gap | Evidence |
|---|---|---|
| G1 | **It is prose in four literals with no test over the set.** A fifth prompt carries it only if its author remembers. This is 5.2's gap wearing a different hat, and it is the one MAX-175 should close | `ChatModel.workoutTask`, `ChatModel.trainingTask`, `PlanProposalInstruction`, `WorkoutScorer.taskDescription` |
| G2 | **One live instance of the exact failure mode, already known and still open.** `TrainingFactSheet`'s plan block renders `entry.session` and **leaves the lift slot unrendered** — so a training thread's model is told the run prescription and silently not the lift one. `PROJECT_TRACKER.md` logs it as open against MAX-136 | Tracker's fact-sheet source table |
| G3 | `WorkoutScorer.taskDescription` is bounded differently — rubric-first, JSON-out, no free prose — and arguably needs no refusal clause. **That should be a recorded decision, not an omission nobody noticed** | `WorkoutScorer.swift` |

**G2 is the important one.** It is Helix's per-muscle-story failure in our own idiom, it is
verified, it is open, and it is a prompt-contents change — so it is D3 territory and carries
a `/security-review`. Filed below as MAX-181.

### 5.4 Where our privacy position actually stands

Structurally we are equal or stronger than Helix on every axis the owner tested: no backend
(A1, and unlike them we have no relay because we have no distribution), no account, no ads,
no trackers, no analytics, one model provider instead of two, and — the part that matters —
**A5 writes down what the on-device key is buying and what shipping would cost**, which §2.1
suggests Helix has not done.

**But our prompt is not anonymised, and we should never claim it is.**
`WorkoutFactSheet.factSheet()` opens every prompt with `Date: <day> (<weekday>)`. A dated
series of workouts is not an anonymised number; it is a re-identifiable record of a person's
movements in time. `Goals: <statements>` renders free text the athlete typed into the plan
authoring screen, and nothing constrains what that text contains.

**Recommendation: keep the dates and stop pretending otherwise.** *"You drifted on the long
run three Sundays running"* is the product; stripping dates to match a competitor's marketing
sentence would damage the app to win an argument nobody is having. The goal-statement
passthrough is the genuinely unexamined channel, and it should get the treatment MAX-068 is
already getting for splits. Amendment A26 (§10) records the position so no future ticket
adopts Helix's wording by drift.

---

## 6. What to reject outright, and why it needs an amendment

**Subjective day-ratings that re-weight a score the athlete has already seen.** §2.3.

If Maximize ever adds a felt-rating — and there is a reasonable case for one, since PRD §2's
correction-rate metric is already an athlete-judgement signal — **the rating must be
collected before the score is revealed**, or the personalisation is measuring the athlete's
own anchoring and calling it physiology.

This app is unusually well placed to get it right, because **it already has the correct
shape and did not notice.** D8's auto-versus-manual divergence is a felt-rating loop that
happens to be honest by construction: the auto-score is written immutably *first*, the
athlete's correction is a separate additive record, and the gap between them is the
measurement. Nothing re-weights anything. A21 then went further and excluded
category-error scores from that divergence, so the signal measures scorer quality rather than
noise.

The failure mode to guard against is not "we might add a bad feature." It is that a *good*
feature — personalising the rubric from the athlete's own corrections — is one careless
ordering away from being Helix's contaminated loop. **A25 (§10) writes the ordering down
before anyone needs it**, which is the same move A5 made about the API key and the same move
§2.1 suggests Helix skipped.

---

## 7. The strategic question, answered

The owner's framing, which I agree with: **Helix does not kill Maximize, but it kills any
version of Maximize imagined as a shippable product.** This section says which project the
codebase is optimising for, because the answer changes what the next fifty tickets should be.

### 7.1 Why Helix is not a threat to *this* app

Maximize is single-user, scoped to one athlete's 16-week plan, with a hand-tuned rubric no
general-purpose app will replicate. Nothing in the owner's reading or in search suggests
Helix has a **versioned training plan** or scores a workout **against a prescription** — and
that is the entire spine of this app. D1's reproducibility guarantee, `PlanCalendar`,
`ScheduledSession` per (weekday, discipline), the rubric-as-data, the effective-day ledger:
none of it has a Helix counterpart, and none of it is something a broad consumer app can add,
because it requires the user to author a plan.

`PROJECT_TRACKER.md` names MAX-062, the cross-run drift overlay, as *"the ticket that
justifies the project"* precisely because *"no other app can draw it."* On the evidence
available, Helix cannot draw it either.

### 7.2 The codebase is already optimising for the private app, by decision

This is not a preference — it is recorded in the architecture, and A5 is the load-bearing
entry. The Anthropic key lives in Keychain *"acceptable only because the app is single-user
and never distributed,"* with an explicit tripwire: **ship it to anyone else and the key must
move behind a server first.**

A5's tripwire is what makes the app architecturally single-user. Everything else follows:
A1 deleted the backend, A8 deferred CloudKit because free provisioning grants no iCloud
entitlements, `AppSettings` is a singleton with no owner key, `StandardPlanSeed` encodes one
person's rubric, and `docs/DEVICE-BUILD.md` describes signing as a local, credential-holding,
non-CI act.

**Recommendation: say this out loud, and stop treating it as provisional.** It is currently
legible only to someone who reads A5 closely enough to notice that a tripwire is also a
commitment.

### 7.3 What changes if it is the private app

- **The parity backlog dissolves.** Feature breadth stops being a goal at all. §3's four
  Builds are not a compromise; they are the whole correct list.
- **A5's tripwire stays a tripwire, not a debt.** No work is owed to "prepare for shipping."
- **A8's deferral is permanent-shaped**, not a stopgap — and the schema keeps CloudKit's
  restrictions anyway, exactly as CLAUDE.md instructs, because re-enabling should stay two
  lines rather than a migration.
- **The hand-tuned rubric is a feature.** Generality would make it worse. §2.3's
  contamination problem is one an app with one athlete and an immutable auto-score can
  actually avoid.
- **Effort goes to depth**: the drift overlay, plan fidelity (P1/P2/P4 in the tracker's plan-
  model gaps, particularly interval structure), and scoring quality measured by the
  correction rate PRD §2 already defines.
- **Device verification stays acceptable**, because there is one device and one person to
  run `docs/DEVICE-CHECKS.md`.

### 7.4 What would have to change if it is not

Listed in cost order, because the first item is most of the cost:

1. **A5 reverses, and with it A1.** The key moves behind a server — which reintroduces the
   backend A1 deleted, the largest single architectural reversal available. Everything A1
   claimed as a benefit (offline by construction, the numerically critical logic in a
   CI-verified pure package) is either lost or must be re-argued.
2. **Multi-user reaches the schema.** Every record is keyed by workout UUID, plan version or
   day; none carries an owner. `AppSettings` is a singleton.
3. **CloudKit must come back (A8)** — cheap, and the one item already paid for, because the
   schema has obeyed CloudKit's rules throughout.
4. **The plan model must survive strangers.** `StandardPlanSeed` is one athlete's rubric, and
   plan authoring assumes someone who knows what a cadence band is.
5. **Onboarding for people who do not read grade-adjusted pace.** `docs/FIRST-RUN-SPEC.md`
   argues *against* an onboarding flow — correct for one user, wrong for many.
6. **The health-claim surface becomes a liability**, not a curiosity. §8.3's declines stop
   being scope calls and start being risk calls.
7. **The market evidence is discouraging, and it is Helix's own.** §1: a broad, fast-shipping
   Whoop clone at $9.99/mo with a full SEO operation has **too few ratings to display an
   overview**. That is evidence about the market for this category, not about Helix's code.
   I cannot verify it and neither could the owner beyond the listing, but it is the single
   most relevant data point available about whether item 1's cost would ever be repaid.

### 7.5 The recommendation

**Optimise for the private app, explicitly and on the record.** Take the two cheap Helix
ideas that compose with the plan spine (strain, load balance), take the muscle map narrowly
because A22 already paid for its input, take the three discipline rules in §5 — of which two
we already hold and the third is a smaller gap than reported — and decline the rest.

If the owner wants to test the shippable path, **the honest first move is not a feature. It
is pricing A5's reversal**, because nothing else on the list is real until the key moves.

---

## 8. What not to build, and why

### 8.1 Recovery, strain ceiling and sleep — decline for now, and this is a change from the parity brief

The parity draft of this document ranked recovery as the top build. **On the owner's
findings I no longer think so**, for three reasons that only appeared once §2 arrived:

1. **§4.2's cost is real** — roughly the original ingestion phase, again — and it buys a
   number whose *method* §2.3 shows to be the weakest part of Helix's product. Building the
   expensive thing to match the untrustworthy thing is the wrong trade.
2. **A recovery score has no home in a plan-relative app** unless it changes the ask. If it
   changes the ask, the plan is no longer authored (D1) but inferred, which is a different
   product. If it does not, it is a tile.
3. **The cheap 60% is available without any of it.** Strain and load balance (§4.1) tell the
   athlete what training cost and whether they are ramping too fast, from a curve already on
   disk. That is most of the value at a fraction of the cost.

**Not "never".** If the owner wants it after strain lands and proves useful, §4.2 is an
accurate cost estimate and A27 (§10) is the amendment it needs. It should be a deliberate
decision with that price in front of it, not the default first move.

### 8.2 The VO2max lab and the Apple Watch — decline together

The Cooper test needs three non-goals spent at once: live in-workout coaching (PRD §3, and
now load-bearing via A14), writing to HealthKit (PRD §3), and a Watch target — because nobody
runs a twelve-minute maximal test holding a phone to read a timer.

**On the Watch, honestly: it buys nothing on the recommended list.** Every input already
arrives in iPhone HealthKit after Watch sync; that is how the entire app works, and Helix's
own copy concedes iPhone-only operation is viable. A Watch target costs a new build target,
signing work on the part of `docs/DEVICE-BUILD.md` that is already fragile, a second UI held
to `CLAUDE.md`'s standard, and a second surface CI cannot verify. **The Cooper test is the
only capability that genuinely requires it**, which is a further argument against both.

**The cheaper thing that is not the lab:** Apple already computes and publishes
`HKQuantityTypeIdentifier.vo2Max` from ordinary runs. If the owner wants the number on
screen, read Apple's. Building our own estimator would be PRD §13's named anti-pattern —
reimplementing Apple — and it would be worse.

### 8.3 Physique scanning and bloodwork — decline, and they are not ordinary scope calls

Both make claims about a person's body, and both break structural rules rather than merely
adding work.

**Physique scanning** sends a photograph of the athlete to a model. That is a categorically
different disclosure from the dated metrics §5.4 describes, it cannot pass through the D3
context builder as designed (an image is not a fact sheet), and it has no ground truth to be
checked against.

**Bloodwork** is either a reference-range lookup or clinical interpretation, and the distance
between *"your ferritin is below the reference range"* and *"your ferritin is low, eat more
iron"* is the distance between a table and medical advice. **PRD §12 already settled the
adjacent question** — anomaly flags were deferred with the words *"deliberately deferred; not
a diagnostic tool"* — and `ChatModel.trainingTask` already instructs Claude to refuse
clinical questions outright. Adding bloodwork would contradict a rule the app currently
enforces in its own prompt.

**These stay owner decisions if the owner wants them at all**, and each would need an
amendment stating what the app asserts and what it refuses to, plus a `/security-review` on
the new disclosure. I am not filing tickets for them.

### 8.4 Nutrition logging — decline, and this is the clearest case

Barcode scanning and meal photography are better manual entry. They are still **manual entry
as a core daily loop**: several taps a day, forever, or the data is worthless.

PRD §2's north star is *"Never hand-type a workout log row again"* with a target of **zero**
manual entries. PRD §3 names manual entry *"the thing being killed."* The app's entire thesis
is that a loop like that decays, and that the days you skip logging are disproportionately
the days worth analysing. Building the thing the product exists to kill, as a daily loop, is
not a scope question — it is a contradiction.

A22 shows what a legitimate exception looks like: **one field, on one kind of workout, entered
after the fact on a screen you are already looking at**, recorded as an amendment that
explicitly refuses to generalise. Nutrition cannot be scoped that way. A20's tripwire is
written about exactly this pressure: *"'It is only two numbers' is how the thing the product
exists to kill comes back."*

**If the owner wants it anyway, it arrives as an amendment superseding PRD §3, with a scoped
answer to what else the app then owes the athlete — never as a ticket.**

### 8.5 Cycle awareness — decline for this athlete

Not an ethics question and not a scope question in the usual sense: a single-user app, and
only the owner knows whether it applies to them. On the evidence available it does not.
Filed as declined rather than deferred so it is not silently re-proposed.

### 8.6 Game Center, badges, widgets, energy plan — decline

Leaderboards require other people; this app has one user by design and no account.
Achievement badges for an athlete who reads aerobic decoupling misjudge the audience — PRD §5
says the UI *"can be dense and quantitative, not hand-holdy."* The energy plan is a
presentation of features §8.1 declines. Widgets were worth deferring in the parity draft on
the theory that recovery would land; with §8.1 they have nothing to show.

---

## 9. Tickets

Four tickets. **MAX-175 is the coordinator's** (the no-fabricated-score invariant plus the
honest-refusal constraint) and is deliberately absent here — §5.2 and §5.3 are written as
input to it, particularly the correction in §5.3 and the G1/G2/G3 breakdown. Numbering
continues from there.

**MAX-176 — Per-workout strain, computed at ingestion (Opus)**
A zone-weighted integral of the stored HR curve, computed once and stored per D2. Absence is
first-class: a workout with no HR curve has no strain and says so, per A18 and per MAX-175's
invariant once it lands. Must state its own limit — a lift's strain is HR-only, which A20's
reasoning already establishes is all the record carries.
*Files:* `Sources/MaximizeCore/Domain/DerivedMetrics.swift`,
`Sources/MaximizeCore/Domain/DerivedMetricKind.swift`,
`Sources/MaximizeCore/Metrics/DerivedMetricsCalculator.swift`,
`Sources/MaximizeCore/Persistence/StoredWorkoutRecords.swift`,
`App/Persistence/MaximizeSchema.swift`, tests.
*Constraint:* additive optional field with a default — A8's CloudKit discipline is binding,
and MAX-169's additive-schema conclusion applies.

**MAX-177 — Strain reaches the detail view and the prompt (Sonnet, 🔒)**
One summary tile, one fact-sheet line. The fact-sheet half is a D3 decision about what Claude
sees and inherits MAX-068's `/security-review` obligation.
*Files:* `Sources/MaximizeCore/Metrics/SummaryTileData.swift`,
`Sources/MaximizeCore/Context/WorkoutFactSheet.swift`, `App/Workouts/SummaryTilesView.swift`,
tests. **Needs device verification:** the tile.

**MAX-178 — Acute vs chronic load balance (Sonnet)**
Rolling 7-day and 28-day strain sums and their ratio over stored values, in the pure-function
shape `TalliesCalculator` already has. The first 28 days are a designed absence state in the
existing voice, not a blank.
*Files:* new `Sources/MaximizeCore/Tallies/LoadBalanceCalculator.swift`,
`Sources/MaximizeCore/Metrics/TrendTileData.swift`, `App/Dashboard/TrendTilesView.swift`,
tests. **Needs device verification:** the tile.

**MAX-179 — Per-muscle fatigue from the entries A22 already collects (Opus)**
A decay model over `MuscleGroupEntry` records: last session per group, decayed by elapsed
time, weighted by that session's duration and (once MAX-176 lands) its strain. **Must state
in its own doc comment what it cannot know** — no sets, no reps, no load (A20) — so a later
ticket does not read the model as more precise than it is. **This ticket is the one most
likely to attract a "just add a weight field" follow-up; A20's tripwire governs it, not
A22's permission.**
*Files:* new `Sources/MaximizeCore/Domain/MuscleFatigue.swift`, new
`Sources/MaximizeCore/Metrics/MuscleFatigueCalculator.swift`, tests.

**MAX-180 — The muscle map, drawn (Sonnet)**
A six-region figure on a flat content surface (FR-4.2, no glass over data), `@ScaledMetric`
throughout, colour tokens only. Fatigue bands must carry a **non-hue channel** and must
**extend the existing score-band accessibility test rather than write a parallel one** —
CLAUDE.md is explicit, and this codebase has already found a real 1.02:1 hue-only failure.
Carries an honest caption about what the model does not know.
*Files:* new `Sources/MaximizeCore/Accessibility/MuscleFatigueMark.swift`, new
`App/Workouts/MuscleMapView.swift`, `App/Workouts/WorkoutDetailView.swift`, tests.
**Needs device verification:** the whole thing. CI never draws a pixel.

**MAX-181 — `TrainingFactSheet` renders the lift slot (Sonnet, 🔒)**
§5.3's G2. The plan block renders `entry.session` and leaves the lift slot unrendered, so a
training thread's model is told the run prescription and silently not the lift one — a live
instance of the exact failure MAX-175 is being written to forbid. Known and open against
MAX-136 in `PROJECT_TRACKER.md`. Prompt contents, so D3 and `/security-review`.
*Files:* `Sources/MaximizeCore/Context/TrainingFactSheet.swift`, tests.
*Sequencing:* **after MAX-175**, so it lands against the stated invariant rather than beside it.

---

## 10. Amendments this implies

Proposed for `docs/PRD-AMENDMENTS.md` if the owner accepts §7.5. Drafted as intent, not final
text. **A25 is the one that should land regardless of every other decision in this document.**

**A25 — A felt-rating is collected before the score is revealed, or not at all.**
Records §2.3's finding as a rule for us. If Maximize ever collects a subjective day- or
session-rating, the rating is captured **before** the athlete has seen the corresponding
score, or the personalisation measures the athlete's anchoring rather than their body. Notes
that D8 already has the honest shape — auto-score written immutably first, correction stored
additively beside it, divergence as the measurement — and that the rule exists to keep a
*good* future feature (personalising the rubric from the athlete's own corrections) from
becoming a self-confirming loop by an ordering mistake. Cross-references A21, which already
protects that signal from category-error noise.

**A26 — The prompt carries dated records, and the app never claims otherwise.**
Clarifies A5 and records §5.4. Maximize's Claude prompt is **not** anonymised: it carries
calendar dates and athlete-authored goal text. This is deliberate — dated series are the
product — and the app must never adopt "anonymised numbers only" as a claim while it is true.
Names the goal-statement passthrough as the one channel never examined, alongside MAX-068's
splits question. Restates the A5 tripwire, and adds §2.2's caution: the App Store "Data Not
Collected" label exempts real-time unretained requests and would therefore be no evidence at
all about our prompt contents.

**A27 — Daily health data would be a second ingestion path, and it is not being built.**
Records §8.1 as a decision rather than an omission, with §4.2's cost attached, so the question
is re-opened deliberately rather than re-derived from scratch. States that if it is ever
built it needs its own observer and its own anchor store, for the reason `PROJECT_TRACKER.md`
already gives about anchors and CloudKit, and that it re-presents the HealthKit permission
sheet on existing installs.

**A28 — Maximize is a single-user app by decision, not by circumstance.**
§7.2. Elevates what A5's tripwire already implies into a stated position, so that "prepare
for shipping" is never treated as owed work, and so that the reversal has a written price
(§7.4) rather than being discovered one ticket at a time. Records that the hand-tuned rubric
and the authored plan are advantages of the private app, not limitations of it.

---

## 11. Summary

| | |
|---|---|
| **Build** | Per-workout strain · load balance · per-muscle fatigue · the muscle map (MAX-176–180) |
| **Fix** | `TrainingFactSheet`'s unrendered lift slot — a live instance of the failure MAX-175 forbids (MAX-181) |
| **Already have, more strictly** | The frozen verdict (D8, defended by A21) · honest refusal in three of four model-facing prompts · no backend, with the cost written down (A1/A5) |
| **Write down** | Felt-ratings before scores (A25) · the prompt is not anonymised (A26) · daily ingestion declined with its price (A27) · single-user by decision (A28) |
| **Decline** | Recovery/ceiling/sleep for now · VO2max lab · Watch app · physique scan · bloodwork · nutrition logging · cycle awareness · Game Center · widgets · energy plan |

**The one-line conclusion.** Helix is broad, fast and unproven, and its two most quotable
claims — no backend, and a personalised recovery score — are the two the owner's reading
found weakest. Maximize is narrow, slow, single-user and correct about the things it has
written down. **Matching Helix's feature set would trade the second for the first.** Take the
four features that compose with the plan spine, write down the three rules we already follow
and the one we should, and spend the rest of the effort on the drift overlay — which remains,
on all available evidence, the thing no other app can draw.

---

## Sources

**Layer 1 — the owner's reading of Helix's pages (docs, privacy, recovery, App Store).**
Not verified by me; the pages are unreachable from this environment. §1, §2.

**Layer 2 — web search**, used only where it corroborates Layer 1. §1, §3.

- `https://www.projecthelix.app/docs/ai-coach` — **blocked** (`EGRESS_BLOCKED`)
- `https://www.projecthelix.app/` — **blocked**
- `https://apps.apple.com/us/app/helix-ai-fitness-coach/id6789951372` — **blocked**

**Layer 3 — this repository**, verified. `docs/PRD.md`, `docs/PRD-AMENDMENTS.md` (A1–A24),
`docs/LIFTING-SPEC.md`, `docs/CHAT-FIRST-SPEC.md`, `docs/FIRST-RUN-SPEC.md`,
`docs/DEVICE-BUILD.md`, `PROJECT_TRACKER.md`, `CLAUDE.md`, and the source under
`Sources/MaximizeCore/` and `App/` — in particular `ChatModel.swift`,
`ChatInstruction.swift`, `WorkoutScorer.swift`, `PlanProposalInstruction.swift`,
`WorkoutFactSheet.swift`, `DerivedMetrics.swift`, `MuscleGroup.swift`, `HealthDataType.swift`
and `MaximizeSchema.swift`.

# PRD Amendments

[docs/PRD.md](./PRD.md) is preserved as received (Draft v1, 2026-08-04). Where the
build deliberately departs from it, the departure is recorded here rather than by
editing the spec — so the original reasoning stays legible and the deltas stay
reviewable.

**Read this alongside the PRD. Where they conflict, this file wins.**

---

## A1 — No backend. The app is fully on-device.

**Supersedes:** §6 (architecture), §8 (Postgres schema), §11 (TLS, device token),
and the backend half of §5.

**Decision (2026-08-04):** There is no FastAPI/Postgres/Redis backend. Storage is
SwiftData, backup is CloudKit, and Claude is called directly from the app.

**Rationale:** The backend's primary job in the PRD was keeping the Anthropic API key
off the device (§6, §11). That constraint is load-bearing for a distributed app; for
a single-user app that is never shipped to anyone else, it buys little. The threat
model collapses from "the key is in every App Store binary" to "someone extracts the
key from my own phone."

Every other decision the backend supported survives the move — only the substrate
changes:

| Decision | Intent | On-device form |
|---|---|---|
| D1 | Historical scores reproducible | Versioned plan records in SwiftData |
| D2 | One set of stored numbers | Computed at ingestion, stored, read everywhere |
| D3 | Scorer and chat can't diverge | One context builder in `MaximizeCore` |
| D6 | Chat survives reinstall | SwiftData + CloudKit |
| D7 | HR series as a blob | Unchanged |
| D8 | Immutable auto-score | Unchanged |

**What this buys:** deletes an entire stack (FastAPI, Postgres, Redis, Alembic,
docker-compose, deployment) and removes the network from the read path, so §11's
offline requirement is satisfied by construction rather than by feature work. It also
moves the numerically critical logic — metrics, classification, scoring, tallies —
into a pure Swift package that CI fully verifies.

**What it costs:** see A5.

## A2 — FR-0.4 (background `URLSession` upload) is removed.

There is no server to upload to. Ingestion writes straight to the local store. The
reliability requirement it served (§11, "at-least-once delivery, idempotent
ingestion") still holds and is satisfied by dedupe on `workoutUUID` at write time.

## A3 — Device-token auth is removed.

**Supersedes:** §3 non-goals ("auth is a device token, nothing more") and §11.
Nothing to authenticate to. The only credential in the system is the Anthropic API
key (A5).

## A4 — Redis caching is removed.

**Supersedes:** §8 ("cache in Redis if needed"). Tallies are computed on read from
the local store; at single-user volume this is trivially fast. If it ever isn't,
cache in memory.

## A5 — The Anthropic API key lives in Keychain, on-device.

**Supersedes:** §6 ("The Anthropic API key never touches the device") and §11.

Accepted consequence of A1. Bounded by two conditions:

1. The app is single-user and is **never distributed**.
2. **Tripwire:** if condition 1 ever stops holding, the key must move behind a server
   *before* the app ships. This is a release blocker, not a follow-up.

## A6 — §14.1 resolved: rest-day conversion is **automatic**.

**Resolves:** the open sub-decision in §14.1, which the PRD left to the owner.

The system spends the weekly rest-day budget automatically on the least-costly missed
days, rather than requiring the user to tap a red day. Chosen for consistency with the
north star ("never hand-type a workout log row again" — §2); a manual conversion tap
is exactly the kind of bookkeeping the product exists to remove.

**Known trade-off, from the PRD's own analysis:** automatic conversion will sometimes
forgive a day the user would rather see as a miss, because "that was a real rest day"
is a judgment the system cannot reliably infer. If the calendar starts reading as too
generous, the fix is to revisit the selection heuristic — or fall back to manual — not
to widen the budget.

## A7 — §14.2 resolved: the accent is the violet **`#8E7CFF`** (dark) / **`#5B3FE8`** (light).

**Resolves:** the open sub-decision in §14.2, which the PRD left to the owner and
marked non-blocking.

**Decision (2026-08-05, MAX-084):** ratify the values MAX-040 committed as a working
default. In full, all four appearances:

| | Standard | Increase Contrast |
|---|---|---|
| Dark | `#8E7CFF` | `#B3A6FF` |
| Light | `#5B3FE8` | `#3B22C4` |

No code changes: the values are already in
`Sources/MaximizeCore/Accessibility/DesignPalette.swift`. What changes is their
status — they were "a defensible default, not a decision" (`ColorTokens.swift`), and
they are now the decision. Re-theming stays a one-line edit if the owner disagrees.

**Why this one.** The accent has to survive three collisions the PRD sets up, and
violet is the only region of the wheel far from all three at once: it is not
Robinhood's green (`#00C805`, named in the PRD), it is not any of the three score
bands, and it is not the untinted iOS system blue that users read as "no design was
applied here".

**It measures well in every appearance**, which matters more than it might sound,
because the accent is about to move from two call sites to every tab label, picker
segment and button title in the app (design review §3.1). Those are *text*, so 4.5:1
is the bar, not 3:1:

| Pair | Dark | Light | Dark, IC | Light, IC |
|---|---|---|---|---|
| accent on `surface` | 6.06:1 | 6.32:1 | 9.82:1 | 9.49:1 |
| accent on `surfaceElevated` | 5.56:1 | 5.81:1 | 7.90:1 | 8.14:1 |
| accent on `surfaceInset` | 5.05:1 | 5.32:1 | 7.01:1 | 7.22:1 |
| `textOnSaturatedFill` on accent | 6.06:1 | 6.32:1 | 9.18:1 | 9.49:1 |

Every figure clears AA for normal text against every surface level in both
appearances, and clears AAA (7:1) under Increase Contrast. `WCAGContrastTests` pins
the 6.06:1 figure and asserts the AA floor for the rest, so this table is checked on
every commit rather than trusted.

(The design review's appendix records 9.18:1 for dark Increase Contrast. That figure
pairs the Increase Contrast accent with the *standard* dark surface; against the
Increase Contrast surface — pure black — it is 9.82:1. Both clear AAA; the row above
is the pairing that actually renders.)

**Alternatives measured and rejected**, dark value against `surface`:

| Candidate | On `surface` | Against `scoreEffective` | Why not |
|---|---|---|---|
| Cyan `#32D6E0` | 11.07:1 | **1.14:1** | Sits at the same luminance as "this run went well", on screens that show both |
| Teal `#2FD4C4` | 10.60:1 | **1.09:1** | Same collision, worse |
| Electric blue `#4D9BFF` | 6.97:1 | 1.39:1 | Reads as system blue at a glance — the failure mode the brief names |
| Magenta `#FF4FD8` | 6.89:1 | 1.41:1 | Clears the bands, but is louder than a colour used "sparingly" (FR-4.3) should be |
| Lime `#C6F24E` | 15.17:1 | 1.56:1 | Same hue family as `scoreEffective`; also very loud |

The cyan and teal numbers are the interesting ones: both have excellent contrast
against the background and would still have been wrong, because contrast against the
*surface* is not the only constraint an accent has to meet.

**The one real argument against violet-on-near-black** is that it is a recognisable
current palette and a discerning viewer may find it familiar rather than distinctive.
Against that: this app is single-user and is never distributed (A5, A8), so "reads as
someone else's brand" costs nothing.

**What this does not settle.** The accent still reaches almost nothing the system
draws — `.tint()` is called nowhere in `App/` — so ratifying the value does not by
itself make the app look accented. That is a separate ticket (design review §3.1).

## A8 — CloudKit backup is deferred. D6 is downgraded to on-device durability.

**Amends A1**, which named CloudKit as the backup half of the on-device architecture.

The app is signed with a free Apple Developer personal team, and free provisioning does
not grant the iCloud container or CloudKit service entitlements. Requesting them made
the device build unsignable — and the device build is the only build that can exercise
zero-touch capture at all, since the Simulator cannot run HealthKit background delivery.
Given the choice between the backup path and the product's central claim, the central
claim wins.

**What this costs, stated plainly.** D6 says chat threads are persisted and survive
reinstall. They now survive *relaunch*, not reinstall: delete the app and the history
goes with it, and a second device starts empty. Nothing else regresses — capture,
scoring, metrics, chat and every screen are local and unaffected.

**Why the schema does not change.** MAX-020 built every model to CloudKit's
restrictions: no `@Attribute(.unique)`, no non-optional property without a default, no
required relationships. Those constraints are now unenforced by anything, and they stay
anyway. They cost nothing to keep and they are what makes re-enabling mirroring a
two-line change — the entitlements block in `project.yml` and `makeOnDisk`'s
`cloudKitDatabase` default — rather than a migration of an already-populated store.
Removing them would be spending real future work to buy nothing today.

**The trap this closed on the way past.** `makeOnDisk` defaulted to
`cloudKitDatabase: .automatic`, and against a build with no iCloud entitlement that is
not a harmless no-op: container creation fails, `PersistenceComposition.store` becomes
nil, and the app runs with no storage — capturing nothing while appearing to work,
because every failure on that path is already designed to be survivable. The default is
now `.none`.

**Tripwire, in the same spirit as A5's:** if this app is ever distributed, or if a
second device is ever expected to see the same history, CloudKit is not optional and
D6 is not satisfied. Do not let "it has worked fine for months" stand in for backup —
it has worked fine because there is only one device and nobody has reinstalled.

---

# The chat-first pivot (A9–A15)

A9 through A15 all come from one direction change by the owner and are recorded together.
The reasoning behind them is [docs/CHAT-FIRST-SPEC.md](./CHAT-FIRST-SPEC.md) (MAX-090);
what follows is only the part that supersedes the PRD. **None of it is built yet** — these
amendments describe the target the MAX-092–104 tickets are working toward, and are recorded
now so that no ticket has to re-derive them, and so that A10 in particular cannot land by
accident.

## A9 — Chat is a second primary interaction, with three named jobs.

**Supersedes:** §7.2's framing of chat as a per-workout feature, and FR-2.1's assumption
that a chat thread always has a workout.

The owner's direction: *"I want the interactions of this app to be mainly through a chat…
I want to be able to generate my plan, view my plan through the chat interface. I want to
be able to ask questions about my data through the chat."*

Chat gets exactly three jobs — **generate a plan**, **read a plan**, **ask questions about
the data** — reached from a persistent control present on every screen.

**Chat is additive, and this is the load-bearing half of the amendment.** The owner's own
clarification put the detailed dashboard and workout-detail screens explicitly in scope:
they are not demoted, not thinned, and not replaced by prose. §5's dense-and-quantitative
brief and §7.4's numerals-do-the-hierarchy-work are *reinforced* by this pivot, not
softened. A future ticket proposing to replace a chart with a paragraph is out of scope of
this amendment and should be refused on its authority.

## A10 — Claude reaches the dashboard. The §3 non-goal is spent deliberately.

**Supersedes:** §3's non-goal *"Claude on the dashboard tab (`summarize my month`)"*, §12's
deferral of it to v2, and the matching line in `PROJECT_TRACKER.md`'s "Deliberately not
built".

A9's persistent control appears on the dashboard, and there it opens a thread about the
athlete's training over an interval rather than about one run. That *is* the deferred
feature, so it is superseded on the record.

Written as its own amendment rather than folded into A9 because the "Deliberately not
built" list exists, in its own words, "so nobody helpfully adds one". A non-goal that
disappears because of where a button was placed is exactly the failure that list is for.
This amendment is the deliberate spend.

## A11 — Thread identity is independent of a workout.

**Supersedes:** D6's assumption of one thread per workout, and MAX-048's duplicate-
resolution rule inasmuch as it keys identity on the workout.

A thread is keyed on its own identifier and carries a **subject**: either one workout, or
the athlete's training over a resolved date range. The workout link becomes one of two
subjects rather than the thread's identity.

**No migration.** Existing threads have a workout subject; the fields this adds are
additive and optional, which is the same discipline A8 requires of the schema for a
different reason.

**Scope is resolved once, at thread creation, and frozen.** A training thread inherits the
interval control's current range, converts it to absolute days, and keeps them. It does not
slide with the calendar — a conversation is about a bounded set of facts, and a window that
moved would make yesterday's answer cite runs that are no longer in context. New chat is
how you get a newer window. See A12's agreement property for what this obliges the UI to
state.

## A12 — D3 is generalised to a subject, not weakened.

**Supersedes:** nothing. **Amends** D3's wording, which assumed a single workout.

D3 says one context builder feeds both scorer and chat. A thread with no workout has no
`WorkoutContext` to build, and the two obvious escapes — concatenating N workout fact
sheets, or letting the chat layer assemble its own — are both rejected in the spec (§3.1),
the first on privacy grounds and the second because it is precisely the divergence D3
exists to prevent.

The generalisation, in four rules:

1. **One module, one entry point.** `Sources/MaximizeCore/Context/` keeps a single
   `build(for subject:)`. `WorkoutContextBuilder` is unchanged and is called *by* it, so
   the scorer and a workout thread still receive byte-identical context.
2. **A closed subject set.** Adding a third subject is an amendment, not a ticket.
3. **A shared renderer.** Both fact sheets format the same measurement through the same
   formatters, enforced by a test asserting the two paths agree. Without this, "one module"
   is true and worthless — `+4.2%` against `4.2 %` is a divergence at the only boundary
   that matters.
4. **No arithmetic in a context.** Every aggregate a training context quotes is produced by
   the same core function the corresponding screen reads — `TalliesCalculator` for tallies,
   the trendline fit for a slope. This is D2 restated at a new boundary, and it now has
   teeth it did not need before: chat and a tile describe the same number to the same
   person, so a divergence is a **visible product defect**, not an internal untidiness.

**A training context is a roll-up, not a stack of fact sheets** — the plan in effect, the
tallies over the scope, one line per run, and the scope stated. No heart-rate curves, no
splits, no coordinates, no score rationales. Bounded by the scope and again by an explicit
maximum, because health data leaving the device must never be sized by a number nothing has
validated.

**What this costs, plainly.** More leaves the device than before: today one run's facts go
when the athlete opens a thread and types; after this, a summary of up to N runs goes per
training turn. That is a real change to the privacy posture and is recorded as one. It is
bounded by the four rules above and by A14's no-unattended-call invariant, and every ticket
touching `Context/` or a prompt gets a `/security-review`.

## A13 — A model-drafted plan is a proposal. D1 is untouched.

**Clarifies:** D1. It supersedes nothing.

D1 says the plan is versioned data whose immutability keeps historical scores
reproducible. Generating a plan is an *authoring* act, and the two are compatible as long
as there is exactly one door into storage.

**The model emits a proposal, never a plan.** A proposal is parsed and validated in the
core, rendered for review, and can only become a plan version by the athlete tapping
through `PlanAuthoringSession` — the same door `PlanAuthoringView` uses, built by MAX-080.

**The near-miss to watch for in review:** a helper that applies a proposal to a draft *and
also stores it*. Applying is fine. Storing is D1's door, and it opens by hand.

## A14 — Cost discipline for a chat-first app, and one invariant.

**Supersedes:** §11's single-line cost note.

Four bounds, and one rule that is not a bound:

- **The tier is Sonnet at `medium` effort**, both clients, on the owner's instruction
  (MAX-091). `effort` is a per-request lever, so a single route can be raised without
  moving the app's cost floor.
- **Context is a roll-up** (A12), doubly bounded. The largest lever, chosen for privacy
  first; the saving points the same way.
- **The replayed transcript is capped**, and when turns are dropped the model is told so —
  a model answering confidently as though it had seen the start of a conversation it did
  not is worse than one that says it lost the thread. Summarising the dropped turns with a
  second call is rejected: it is a second assembler of context (A12) *and* it doubles the
  calls.
- **Plan drafting is one call per tap**, bounded by being a button.

**And the invariant: no unattended chat call. Ever.** Every chat call is initiated by the
athlete typing or tapping. The only unattended model call in this app is and remains the
scorer's, one per ingested workout.

Written as an invariant because the obvious next request — a proactive coach, a weekly
summary that writes itself, a notification carrying an insight — would change the cost
profile by an order of magnitude *and* would send health data to a model with nobody
present. Adding one is a decision made deliberately, with this paragraph in front of it.

## A15 — The plan gets a read-only screen.

**Adds to** §7. Supersedes nothing.

The plan is the reference every score is measured against, and today it is legible only
while you are editing it: there is an authoring form and no way to simply *look* at what is
in effect.

A9 asks chat to answer plan questions, and it will. This amendment says a screen is also
required, because "what is my current plan" is a lookup rather than a conversation, and
making the athlete spend a model call — against a key they pay for — to read back their own
stored configuration is the wrong shape for it.

**This is the one item in the pivot nobody asked for**, recorded as such. It is deliberately
independent of every other ticket in the chat-first set, so dropping it costs nothing else.

---

# Lifting (A16–A21)

A16 through A21 come from one sentence from the owner — *"Plans should account for both
lifting goals and running goals"* — and are recorded together. The reasoning behind them is
[docs/LIFTING-SPEC.md](./LIFTING-SPEC.md) (MAX-109); what follows is only the part that
supersedes or amends the PRD. **None of it is built yet** — these amendments describe the
target the MAX-110–125 tickets work toward, and are recorded now so that no ticket has to
re-derive them, and so that A16's narrow scope and A20's refusal cannot be lost.

One fact reframes all six and belongs at the top: **strength workouts are already being
captured and already being scored.** Nothing in the ingestion pipeline filters by activity
type, so every lift since MAX-033 has been stored with its heart-rate curve, enriched
against the *running* plan's cap, classified `.other`, and scored — by
`StandardPlanSeed`'s unconditional `fallback.recorded` band at 40–69 against a threshold of
70, or, when its average heart rate cleared cap + 8, by `easy.wellOverCap` at 20–45 with
the rationale *"Well above the easy cap for the whole run."* Those scores are immutable
(D8). So this is not the addition of a feature; it is the correction of behaviour already
in production. See A21.

## A16 — Lifting is in scope. The strength-training non-goal is spent, narrowly.

**Supersedes:** §3's non-goal *"Strength-training analysis. Lifts are submaximal and don't
need HR scoring; deferred, possibly permanently"*, §12's *"Strength-training scoring and
volume tracking"*, and the matching entry in `PROJECT_TRACKER.md`'s "Deliberately not
built".

The plan accounts for lifting and for running. A weekly template prescribes both, a missed
lift costs the athlete something, and the scorer, the calendar, the tallies and chat all
know which discipline a session belongs to.

**Written as its own amendment, and deliberately narrow.** The PRD sentence group being
superseded protects two different things — strength *analysis*, and manual entry. This
amendment spends the first and explicitly does not spend the second; **A20 is the record of
that refusal.** A future ticket that adds a sets-and-reps field should be refused on A20's
authority, not admitted on A16's.

The "Deliberately not built" list exists, in its own words, "so nobody helpfully adds one".
This is the deliberate spend, in the same spirit as A10.

## A17 — The prescription is indexed by discipline. One plan, one version.

**Amends:** D1's plan shape and §8's `plan` / `plan_day` schema. **Supersedes nothing.**

`Discipline` is a **closed two-case** core vocabulary — `.run` and `.lift`. A weekly
template prescribes exactly one `ScheduledSession` per **(weekday, discipline)** pair, and
a resolved `PlanDay` therefore carries exactly two sessions. **A workout is only ever
evaluated against the session of its own discipline**, which is what makes it impossible
for a lift to match a band written about an easy run.

Four properties this preserves, each of which was load-bearing before:

1. **Totality.** Rest is explicit on both slots, so resolving a day to its ask is still a
   total function in both arguments. `WeeklyTemplate`'s own reasoning — a partial template
   pushes an "I don't know what today is" case into the scorer, which §13 names as the
   load-bearing risk — now applies twice rather than being weakened once.
2. **One version.** There are never two plan records in effect on one day.
   `Score.planVersion`, `DerivedMetrics.planVersion`, `PlanCalendar.plan(on:)` and the
   context builder's coherence guard all stay singular, and "what plan was I on in March"
   keeps one answer. Revising the lifting block restates the running block — which is what
   changing any other field already costs, and `PlanAuthoringSession` already carries the
   rest forward verbatim.
3. **No migration, no historical change.** The plan is stored as a JSON blob, and the lift
   slot decodes with `decodeIfPresent`, defaulting to rest on every weekday. A plan
   authored before lifting existed decodes to "this plan prescribed no lifting" — which is
   exactly what it meant. **No stored prescription changes and no historical score becomes
   irreproducible.** This is an acceptance criterion, not an assumption.
4. **A closed set.** Adding a third discipline is an amendment, not a ticket — the same
   discipline A12 imposes on chat subjects, for the same reason. Cycling, swimming and
   mobility stay `.other` sessions in the run slot, which is what they are today. This is
   not a multi-sport model.

**No numeric lifting progression.** `Plan` grows no lifting analogue of `LongRunArc` in v1,
because a progression's target would be a load or a volume and A20 says neither is
obtainable. Lifting is expressed as sessions in the template plus goal statements in
`PlanGoals`. If A20 is ever overruled, a lifting arc is additive to the record in exactly
the way the slot above is.

## A18 — A metric that cannot mean anything for a discipline is not computed.

**Amends:** §9's derived-metric definitions.

Absence and meaninglessness are different, and the app currently confuses them.

- **Absent** — the measurement was not taken. An indoor run has no grade-adjusted pace.
  `nil` is honest, and this codebase treats absence as first-class throughout.
- **Meaningless** — the measurement *can* be taken and the number describes nothing.
  `DerivedMetricsCalculator` derives average cadence from step count over duration with no
  discipline gate, so a lifting session yields a steps-per-minute figure — walking between
  racks — that is drawn against a 165–170 running band and printed to Claude as "Average
  cadence". **That is a fabricated number that looks measured**, which is the failure D2
  exists to prevent, arriving through a metric nobody thought to gate.

So the rule is not "share the record and let fields be absent". It is: **the calculator
does not compute a metric that cannot mean anything for the workout's discipline, and the
reason is legible where the absence shows.**

**One record, two computation paths.** `DerivedMetrics` stays a single stored type, with
lifting metrics added as optional fields — additive columns, no non-optional without a
default, per the CloudKit discipline A8 requires be kept. A parallel record would buy
nothing and cost a second thing every loader has to remember.

The same rule reaches the prompt: a lift's fact sheet carries no cap line, no cadence line,
no pace line and no splits section — absent, not rendered as "—", because a heading whose
only content is that it does not apply is prompt tokens spent on nothing. One module, one
entry point, one renderer with a discipline branch: **A12 is unchanged.**

## A19 — Effective days count obligations, not days.

**Amends:** FR-3.4 (the tallies), D9 (the rest-day budget), and D4's day-level roll-up.

A Tuesday prescribing a run and a lift is **two** obligations, and this is the amendment
that makes skipping the lift cost something.

- **Tallies.** `EffectiveDayTally` counts prescribed sessions, not days. Each obligation is
  effective independently, by the same ledger rule as today (the manual annotation where
  one exists, else the auto-score), against the workouts of its own discipline.
- **Two attempts at one obligation still resolve generously.** A warm-up jog plus a real
  run is one obligation met, judged by the better session — that reasoning is unchanged and
  must stay unchanged. What changes is that *two obligations* are no longer satisfied by
  meeting either one, which would make lifting decorative.
- **The streak is all-of at the day level.** A day breaks the streak if any obligation was
  missed-and-unconverted or scored below threshold; it extends the streak if it had at
  least one obligation and met every one. "Was every attempt at my run good" and "did I do
  everything the plan asked today" are different questions and get different answers.
- **The rest-day budget spends on obligations** (D9, A6). Converting a whole day would
  forgive the run the athlete also skipped — a budget buying more than it was sold for.
  `RestDayBudgeting`'s cost ordering gains `.lift` **without reordering the existing
  cases**, since the tiers are ordinal and a reorder would silently rewrite the calendar's
  past.
- **The calendar rolls up to one verdict per cell** (D4). A cell cannot honestly carry two,
  and the visual budget is already spent (MAX-084's band mark, MAX-087's size channel,
  MAX-105's prescription substrate). **A day where the run scored effective and the lift was
  missed is not a green day**: `.scored` still outranks the ask for *its own* obligation,
  and no longer outranks a different obligation's miss.
- **One resolver.** The day roll-up the calendar draws and the obligation tally the tile
  reads come from the same core function. Two implementations of "was this day fully met"
  is D2's drift with a colour attached.

**The property that makes this landable: on any day prescribing at most one session,
per-obligation and per-day counting are identical.** Every day in the athlete's history
prescribes at most one, so **no historical figure moves** — and that is an acceptance
criterion with a fixture suite behind it, not a hope.

**What it does cost, plainly.** The effective-days tile's denominator changes meaning for
future two-discipline weeks: `4/5` becomes `6/8`. That is a visible change to a number the
athlete already reads, and it needs a line of copy rather than silence.

## A20 — Lifting is scored on adherence, not volume. Manual entry stays a non-goal.

**Reaffirms:** §3's non-goal *"Manual entry, editing, or a general logging UI. The thing
being killed"*, and §2's north star, against the pressure A16 creates.

**HealthKit carries no load.** A strength workout supplies start and end, duration, active
energy, the per-sample heart-rate series, and a step count that means nothing. There is no
quantity type for repetitions, sets, or weight lifted; watchOS's own Workout app does not
capture them; a third-party lifting app writes only a summary workout. (Verified against
HealthKit as documented; **not** verified against the iOS 26 SDK from a container with no
SDK — MAX-112 must check the current type list and say what it found.)

So the choice is stark: either lifting is scored on what was captured, or the athlete types
sets and reps.

**Decision: it is scored on what was captured.** A prescribed lift performed on the
prescribed day, of at least a fraction of the prescribed duration, scores well; a short one
scores less; a missed one is a missed obligation under A19. No rubric band references a
load or a volume, because no such number exists in the record.

Three reasons, in order of weight: it is genuinely what the ask needs — the request is that
skipping the lift *cost something*, and adherence delivers that zero-touch; a volume rubric
would oblige the app to become a lifting logger (exercise library, previous-session recall,
rest timer), and §13 names scope discipline as the top execution risk above any technical
unknown; and the scoring the app *can* do here is honest, where the scoring it cannot do
would be a guess.

**The cost, stated plainly.** Adherence scoring cannot tell a hard session from a token
one. Forty-five minutes of moving light weights scores like forty-five real minutes. If the
owner's actual complaint is that their lifting is not progressing, this does not address
it, and nothing reading only HealthKit can.

**Tripwire.** If manual entry is ever admitted for lifting, it is admitted *as an
amendment superseding §3*, with a scoped answer to what else the app then owes the athlete
— never as a text field arriving inside a lifting ticket. "It is only two numbers" is how
the thing the product exists to kill comes back.

**Not manual entry, and worth distinguishing:** an athlete who already logs lifts in a
third-party app that writes to Health is captured today, unchanged, with zero taps. That is
the product working as designed. It still yields no load data, so nothing above changes.

## A21 — Scores written before the plan distinguished lifting stand. D8 is not weakened.

**Clarifies:** D8. It supersedes nothing.

Every lift already ingested carries an immutable auto-score produced by applying a running
rubric to it — 40–69 from the seed's unconditional fallback band, or 20–45 from
`easy.wellOverCap`, which carries no classification condition and therefore fires on any
workout whose average heart rate clears cap + 8. Those scores are in the average-score
tile, in the calendar, and in the chat context.

**D8 forbids overwriting them and this amendment does not create an exception.** But the
reason D8 exists is that auto-versus-manual divergence measures *scorer quality* (§2), and
these are not scorer misjudgements — the model was handed a category error and did its job.
Counting them as scorer error corrupts exactly the telemetry D8 protects.

**The decision recorded here: they stand, and they are labelled.** Where such a score is
shown — the verdict header, the calendar's VoiceOver sentence — the app says it was
assigned before the plan distinguished lifting. That costs one string and no stored record.

Rejected: annotating them (additive by the letter of D8, but an annotation means *a human
corrected this*, and manufacturing them poisons the correction-rate metric worse than
leaving the scores alone); and a narrow exception to D8 for scores whose scheduled kind and
workout discipline disagree (honest, and the first crack in an invariant that has held all
project).

**This one is flagged as an owner/overseer call rather than settled by a ticket**, and it is
tracked as MAX-125. Fixing `StandardPlanSeed`'s bands does not retroactively fix a stored
plan either: the athlete must author a revision for the corrected rubric to govern
anything.

---

## A22 — Muscle groups are entered by hand, on the workout. The manual-entry non-goal is spent, narrowly.

**Supersedes:** PRD §3's non-goal *"manual entry/editing"*, for this one field only.

**Decision (owner, 2026-08-05):** *"you can set the muscle group in the detail view of the
workout if it is strength training."*

A17 lets a plan prescribe muscle groups. Nothing could check it: HealthKit reports
`traditionalStrengthTraining` and says nothing about what was worked, which is the same wall
A20 hit choosing adherence over volume. MAX-144 costed three ways out; this is the owner
taking the first, and it is the only one that makes a lift's prescription a **standard**
rather than documentation.

**The non-goal is spent deliberately, and narrowly**, the way A10 was. It buys exactly one
field, on one kind of workout, entered after the fact on the screen where you are already
looking at that session. It does **not** open manual entry of workouts, distances, durations,
heart rates or scores — every one of those still comes from HealthKit or from the scorer, and
a later ticket proposing otherwise does not inherit this amendment's permission.

### What it forces, and this is the load-bearing part

**A lift cannot be scored at ingestion.** D2 computes metrics once when a workout arrives;
D8 makes an auto-score immutable. But the muscle groups arrive *later*, whenever the athlete
opens the detail screen — so a lift scored at ingestion would either be scored against
information nobody had yet, or need revising afterwards, which D8 forbids outright.

So: **a lift is not scored until the athlete says what they trained.** Until then it is
neither awaiting a model nor permanently unscoreable — it is **awaiting the athlete**, which
is a third state and a better one, because it is the app asking a question rather than
guessing an answer. MAX-126 established `noVerdict` for "there will never be a verdict";
this needs its sibling.

That state is also the feature's own prompt. A lift sitting on the calendar saying *"tell me
what you trained"* is how the athlete learns the field exists, and it costs no onboarding.

### Where the entry lives

**Not on `Workout`.** That record mirrors what HealthKit reported and nothing else writes to
it; putting athlete-supplied data there would make it two things at once. This is
athlete-supplied truth *about* a workout, which is the shape `ScoreAnnotation` already has —
additive, timestamped, never overwriting what was captured (D8's own discipline, applied to
an input rather than to a verdict).

**A lift with no groups entered is not zero groups.** Absence is first-class in this codebase
and the distinction matters here: "I have not told you yet" and "I trained nothing" are
different, and only the first should prompt.

## Requirements unaffected

Everything in §7 (features), §9 (metric definitions), §10 (scoring logic), §13 (risks)
stands as written. The scoring rubric, the derived-metric definitions, and the design
direction in §7.4 are unchanged by the move on-device.

§9 and §10 are amended for lifting by A18 and A20 respectively; both stand unchanged for
running.

# Chat-first — product specification

**Ticket:** MAX-090
**Date:** 2026-08-05
**Status:** proposal. Nothing here is built.
**Deliverable:** this document plus amendments A9–A15 in
[docs/PRD-AMENDMENTS.md](./PRD-AMENDMENTS.md). **No view code and no core code was
written.**

> **Two overseer edits on landing.** §11's tickets were proposed as MAX-091–103 and are
> renumbered **MAX-092–104**, because MAX-091 was taken by the tier change that landed while
> this was being written. And §8.3's open question about which model to run is **closed** —
> the owner answered it (Sonnet at `medium` effort, both clients), so §8.1, §8.2, §8.3 and
> §12's row 5 now record the answer and its consequences rather than the question. Nothing
> else in the document was altered.

---

## What this document is, and what it cannot be

**I have not seen this app.** There is no Swift toolchain in this container, no
simulator, and no device anywhere in this project's CI (tracker R1, R2). Every claim
below about *what the app does today* is read from source — `Sources/MaximizeCore/`,
`App/`, the PRD, the amendments, MAX-082's design review. Every claim about *what it
looks like* is inference from committed values and view structure. The owner is the
only person who has used the thing.

Where a decision depends on something I cannot verify — how an iOS 26 API behaves,
whether a floating control reads well over a near-black background, what a Claude call
actually costs at this shape — it says so in the text and appears again in §12.

I separate **decisions** (where I resolved a tension and will defend it) from
**recommendations** (where I have a view and the owner should overrule me freely). Every
place I am arguing against a reading of the request is marked and says why.

---

## 0. The shape, in six sentences

Chat is **additive**. The dashboard and the workout detail screen remain the way numbers
are read, and the owner's ask is that they get *denser*, not thinner. A persistent Liquid
Glass **Ask** button floats above the tab bar on every screen, opening a chat sheet with
thread history and a new-thread action. Chat has exactly three jobs — **generate a plan**,
**read a plan**, and **ask questions about the data** — and everything else stays a screen.
A thread has a **subject**, either one workout or the athlete's training over a fixed
interval, and the subject is what decides which of the athlete's data enters a prompt.
Because both surfaces now describe the same numbers to the same person, **a figure quoted in
chat that contradicts the tile behind it is the failure mode this design is built to make
impossible** (§3.6).

---

## 1. Scope, as settled

The owner's words: *"i want highly detailed dashboard views and workout detail views. but I
want to be able to generate my plan, view my plan through the chat interface. I want to be
able to ask questions about my data through the chat."*

That settles the question this document might otherwise have spent its length on. **The
screens are not demoted.** PRD §5's dense-and-quantitative brief and §7.4's numerals-do-the-
hierarchy-work are reinforced, not softened. Nothing below proposes shrinking, hiding, or
replacing a chart with prose.

### 1.1 The three jobs, and what each one needs

| Job | Why chat and not a screen | Load-bearing decision |
|---|---|---|
| **Generate a plan** | Authoring a 16-week plan through seven weekday pickers and a 16-row arc is the least pleasant screen in the app (`App/Plan/PlanAuthoringView.swift`, 419 lines of form). Describing it in a sentence is how a person actually thinks about it | §4 — the model emits a **proposal**, never a plan; MAX-080's door is the only door |
| **Read a plan** | The plan is the reference every score is measured against, and today it is legible *only while you are editing it* | §5 — chat answers plan questions, **and the plan also gets a screen**. Argued, because this is the one place I am adding something the owner did not ask for |
| **Ask questions about the data** | Interpretation. "Why did my HR climb", "has drift flattened" — questions no chart answers, about data every chart shows | §3 — what a workout-less thread may see, and the agreement property in §3.6 |

### 1.2 What "highly detailed" promotes

The densification work is MAX-082's board, not this ticket's, and I am not doing it. But
"highly detailed" being an explicit product requirement rather than an inference **changes
the status of two of that review's findings**, and the overseer should know:

- **§4.1 — the numeric score on the workout row.** The review filed this as *taste* with a
  defensible counter-argument. Under an explicit "highly detailed" brief it is no longer
  taste: the app's opening screen currently answers "when did I run and how far", which PRD
  §1 says Apple Fitness already answers. The uncoloured score at `.metricSecondary` (the
  review's own proposal, which keeps FR-4.3's three-colour restriction intact) becomes a
  requirement.
- **§2.1 — the 1.09:1 surface ramp.** Density is legibility-limited. A screen carrying more
  numbers needs its cards to have edges more than a sparse one does, not less. T3 moves up.

Neither is in this document's diff. Both belong to the review's board.

---

## 2. The product shape

### 2.1 Entry point

One entry point, everywhere, in the same place: a floating capsule pinned bottom-trailing
above the tab bar, `.glassChrome(.floatingControl)`, carrying an icon and a short label.

It is **subject-aware**. On the Workouts list, the Dashboard, the plan screen or Settings it
reads **"Ask"** and opens a training thread. On a workout detail screen it reads **"Ask
about this run"** and opens that run's thread. The label is not decoration: it is the only
thing on screen telling the athlete which pile of their own data is about to be sent
somewhere, and that is worth the pixels.

**This replaces, rather than joins, the existing chat entry point.**
`App/Workouts/WorkoutChatSectionView.swift` currently renders a card with an "Open chat"
button. Two chat buttons on one screen, six inches apart, opening the same conversation, is
worse than either alone. The card stays and becomes what design review §4.4 asked for — a
preview of the last exchange, or the invitation copy — and loses its button.

### 2.2 The sheet

A full-height sheet (chrome; the system supplies its own glass — `App/SettingsToolbar.swift`
already documents why we do not re-apply it). Structure:

| Element | Behaviour |
|---|---|
| Leading toolbar button | Opens the thread list (§2.3) |
| Title | The thread's derived title (§2.4), inline |
| **Subtitle** | **The thread's scope, stated.** For a training thread, the resolved date range; for a workout thread, the run. Load-bearing, not decorative — see §3.6 |
| Trailing | **New chat** — training subjects only; absent for a workout subject (§3.4) |
| Trailing | **Done** — dismisses, releasing focus first, exactly as `WorkoutChatView` does today |
| Transcript | Unchanged from MAX-081: its own `ScrollView`, `.scrollDismissesKeyboard(.interactively)` |
| Runs strip | For a training thread, a horizontal strip of the runs whose figures are in this thread's context, each tappable through to its detail screen (§6.2) |
| Composer | Unchanged: a bottom `safeAreaInset`, so the keyboard lifts it as a unit |

**Which thread opens.** The most recently active thread for the current subject, or a new
empty one if there is none. Not "the last thread you had open regardless of subject" —
tapping Ask on a workout screen and landing in last week's mileage conversation would be the
app losing track of what you are looking at.

### 2.3 The thread list

A pushed screen inside the sheet. Rows, newest activity first: derived title, subject glyph
(a run glyph for a workout thread, a chart glyph for a training thread), a relative
timestamp, one line of the last message. Swipe to delete.

Deliberately **not** a third tab and not a top-level destination. The tab bar advertises the
app's parallel modes — `App/RootTabView.swift` says so, and MAX-081 removed Settings from it
on exactly that reasoning. "The list of my past conversations" is not one of them.

### 2.4 Titles

Derived in `MaximizeCore`, never generated:

- **Workout thread** — the run's date and activity type. There is one per run, so it must
  identify the run, not the conversation.
- **Training thread** — the first user message, truncated on a word boundary. Before there
  is one, the resolved interval label (`TrendIntervalFormatting.label(for:)` already
  produces one).

**A model call to title a thread is rejected.** One call per conversation for a string
nobody reads twice, against a key the owner pays for (§8), and a second place that decides
what a conversation is about. Renaming by hand is a later ticket, not a v1 gap.

### 2.5 What a thread does not do

**It does not write.** Chat proposes; the athlete taps. Concretely: chat may not record a
score annotation, may not convert a rest day, may not store a plan version, may not change a
setting. The only write a chat turn performs is appending its own completed turn to its own
thread. §9 explains why this is an invariant rather than a scoping choice.

---

## 3. Context — D3, resolved. One of the two load-bearing decisions.

### 3.1 The problem, stated precisely

`WorkoutContextBuilder.build` takes a workout, its metrics, its classification, a plan
calendar and (for chat) its score, and returns a `WorkoutContext` that renders to a fact
sheet. It is the single assembler, and CLAUDE.md makes that a rule: *"never assemble prompt
context anywhere else."*

A thread about "has my drift flattened this month" has no workout. There is no context to
build. The two obvious escapes are both wrong:

- **Build N workout contexts and concatenate.** A month at fact-sheet fidelity is a dozen
  runs × (plan block + measured block + ten-bucket HR shape + every kilometre split). An
  enormous prompt, and — far worse — the athlete's entire recent movement record, at the
  finest resolution the app stores, leaving the device because they asked a one-sentence
  question. A chat that can see everything is a chat that sends everything, and this is the
  shape that does it.
- **Let something else assemble it.** Forbidden, for a good reason: two notions of what
  Claude knows drift, and the drift is invisible until a number in a bubble disagrees with a
  number on the screen behind it. Which, per §3.6, is now a *user-visible* failure rather
  than an internal one.

### 3.2 Decision: D3 is generalised, not weakened

There remains exactly one context module, `Sources/MaximizeCore/Context/`, with **one entry
point**:

```swift
public enum ContextBuilder {
    public static func build(for subject: ChatSubject, /* stored inputs */) throws -> PromptContext
}

public enum PromptContext: Hashable, Sendable {
    case workout(WorkoutContext)
    case training(TrainingContext)

    public func factSheet() -> String    // dispatches; the only renderer either case has
}
```

`WorkoutContextBuilder.build` is unchanged and is called *by* this. The scorer keeps calling
it directly, byte for byte, so the scorer and the workout chat still cannot diverge — which
is the divergence D3 exists to prevent.

**Is `TrainingContext` a second assembler?** No, and the distinction matters enough to write
down. D3's guarantee is *one assembler per subject, shared by every consumer of that
subject*. The workout subject has two consumers (scorer, chat) sharing one builder. The
training subject has one consumer and nothing to diverge from. What must not happen — and
what A12 makes a rule — is a second *place*: no view model, no transport, no App-layer
helper may compose prompt text. Two cases in one module behind one entry point is one place.

**One thing must be enforced mechanically or this claim rots.** The two fact sheets must
render the same measurement identically. If `WorkoutFactSheet` prints drift as `+4.2%` and a
training roll-up prints `4.2 %`, D3 has failed at the only boundary that matters even though
there is still "one module". So `WorkoutFactSheet.swift`'s private formatters — `bpm`,
`distance`, `duration`, `pace`, `percent`, `signedPercent`, `number`, and the
locale-pinned-to-nil discipline that goes with them — move to an internal
`FactSheetFormatting` used by both renderers, with a test asserting a figure formatted by
one path equals the same figure formatted by the other.

### 3.3 What a training thread may see

**A roll-up, not a stack of fact sheets.** `TrainingContext` carries exactly four things:

1. **The plan in effect** — version, HR cap, cadence band, weekly template, current arc week
   and its prescribed distance, goals, both score thresholds. This is the athlete's own
   configuration, not a measurement of their body. It is also what makes an answer worth
   having: "am I on plan" is unanswerable without the plan, and it is what job two (§5)
   reads from.
2. **The tallies over the scope** — workout-days, effective-days and eligible-days, average
   score, current streak, current training week. Produced by `TalliesCalculator`, which
   already computes these from stored scores and honours annotations and rest-day
   conversions. Nothing recomputed (D2). See §3.6 — *these must be the same values the
   dashboard tiles read, from the same function.*
3. **One line per run in scope**: date, weekday, classification, scheduled session, distance,
   duration, average heart rate, drift fraction, score, band. That is it.
   - **No heart-rate shape.** The ten-bucket curve is what lets a single run's fact sheet
     answer "why did it climb after mile 3". Across twelve runs it is 120 numbers answering
     a question nobody asked in a training thread.
   - **No splits.** MAX-068 sent them, once, for one run, and its own documentation calls a
     split series "a finer-grained record of one person's movement than anything else in the
     prompt". Twelve of them is not a marginal increase.
   - **No route, no coordinates.** `WorkoutContext` already gives the reasoning: a month of
     them is a home address and a routine.
   - **No score rationales.** The prose the scorer wrote per run is not needed to see a
     trend, and it invites the model to argue with a stored verdict (§9, D8).
4. **The scope itself**, stated in prose — and, when runs were dropped by the cap, how many
   and why.

**Bounded twice over.** The scope bounds it in the ordinary case; a
`TrainingContext.maximumRenderedRuns` constant guards a corrupt record, exactly as
`WorkoutContext.maximumRenderedSplits` does. Beyond the cap the context states the count and
lists none. Health data leaving the device must never be sized by a number nothing has
validated.

**What this costs, plainly.** This pivot increases what leaves the device. Today one run's
facts leave when the athlete opens a thread and types. After this, a summary of up to N runs
leaves per training-thread turn. That is a real change to the privacy posture and no amount
of "it's still on-device by default" makes it not one. The mitigations are the four bounds
above plus §8.4's invariant that no chat call is ever unattended. **Every ticket touching
`Context/` or a prompt gets a `/security-review`**, per CLAUDE.md, no exceptions.

### 3.4 Who decides the scope

Not the model, and not a date field the athlete must fill in before they can ask a question.

**Decision: the scope is inherited from the app's existing interval control, resolved to
absolute days at thread creation, then frozen on the thread.**

- Opened from the Dashboard, a new training thread takes the currently selected
  `TrendInterval`'s `from`/`through`. The app already has one control for "what period are
  we talking about" and it is on screen; a second control inside the chat sheet would be two
  notions of scope, which is the same class of mistake D2 and D3 exist to prevent.
- Opened from anywhere else, the same default `TrendIntervalModel` uses.
- The resolved days are stored on the thread. They do not slide.

**Why frozen.** A thread is a conversation about a bounded set of facts. If the window slid
with the calendar, an answer given last Tuesday would cite runs no longer in context, and
scrolling up your own transcript would show the assistant contradicting the app. Freezing
makes a thread reproducible, and gives **New chat** a real job: a newer window is a new
conversation.

Not frozen: the context is rebuilt from stored data on every load, so runs ingested *inside*
the window after the thread started do appear. Only the boundaries are fixed.

**This design introduces a way for chat and the dashboard to disagree, and §3.6 is how it is
closed.** Freezing is right, but a frozen July thread answering while the dashboard shows
August is exactly the ambush the owner's clarification says to design against.

### 3.5 What the model is told it cannot do

`ChatInstruction.task` for a training thread is a new string (the workout one stays as it is)
and must state at least:

- Answer only from the summary provided; never invent a figure.
- **Always name the window when quoting an aggregate** (§3.6).
- The per-run summary is a summary. Per-kilometre detail and one run's heart-rate curve are
  not here; the honest answer to a question needing them is to say so and point at that
  run's own conversation.
- The scores shown are already assigned and are not up for revision (D8, §9).
- No medical advice.

That is prompt text and a product decision, which is why it belongs beside the chat feature
and not in the transport — the precedent `ChatInstruction`'s documentation sets and
`WorkoutChatModel.task` already follows.

### 3.6 The agreement property — chat and the screens must not be able to disagree

The owner's clarification promotes this from an internal invariant to a user-visible
property, and it deserves its own mechanism rather than a good intention.

**Three ways they could disagree, and the fix for each.**

**(a) Chat computes instead of reading.** A helper that averages some drift figures inside
`TrainingContext` to save a call into the tallies is D2's drift arriving in a prompt, where
nothing on screen contradicts it and nobody notices.

> **Rule.** Every aggregate in `TrainingContext` is produced by the *same core function the
> corresponding screen reads*. Effective days, average score, streak, workout-days and the
> current week come from `TalliesCalculator`. A drift slope, if ever wanted, comes from
> `HeartRateDriftTrendlineData`'s fit — the same computation `DriftOverlayView` draws.
> `TrainingContext` contains no arithmetic over more than one workout.

> **Test.** Build a `TrainingContext` and a `TrendTileData` over the same interval from the
> same stored inputs and assert the figures are equal. That is a plain unit test in the core,
> it runs on every commit, and it is the difference between claiming the property and having
> it. It is an acceptance criterion of MAX-095, not a nice-to-have.

**(b) Same numbers, different windows.** The thread's scope is frozen (§3.4); the dashboard's
is not. Same source function, different arguments, two different correct answers that look
like a contradiction.

> **Rule.** The window is stated everywhere it could matter: as the sheet's subtitle, as the
> runs-strip header, and inside every aggregate sentence the model produces (§3.5). A thread
> whose scope no longer matches the dashboard's current interval shows a quiet one-line note
> offering to start a new chat on the current interval.

> This does not prevent the mismatch — freezing is deliberate — it makes it *legible*, which
> is the achievable goal. An ambush becomes a labelled difference.

**(c) Same numbers, different rounding.** The fact sheet formats with `%.0f` / `%.1f` and
locale pinned to nil; the screens format through `WorkoutDisplayFormatting` and the
`Font` tokens' `monospacedDigit`. "74" against "73.6" is a disagreement to a reader even
though both are the same stored double.

> **Rule.** Where a figure appears in both a tile and a fact sheet, the fact sheet renders it
> at the tile's precision or coarser — never finer in a way that implies a different value.
> The formatter extraction in §3.2 is what makes this checkable in one place.

This is the clearest reason the roll-up in §3.3 is the right shape, quite apart from privacy
and cost: **a summary built from the same functions the screens read cannot contradict them.
A stack of freely-worded per-run prose could.**

---

## 4. Generating a plan through chat — D1, resolved. The other load-bearing decision.

### 4.1 The boundary

D1 says the plan is versioned *data* whose immutability makes historical scores reproducible.
Generating a plan is an *authoring* act. Those are compatible, and MAX-080 already built the
machinery that keeps them so:

- `PlanDraft` is mutable and **cannot become a `Plan` by itself** — there is deliberately no
  `PlanDraft.plan()`.
- `PlanAuthoringSession.plan(from:effectiveFrom:)` is the only door. It stamps the version
  number and validates the effective date against MAX-011's ordering rules by constructing
  the `PlanCalendar` the write would produce.
- `PlanRepository.store` re-runs the same check before touching disk.

**Decision: the model emits a `PlanProposal`, the proposal becomes a `PlanDraft`, and the
draft goes through the existing door.** The model does not route around MAX-080; it feeds it.

### 4.2 What the conversation actually is

The athlete describes the plan in prose, over as many turns as they like, in an ordinary
streaming training thread:

> *"16 weeks, half marathon on 15 November. Four runs a week. I can't run Mondays. Keep the
> long run on Sunday and build it to about 30k."*

The thread already carries the training context (§3.3) — including their **current** plan,
if any, and how they have actually been executing it. So a revision conversation can be
about the difference (*"the Thursday easy run is always over cap, drop it to 6k"*) rather
than a re-specification from nothing.

A **"Draft a plan from this conversation"** action then produces a proposal. See §4.7 for
why that is a separate action rather than something the model emits mid-stream.

### 4.3 What the model emits

`PlanProposal` is `Codable` and deliberately weakly typed, in the same spirit as
`ScoreProposal` — a bare `Int` so an out-of-range answer survives parsing and can be refused
on its merits rather than collapsing into "the JSON did not decode". It carries exactly the
fields `PlanDraft` carries:

- `heartRateCapBPM`, `cadenceLow`, `cadenceHigh`
- `effectiveThresholdPoints`, `marginalThresholdPoints`
- seven weekday sessions: kind, optional distance in metres, optional note
- the long-run arc: an ordered list of week index and distance in metres
- goal statements

### 4.4 What the model may not emit, and why each one

| Not emitted | Why |
|---|---|
| **`version`** | Derived by `PlanAuthoringSession` as the successor of the highest stored version. A version number anything can propose is a back-dated version waiting to happen — `PlanDraft`'s own doc comment says exactly this about a *screen* offering one, and a model is no more trustworthy than a text field |
| **`effectiveFrom`** | Same. The session derives `suggestedEffectiveFrom` and `earliestEffectiveFrom`; the athlete may move the date within the permitted range on the authoring screen, where `permitsEffectiveFrom` bounds the control. **A back-dated `effectiveFrom` is therefore not a failure mode that can occur** — not "is validated and rejected", but *cannot be expressed* |
| **Rubric bands** | The bands are the ordered conditions that decide what every future run scores. A hallucinated condition there does not produce a visibly wrong plan; it produces a plan that looks fine and quietly mis-scores for sixteen weeks. `PlanDraft` already excludes them because editing them needs a structured rule editor, and `PlanAuthoringSession` carries them forward verbatim from the superseded version precisely so a revision never re-seeds a rubric the athlete tuned. **"Generate the plan via AI" should mean the plan the athlete has an opinion about, not the scoring machinery.** A future `RubricBandProposal` over a closed condition grammar is its own ticket and its own argument |

### 4.5 What happens when the model emits something invalid

`PlanAuthoringError` already exists, already has athlete-readable text, and already covers
every failure this can produce: `heartRateCapImplausible`, `cadenceBandInverted`,
`cadenceBandNotPositive`, `thresholdsInverted`, `scoreThresholdOutOfRange`,
`scheduledDistanceNotPositive`, `longRunDistanceNotPositive`, `wouldRewriteHistory`.

1. Parse fails, or the proposal does not convert → **one** automatic retry with the error's
   `description` appended to the instruction. One, not a loop: a loop burning the owner's
   tokens against a model that keeps proposing a 400 bpm cap is the failure mode to design
   against.
2. Second failure → the athlete sees the error text, and the authoring screen opens on the
   seed or current draft, unchanged. A failed feature leaves them exactly where MAX-080
   already puts them rather than nowhere.
3. A proposal that converts but that the athlete dislikes is a prefilled form. Every field
   stays editable. This is the ordinary case and it is why the handoff target is the existing
   screen and not a confirm dialog.

`wouldRewriteHistory` is documented as unreachable in practice and kept as a belt-and-braces
alternative to a `try!`. It stays unreachable here, because the model supplies no date.

### 4.6 The proposal card — and why it renders a diff

The proposal appears in the transcript as a card, not as prose, and for a revision it renders
as a **diff against the current version**: what changed, per field, old → new.

This is the affordance that makes an unrequested change visible. A model asked to drop
Thursday to 6 km may also, helpfully, move the cap to 148 — and in a full re-statement of the
plan that edit is invisible among fourteen unchanged fields. A diff makes it one highlighted
row. For a first plan there is nothing to diff against, so the card renders the plan itself.

The card's action opens `PlanAuthoringView` prefilled, with the same governed-days preview
`PlanAuthoringSession.governedDays` already produces — which is the screen's existing
confirmation half, and the only way to catch an arc starting on the wrong week.

### 4.7 How a proposal is obtained

**Recommended (Phase A): a separate one-shot call.** The transcript so far, plus the training
fact sheet, plus the schema, go to a non-streaming call whose reply is parsed into a
`PlanProposal`. This reuses the exact pattern `ScoringModelInvoking` / `ScoreProposal` /
`WorkoutScorer` established — a protocol returning raw text, a parser tolerant about
formatting and strict about content, validation owned by the core:

```swift
public protocol PlanProposalModelInvoking: Sendable {
    func reply(to instruction: PlanProposalInstruction) async throws -> String
}

public struct PlanProposalInstruction {   // same three-way split, same cache story
    public let task: String
    public let schema: String       // PlanProposal.schemaDescription — no health data
    public let factSheet: String    // TrainingContext, verbatim, the only PII
    public let turns: [ChatTurn]
}
```

**Deferred (Phase B): a proposal emerging mid-stream.** Nicer — the model replies in prose
and attaches a proposal — but it needs either tool use (a new transport surface on
`AnthropicStreamingChatClient`) or fenced-JSON detection inside a streaming bubble. Both are
real work for a better feel rather than a new capability. Phase A delivers conversational
authoring; Phase B is an upgrade to it, not a prerequisite. §12.

### 4.8 "Context about plan specifications" — where that text lives

The owner's phrase covers two different things living in two different places.

**(a) What a plan *is*** — the vocabulary and the constraints. Every `ScheduledSessionKind`,
that the week is Monday-first, that arc weeks are indexed from 1 and strictly ascending, that
distances are metres, that the cap must fall inside `HeartRateSample.plausibleBPM`, that
thresholds must fall inside `ScoreValue.permittedRange` and that the marginal one must not
exceed the effective one, and the response shape itself.

**This must not be hand-written prose, or it becomes a second source of truth that drifts the
first time somebody adds a session kind.** It is *generated from the core types* —
`ScheduledSessionKind.allCases`, `Weekday.allCases`, `HeartRateSample.plausibleBPM`,
`ScoreValue.permittedRange` — and it lives beside the type it describes, as
`PlanProposal.schemaDescription`, following the precedent
`ScoreProposal.responseFormatDescription` sets, for the reason that file gives: *"it lives
beside the type it describes so the instruction and the decoder cannot drift apart."*

A test pins that every case of every enum it enumerates appears in the rendered text. Adding
a session kind and forgetting the prompt then fails CI, rather than silently producing a
model that cannot propose the new kind.

**(b) The athlete's current situation** — their current plan version's contents, their recent
execution, their goals. That is the training context from §3, reused unchanged. No new
assembler.

### 4.9 No third audience

`WorkoutContext.Audience` is a **health-data minimisation switch** and must stay one. The
plan-schema text carries no health data, so it travels in the *instruction*, next to `task`,
exactly as `ChatInstruction` already separates `task` from `factSheet`.

Invariant worth stating because it is the kind that erodes: **`Audience` selects what health
data leaves the device; `task` selects what the model is asked to do. Never conflate them.**

### 4.10 The one-sentence summary of §4

**Nothing the model emits reaches disk without passing through
`PlanAuthoringSession.plan(from:effectiveFrom:)` and without a human tap.** D1 is untouched.

---

## 5. Reading a plan — and the one thing I am adding that was not asked for

### 5.1 What exists today

Nothing. `PlanAuthoringView` is reached from Settings and shows a *draft* — the editable
working copy plus a seven-day governed preview. That is authoring, not reading. There is no
screen anywhere in the app that answers "what does my plan say", and no screen at all that
shows a *superseded* version.

### 5.2 Chat can read the plan, and should

The plan is already in the training context (§3.3 item 1), so *"what's my long run this
week"*, *"why is Wednesday hard"*, *"what changed in version 3"* are answerable today under
this design with no extra work. That is job two, delivered.

### 5.3 But chat should not be the only place the plan is legible

**This is the one place I am proposing something the owner did not ask for, so here is the
argument.**

1. **The plan is a table, not a judgement.** Seven weekday rows, sixteen arc weeks, three
   numbers, an ordered rubric. Chat earns its keep where interpretation is needed. A weekly
   template rendered as prose is strictly worse than a weekly template rendered as a table,
   and it is worse in exactly the dimension the owner's clarification prioritises — detail.
2. **It is the reference every other screen depends on.** A verdict header reading
   *"Scheduled: easy, 8.0 km"* is only meaningful against the week it came from. Making that
   a conversation means the answer is re-generated, re-paid-for, unpinnable, and possibly
   worded differently on two askings — for the one artifact in this app that is
   *definitionally fixed data* (D1).
3. **D1's guarantee deserves a surface.** Historical scores are reproducible because old
   plan versions still exist. Nothing in the app shows that they do. A version history is
   the cheapest possible demonstration that the app's central determinism claim is real.
4. **It closes design review §1.1's other half.** MAX-080 gave the owner a way to *author* a
   plan. Nobody gave them a way to *see* one.

**Recommendation: a plan screen, pushed from the Dashboard's navigation bar**, not a third
tab (`RootTabView`'s reasoning stands) and not buried in Settings beside the authoring form.
The Dashboard asks "am I executing the plan"; the plan is the other half of that sentence.

Content, at the density the brief asks for:

| Section | Content |
|---|---|
| Header | Version, effective range, current-or-superseded, goals, target day |
| The two numbers every chart draws | HR cap and cadence band, as `metricPrimary` numerals |
| Weekly template | Seven rows: weekday, kind, prescribed distance, note |
| Long-run arc | Sixteen rows or a small bar chart, with the current arc week marked |
| Rubric | Both thresholds, and the ordered bands read-only — the thing that decides every score in the app and is invisible today |
| Version history | Every stored version with its effective range, tappable to view that version |

All of it read-only. Editing stays where MAX-080 put it, and an "Author a revision" action
opens that screen.

**This ticket is independent of everything else in this document** — it needs only
`PlanRepository` and the existing core types — so it can be dispatched immediately and in
parallel. If the owner disagrees with §5.3 the ticket is simply dropped; nothing else here
depends on it.

---

## 6. The screens, and how chat points at them

### 6.1 Nothing is removed

The calendar, the drift overlay, the trendline, the detail view's verdict header, HR curve,
cadence band, route map, splits and summary tiles all stay exactly where they are. The one
deletion in this whole document is `WorkoutChatSectionView`'s redundant "Open chat" button
(§2.1), and that is a consolidation, not a removal.

### 6.2 Chat linking back to screens

The deterministic version, which I am specifying:

- A training thread's sheet renders a **"Runs in this conversation"** strip below the
  transcript, built from the same `TrainingContext` the prompt was built from. Each chip
  pushes that run's detail screen. No model involvement, nothing to parse — and it makes the
  scope visible, which is a privacy affordance as much as a navigation one, and part of
  §3.6(b)'s answer.
- A workout thread's sheet already sits on top of that run's detail screen; dismissing is the
  link.

Model-emitted inline references — the assistant naming a run and that name being tappable —
need the model to emit stable identifiers and the app to parse them out of prose. Deferred;
§12.

### 6.3 Chat does not become a renderer

Stated as a rule for implementing tickets, because it is the shape this pivot could drift
into: **no chat surface renders a chart, a calendar, or a metric tile.** If an answer wants a
chart, the answer says which screen draws it and the strip links there. The one exception is
the plan proposal card (§4.6), which is a *form preview*, not data — it shows what would be
written, not what was measured.

---

## 7. The persistent glass button — FR-4.1 / FR-4.2

### 7.1 It is chrome, so FR-4.2 is not in tension

`App/DesignSystem/Surfaces.swift` restricts Liquid Glass to chrome and keeps content flat and
opaque, and `ChromeRole` has a `.floatingControl` case naming exactly this. Today
`glassChrome(_:)` has **zero call sites outside the gallery** (design review §3.2). This is
its first honest one.

The environment tripwire in `Surfaces.swift` will not fire, because the button is attached at
the root, outside every `contentSurface(.card)` subtree. That is not luck — it is where it has
to live anyway (§7.2).

### 7.2 Where it lives

Attached at `RootTabView`, outside the tabs, so both tabs get it and pushing a workout detail
does not stack a second one.

**Preferred mechanism: iOS 26's `TabView` bottom accessory.** iOS 26 provides a bottom
accessory slot that sits above the tab bar and adapts as the tab bar minimises — the slot
Apple Music's now-playing bar occupies, and a persistent chat entry point is the same shape of
control. **I cannot verify this against the SDK from this container.** If it does not exist or
does not behave as described, the fallback is `.overlay(alignment: .bottomTrailing)` on the
`TabView` with `.safeAreaPadding(.bottom)`. The implementing ticket tries the former, falls
back, and says in its PR which one it used and that a human must look at it.

### 7.3 On scroll

**It does not hide.** The owner asked for "constantly persistent", and an entry point that
vanishes when you scroll is one you cannot find when you want it — the exact defect design
review §4.4 records about the current one.

This interacts with `.tabBarMinimizeBehavior(.onScrollDown)`, which FR-4.1 asks for and
nothing currently sets (design review §3.3). Anchored to the tab bar's top edge, minimising
the bar moves the button; that is correct with the accessory API (designed to travel with the
bar) and needs a hand-written accommodation with the overlay fallback. Either way: **the
button never disappears; it may move.**

### 7.4 Keyboard

`.ignoresSafeArea(.keyboard, edges: .bottom)` on the button, so it never rides up a raised
keyboard.

The case barely arises today — the only keyboard in the app is the chat composer's, and the
chat sheet covers the tab bar. It is stated as a rule anyway, because the next inline text
field somebody adds will otherwise discover it the hard way.

### 7.5 On a workout detail screen

The button stays and **changes subject**, per §2.1. The mechanism is a small `@Observable`
model owned by `RootTabView` and placed in the environment; `WorkoutDetailView` sets the
subject on appear and clears it on disappear. A thin, decision-free adapter — the *decision*
(which thread a subject resolves to) lives in the core, per CLAUDE.md.

A SwiftUI `PreferenceKey` is the more idiomatic spelling and is harder to reason about through
a `TabView` containing `NavigationStack`s. The implementing ticket may use either and should
say which.

### 7.6 What I cannot judge

How a glass capsule reads over this app's near-black surfaces; whether it collides visually
with the tab bar's own glass; whether the label at Dynamic Type AX3+ still fits a capsule.
All three are device questions and the ticket carries a **Needs device verification** heading
listing them.

---

## 8. What this costs to run

I cannot price this. There is no telemetry in the app, no usage history I can read, and I
will not invent per-token numbers. What I can do is state the *scaling* and fix the terms that
grow.

### 8.1 Today

One scoring call per ingested workout — unattended, small, non-streaming
(`AnthropicScoringModelClient`). Plus chat on demand, streaming, with `task` and `factSheet`
sent as two cacheable system blocks in stability order so a five-message conversation
re-sends the run's facts four times at cache-read price rather than full price.

> **Closed while this document was being written (MAX-091).** Both clients now run on the
> Sonnet tier at `medium` effort, on the owner's cost instruction. Two of that change's
> consequences bear directly on the numbers below and are load-bearing for §8.2's cache
> argument: the **cacheable prefix minimum is 1024 tokens** on this tier, and the tokenizer
> produces **~30% more tokens** for the same text. See §8.2.

### 8.2 After

A chat-first app invites many more calls, and a training turn carries a larger fact sheet than
a workout turn. Four decisions bound it.

**History is re-sent every turn, because the Messages API is stateless and there is no
alternative.** What matters is which parts are cached. The existing two-breakpoint structure
carries over unchanged: `task` (identical for every turn of that thread kind), then
`factSheet` (identical for the whole life of one thread, since the scope is frozen — §3.4).
The training fact sheet being *larger* makes the cache more valuable, not less. Per-turn cost
is therefore ≈ cached-prefix read + transcript + output, and **the transcript is the only term
that grows.**

> **And the training fact sheet is the first thing in this app that will actually cache.**
> Today's system blocks are far under the 1024-token minimum, so both `cache_control` markers
> are inert — no error, no saving, `cache_creation_input_tokens: 0`. A roll-up over a month of
> runs is the first prefix with a real chance of crossing it. That makes the two-breakpoint
> ordering worth preserving exactly as MAX-024 built it, and it makes §3.3's per-run line a
> *cost* decision as well as a privacy one. It also means **the cache is not a mitigation to
> lean on until it is measured**: a fact sheet that lands at 900 tokens saves nothing, and the
> only honest way to know which side of the line it falls on is `count_tokens` against the
> real model, which no test in this repo can run.

**So the transcript is capped.** Only the most recent N turns are replayed; the proposal is
**40 turns (20 exchanges)**, and when turns are dropped the instruction says so, so the model
does not confidently answer as if it had seen the beginning. Decided in the core, under test.

Rejected alternative: summarising the dropped turns with a second model call. That is a second
assembler of context (forbidden — D3) *and* it doubles the calls, which is the opposite of the
goal.

**The context is roll-up, not fact sheets** (§3.3), doubly bounded by the scope and by
`maximumRenderedRuns`. The largest single cost lever, chosen for privacy reasons first; the
cost saving is a bonus pointing the same way.

**Plan drafting is one extra non-streaming call per tap of "Draft a plan"**, on a prompt of
the same order as one chat turn. It is bounded by being a button rather than a background
behaviour.

### 8.3 The tier — decided, by the owner, mid-ticket

This section originally asked whether a chat-first app should still run every call on the
Opus tier. The owner answered it directly: **Sonnet at `medium` effort, to keep the budget
low.** MAX-091 applied it to both clients together, so the tier is one choice rather than two.

What that leaves for the tickets below:

- **Plan drafting (MAX-099) inherits the same tier by default, and should.** A plan proposal
  is a larger, more structured output than a chat turn, so it is the one call where a tier
  step-up would be arguable — but it is also a call the athlete reviews field by field before
  anything is stored (§4), which is the strongest possible check on a weaker answer. Ship it
  at the same tier and let a real proposal argue otherwise.
- **`effort` is the lever if answers come back shallow, not the tier.** It is a per-request
  value, so a single route can be raised without moving the app's cost floor.
- **One trap for whoever writes MAX-099's client.** Both existing clients disable thinking,
  and disabling is accepted only at `high` effort or below. A new client that copies the
  `Thinking` block and also raises effort to `xhigh` gets a 400, not a slower answer.

### 8.4 Invariant: no unattended chat call. Ever.

Every chat call is initiated by the athlete typing or tapping. The only unattended model call
in this app is and remains the scorer's, one per ingested workout.

Written as an invariant rather than a scoping note because the obvious next request — a
proactive coach, a weekly summary that writes itself, a notification with an insight — would
change the cost profile by an order of magnitude *and* would send health data to a model with
nobody present. Adding one is a decision made deliberately, with A14 in front of it.

---

## 9. The invariants this pivot does not touch

**D1 — the plan is versioned data.** Untouched. §4 routes model output through
`PlanAuthoringSession`, the same door the authoring screen uses; a proposal is not a plan and
cannot become one without a human tap. The near-miss to watch for in review: a future ticket
adding `PlanDraft.applying(_ proposal:)` that also *stores*. It must not.

**D2 — metrics computed once at ingestion and stored.** Untouched, and now with a live threat
that §3.6(a) exists to close. Every figure the training context quotes must be the stored one,
or produced by the same core function the corresponding screen reads. The tempting shortcut —
a helper that averages some drifts to save a call into the tallies — is D2's drift arriving in
a prompt, where nothing on screen contradicts it. Under the owner's clarification this is no
longer an internal tidiness argument: the screens are authoritative and chat describes the
same numbers to the same person, so a divergence is a visible product defect.

**D8 — auto-scores are immutable.** Untouched, with two consequences worth stating:

- Chat writes nothing (§2.5). It cannot record an annotation, however reasonable the athlete's
  disagreement.
- The training task text must tell the model the scores it sees are assigned and not up for
  revision. A model invited to re-score in prose produces a second opinion recorded nowhere,
  which is the *opposite* of the auto-versus-manual divergence signal PRD §2 wants — the whole
  point is that a correction is a record.

**Nothing in this pivot requires moving any of the three.** If an implementing ticket finds
that it does, that is an escalation to the overseer, not a change to make.

---

## 10. Amendments

Drafted into [docs/PRD-AMENDMENTS.md](./PRD-AMENDMENTS.md) in this PR:

| # | Supersedes / adds | In one line |
|---|---|---|
| **A9** | §7.2's framing, FR-1.6, FR-2.1 | Chat becomes a second primary interaction with three named jobs — additive, not a replacement |
| **A10** | FR-3.5, §3 non-goal, §12 | Claude reaches the dashboard tab. The "no Claude on this tab" non-goal is spent deliberately, not forgotten |
| **A11** | D6 | Thread identity is independent; the workout link is one of two subjects; no migration |
| **A12** | D3 (generalised) | One context module, one entry point, a closed subject set, a shared renderer — and the agreement property |
| **A13** | — (clarifies D1) | Model-drafted plans are proposals; D1 is untouched; here is the only door |
| **A14** | §11's cost note | Cost discipline for a chat-first app, including "no unattended chat call" |
| **A15** | — (adds) | The plan gets a read-only screen with version history |

A10 deserves a note here because it is easy to land by accident. PRD §3 lists *"Claude on the
dashboard tab (`summarize my month`)"* as a **non-goal**, §12 defers it to v2, and
`PROJECT_TRACKER.md`'s "Deliberately not built" repeats it — a list that exists, in its own
words, "so nobody helpfully adds one". A persistent Ask button on the Dashboard tab opening a
training thread *is* that feature. It should be superseded on the record rather than arriving
as a side effect of a button placement.

---

## 11. Proposed ticket breakdown

Ordered. Each is one agent's work. Files are named so the overseer can see collisions; ⚠️
marks a file two tickets both touch.

| # | Ticket | Scope, one line | Files | Depends on | Tier |
|---|---|---|---|---|---|
| **MAX-092** | `ChatSubject` and thread identity | `ChatThread` keyed on its own id, gains `subject`; repository grows list / fetch-by-id / delete; `ChatThreadSummary` | `Domain/ChatThread.swift`, `Persistence/Repositories.swift`, `Persistence/StoredPlanRecords.swift`, `MaximizeCoreTestSupport/ChatThreadRepositoryFakes.swift`, tests | — | **Opus** |
| **MAX-093** | The stored record | Additive fields (`subjectKind`, scope days, `lastActivityAt`); store conformance; **assert no migration is needed** | ⚠️ `App/Persistence/MaximizeSchema.swift`, ⚠️ `App/Persistence/MaximizeStore.swift` | 091 | Sonnet |
| **MAX-094** | Shared fact-sheet formatting | Extract `WorkoutFactSheet`'s private formatters into an internal `FactSheetFormatting`; test both paths agree. **Pure refactor, no behaviour change** | ⚠️ `Context/WorkoutFactSheet.swift`, new `Context/FactSheetFormatting.swift` | — | Sonnet |
| **MAX-095** | `TrainingContext` + one entry point | The roll-up type, its renderer, `ContextBuilder` / `PromptContext`, the bounds — **and §3.6(a)'s agreement test as an acceptance criterion** | new `Context/TrainingContext.swift`, `Context/TrainingFactSheet.swift`, `Context/ContextBuilder.swift`; ⚠️ `Context/WorkoutFactSheet.swift` | 091, 093 | **Opus** 🔒 |
| **MAX-096** | `ChatModel` generalised | `WorkoutChatModel` becomes subject-driven; transcript cap; training `task` text | `Chat/WorkoutChatModel.swift` → `Chat/ChatModel.swift`, `Chat/ChatInstruction.swift`, ⚠️ `App/Workouts/WorkoutChatView.swift` (call site) | 094 | **Opus** 🔒 |
| **MAX-097** | Thread list and new chat | List screen, derived titles (core), delete, the sheet's navigation, the scope subtitle | new `App/Chat/ChatSheet.swift`, `App/Chat/ChatThreadListView.swift`; core: title derivation beside `ChatThreadSummary` | 092, 095 | Sonnet |
| **MAX-098** | The persistent glass button | Root-level accessory, subject model; `WorkoutChatSectionView` loses its button and becomes a preview | ⚠️ `App/RootTabView.swift`, new `App/Chat/ChatEntryButton.swift`, `App/Chat/ChatPresentationModel.swift`, `App/Workouts/WorkoutDetailView.swift`, `App/Workouts/WorkoutChatSectionView.swift` | 096 | Sonnet — **needs device** |
| **MAX-099** | `PlanProposal` | The proposal type, `parse`, `schemaDescription` derived from core enums, `PlanProposalInstruction`, `PlanProposalModelInvoking`; tests pinning every enum case appears | new `Plan/PlanProposal.swift`, `Plan/PlanProposalInstruction.swift`, `Plan/PlanProposalModelInvoking.swift` | 094 | **Opus** 🔒 |
| **MAX-100** | The Anthropic client for proposals | Non-streaming call, three cacheable blocks, mirroring `AnthropicScoringModelClient` | new `App/AnthropicPlanProposalClient.swift` | 098 | Sonnet 🔒 |
| **MAX-101** | Conversational plan authoring | `PlanDraft.applying(_:)` in core (**no store call**), the proposal card with its revision diff, the one-retry policy, the handoff into a prefilled `PlanAuthoringView` | core: `Plan/PlanDraft.swift`, `Plan/PlanAuthoring.swift`; app: ⚠️ `App/Plan/PlanAuthoringModel.swift`, ⚠️ `App/Plan/PlanAuthoringView.swift`, `App/Chat/` | 097, 099 | **Opus** |
| **MAX-102** | **The plan screen** | Read-only plan view with version history, pushed from the Dashboard. **Independent of every other ticket here** — dispatchable now | new `App/Plan/PlanView.swift`, `App/Plan/PlanViewModel.swift`; core: a `PlanDisplayData` prepared value; ⚠️ `App/DashboardView.swift` | — | Sonnet |
| **MAX-103** | "Runs in this conversation" strip | The chip strip from `TrainingContext`, pushing through to detail | `App/Chat/`, `App/Workouts/WorkoutDetailView.swift` | 097 | Sonnet |
| **MAX-104** | Copy and absence voice over the new surfaces | One register, one font, one surface for every new absence string; the "no plan authored yet" state points at the plan editor | `App/Chat/*`, `App/Plan/*` | 097, 101 | Sonnet |

🔒 = `/security-review` before merge, per CLAUDE.md. **091–095 and 098 are core-only and
CI-verifiable end to end. 096, 097, 099–103 are App-layer, which CI compiles and never
executes** (tracker R13) — every one of those PRs needs a *Needs device verification* list.

### Collisions, called out

- **MAX-094 and MAX-095** both touch `Context/WorkoutFactSheet.swift`. 093 is a pure
  extraction and must land first; 094 then adds only its own renderer. In parallel they
  conflict in the one file the whole D3 argument rests on.
- **MAX-096 renames the file `App/Workouts/WorkoutChatView.swift` imports from.** Dispatch it
  with the call-site update in the same PR.
- **MAX-098 touches `App/RootTabView.swift`**, which design review **T2** also touches
  (`.tint(.accent)`, the iOS 26 `Tab` builder, `.tabBarMinimizeBehavior`). **Land T2 first.**
  T2 is nearly free and changes the app's character more than anything in the review; the
  button should be built against the migrated tab bar, not merged into it afterwards.
- **MAX-101 and MAX-102 both touch `App/Plan/`.** Different files, but MAX-102 will want to
  link into the authoring screen — sequence 101 first, it is the smaller and independent one.
- **MAX-102 touches `App/DashboardView.swift`**, which design review §4.2 and T2 also touch.
- MAX-080 landed hours ago; every agent branch here rebases onto `main` before its PR opens,
  per the tracker's process note about MAX-012.

### Suggested order

**MAX-102 immediately and in parallel with everything** — it is independent, it closes the
other half of design review §1.1, and it is the fastest visible answer to "highly detailed".

Then **T2 (design review) → 091 → 092 → 093 → 094 → 095 → 096 → 097**, which is the shortest
path to the persistent button, thread history and the general-questions job. **098 → 099 →
100** (conversational plan authoring) runs in parallel with 096/097 once 094 lands. 102 and
103 are polish and parallelise freely at the end.

If the schedule is tight, there is a real intermediate milestone: **091 → 092 → 095 → 096 →
097 with a workout-only subject set** delivers the persistent button, the thread list and
new-chat against the existing per-workout context, deferring all of §3. Combined with
MAX-102, that is two of the owner's three jobs (read a plan, ask about a run) with none of
§3's privacy surface opened yet.

---

## 12. What I am deliberately not deciding

| # | Question | Who should decide | My lean |
|---|---|---|---|
| 1 | **Tool use / model-initiated retrieval.** The long-term answer to "escalate from a training thread into one run's detail", and to Phase B of §4.7 | Owner + whoever owns MAX-024's transport | Defer. A new transport surface and a new security-review surface; the roll-up plus the runs strip covers most of what it buys |
| 2 | **May the model author rubric bands?** | Owner | No, in v1 (§4.4). Needs a closed condition grammar and a ticket of its own |
| 3 | **Multiple threads per workout** | Owner | One (§3.4 / A11). Reversible in a single repository method |
| 4 | **Should the scope be editable per thread**, rather than inherited and frozen? | Owner | Inherit and freeze (§3.4), with §3.6(b) making the mismatch legible. A picker in the sheet is defensible and I hold this lightly |
| 5 | ~~**Model and `max_tokens` for training threads.**~~ **Closed by the owner (MAX-091): Sonnet tier, `medium` effort, both clients.** What remains open is `max_tokens` for a *training* turn specifically | Whoever builds MAX-096, once a real roll-up exists | A training answer is not obviously longer than a workout answer — start at chat's current ceiling and raise it only if turns come back truncated |
| 6 | **Whether iOS 26's `TabView` bottom accessory exists and behaves as §7.2 describes** | Whoever builds MAX-098, on a device | Try it, fall back to an overlay, say which in the PR |
| 7 | **Model-emitted inline references** (a run named in prose being tappable) | Later ticket | Deferred (§6.2). The deterministic runs strip gets most of the value with none of the parsing |
| 8 | **Whether the plan screen is wanted at all** (§5.3 — the one thing here nobody asked for) | Owner | Build it. But MAX-102 is deliberately independent, so dropping it costs nothing else |
| 9 | **The assistant's voice** beyond §3.5's constraints | Owner | The existing workout `task` text is a good model — short, conversational, refuses to invent |
| 10 | **How far "highly detailed" goes** on the dashboard and detail screens | Owner, against design review's board | §1.2 names the two findings whose status changes. The rest of that work is MAX-082's board, not this ticket's |

And one thing explicitly *not* left open: **nothing in this pivot requires moving D1, D2 or
D8.** If an implementing ticket concludes otherwise, that is an escalation.

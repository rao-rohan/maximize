# Chat — an audit of the surface and its context continuity

**Ticket:** MAX-184
**Date:** 2026-08-21
**Status:** Audit, for the owner's decision. **No source is changed by this document.**
**Reads against:** [docs/CHAT-FIRST-SPEC.md](./CHAT-FIRST-SPEC.md) (MAX-090), CLAUDE.md's
"The UI standard" and "Architecture: thin shell, fat core", and A11–A15.

---

## 0. What this is, what it is worth, and the one thing to read first

### 0.1 Nothing here is dangerous

**No data loss, no privacy leak off the device, and no crash was found.** I looked for all
three specifically. The nearest thing to a privacy finding is §2.4 — the thread list decodes
every stored transcript into memory to render a screen that shows none of them, which is the
exact thing `ChatThreadSummary`'s own doc comment says it exists to prevent. That is an
in-memory exposure against the codebase's own stated rule, not health data leaving the
device. It should be fixed; it is not an emergency.

The rest is a mix of seven defects — states that are unreachable, inert, or that put a stale
statement on screen — one real product gap on the owner's central ask, and a list of places
where this is a very good chat surface that is not yet a top-shelf one.

### 0.2 Evidence, and its limits

Every claim about *what the code does* is read from source and cited `file:line`. I read
every file in `App/Chat/`, `Sources/MaximizeCore/Chat/`, `Sources/MaximizeCore/Context/`,
plus `App/Workouts/WorkoutChatSectionView.swift`, `App/RootTabView.swift`,
`App/Plan/PlanAuthoringView.swift`, `App/Plan/PlanAuthoringModel.swift` and
`App/Persistence/MaximizeStore.swift`'s chat-thread half.

**There is no Swift toolchain in this container** (`which swift` finds nothing), so I did not
build, did not run a test, and did not see a pixel. Every claim about *what a person would
experience* is inference from view structure and SwiftUI semantics, and where the inference
could be wrong I have said so and moved the item into §7 as a hypothesis rather than a
finding. §7 exists so that the ranked list in §8 contains nothing I could not verify.

Three claims I was handed as hypotheses, and their status after independent reading:

| Handed to me | Verdict |
|---|---|
| `ChatModel.canDraftPlan` requires `.training`, so the plan cannot be acted on from a workout thread | **Confirmed** (`ChatModel.swift:327-332`). **And it is correct design** — see §3.5. The defect is the missing route, not the gate |
| A workout thread knows the day's prescription and nothing about the surrounding week | **Confirmed** (`WorkoutFactSheet.swift:65,89,118,145,161,167`) |
| A training thread has a roll-up per session but "no splits, no drift, no HR shape" | **Confirmed except for drift.** Drift *is* on every session line (`TrainingFactSheet.swift:290-292`). What is genuinely absent is splits, the HR curve, cadence, time-above-cap, the rationale — **and strain and load balance, which is the finding that matters** (§3.2) |

---

## 1. What is already good, and should not be touched

A ticket list that implies everything is broken is not useful for prioritising. Several of
these surfaces had real design work and the work holds up.

**1.1 The reply ladder (MAX-152, MAX-170) is the best thing in this feature.**
`ChatReplyPhase` (`ChatReplyPhase.swift:32-108`) is a closed enum with eight rungs, and
`ChatReplyProgress` (`:214-355`) is the only thing that moves between them — a pure fold over
stream events with no clock, no `Task.sleep` and no injected date. The stall rule
(`:303-318`) calibrates against what the stream itself has demonstrated while healthy rather
than against a guessed ping cadence, and the file states in its own documentation both what
it is still guessing (`heartbeatsBeforeStall = 8`, `:234`) and what happens when that guess
is wrong. That is the standard the rest of this feature should be measured against.

**1.2 Failure copy (MAX-152).** `ChatFailureNotice` (`ChatFailureNotice.swift:74-193`) is
exhaustive over `ChatStreamError` with no `default`, never prints a status code, never
interpolates health data, and words "no key stored" and "the stored key was rejected" apart
because they need different actions (`:98-103`). Retry is gated on
`ChatStreamError.isWorthRetrying` (`ChatStreamError.swift:113-120`), so no button is offered
that re-runs a call guaranteed to fail identically. Do not touch any of this.

**1.3 Scroll and keyboard (MAX-081, MAX-153).** The composer is a bottom `safeAreaInset` on
the conversation's own container (`ChatConversationView.swift:335`), which is the correct and
non-obvious fix; `ChatConversationView`'s own doc comment (`:48-67`) explains why the previous
arrangement could not be made to behave. `ChatTranscriptFollow` decides whether arriving
content may move the viewport, and the answer is usually no (`:437-462`). The deliberate
departure — focusing the composer no longer drags a scrolled-up reader to the bottom
(`:459-462`) — is right. `.presentationContentInteraction(.scrolls)` (`ChatSheet.swift:139`)
stops an overshoot flick from throwing the conversation away.

**1.4 The waiting state (MAX-152).** A shimmer drawn *on words* rather than instead of them
(`ChatPendingReplyView.swift:144-214`), withheld entirely under Reduce Motion *and* Reduce
Transparency (`:154`), with the sweep sized in fractions of the label's own width so Dynamic
Type cannot break it (`:187-208`). The copy is the channel; the animation is decoration on
top of it. This is CLAUDE.md's hue-alone rule generalised correctly.

**1.5 The composer's geometry (MAX-153).** `HStack(alignment: .bottom)`
(`ChatComposerView.swift:143`) so the send control does not walk up half a line per line
typed. `@ScaledMetric` on both the hit target and the glyph (`:92,96`), and a lower line
ceiling at accessibility sizes (`:230-234`). Two glass shapes inside one
`GlassEffectContainer` (`:122`) rather than one hand-rolled blurred bar, with no
`CornerRadius` constant anywhere in the file because `.floatingControl` brings the platform's
capsule. This is what "let the platform supply its chrome" looks like at a call site.

**1.6 The entry point (MAX-098).** `tabViewBottomAccessory` (`RootTabView.swift:145`) with no
glass re-applied, because the system draws that container itself
(`ChatEntryButton.swift:12-24`) — and `ChatEntryButton`'s doc comment records that §7.1's
prediction was wrong and says why. `ChatEntryPointFocus.release(_:)` matching an identifier
(`ChatEntryPoint.swift:54-57`) is a real ordering bug caught before a device found it.

**1.7 The thread list's platform manners (MAX-150, MAX-153).** `ContentUnavailableView` for
both absences (`ChatThreadListView.swift:69-83`), `.onDelete` rather than a hand-rolled
`.swipeActions` so VoiceOver and Switch Control get the same affordance (`:104-115`), and
`ViewThatFits` dropping the timestamp rather than truncating the title (`:198-211`).

**1.8 The agreement property has a mechanism, not an intention.** Every aggregate in
`TrainingContext` comes from `TalliesCalculator` (`ContextBuilder.swift:275-286`), the average
score renders through the tile's own formatter (`TrainingFactSheet.swift:216`), and the
exclusion caption comes from the one function the dashboard caption reads (`:221`).
`TrainingContextAgreementTests` and `FactSheetFormattingAgreementTests` exist. §3.6 is real.

---

## 2. Defects — states that are unreachable, inert, or that put something untrue on screen

Ranked worst first. Each is a thing a person would hit, not a preference.

### 2.1 **"New chat" does nothing when the dashboard is on the thread's own window**

`ChatSheet.startNewTrainingChat()` (`ChatSheet.swift:196-200`) resolves the dashboard's
current interval into a `TrainingScope` and assigns `opening = .subject(.training(scope))`.
Two things then happen, and both are no-ops in the common case:

1. `ChatConversationView` is keyed on `.id(opening)` (`:105`). When the sheet was opened by
   the Ask button, `opening` is *already* `.subject(.training(currentScope))` — the Ask
   button builds it from the same interval (`ChatEntryPoint.swift:147-156`). Assigning an
   equal value does not change the identity, so the view is not recreated.
2. Even if it were, `ChatThreadRepository.thread(for:newThreadID:at:)`
   (`Repositories.swift:288-294`) returns `mostRecentThread(for:)` when one exists. A scope
   that has not changed resolves to the thread already open.

So on the ordinary path — tap Ask on the dashboard, tap **New chat** — the button is inert.
No new thread, no visual response, no explanation. The toolbar item is only visible for
training subjects (`ChatConversationView.swift:262-266`), so this is the majority of the
times it is seen.

The file's own comment (`ChatSheet.swift:191-195`) argues this is "correct rather than a
duplicate". That is a defensible argument about *storage* and the wrong answer for a
*control*: a button that resolves to "you are already here" must say so, be disabled, or
mint a genuinely new thread. Right now it teaches a tap that silently fails, which is the
exact defect `ChatEntryButton`'s own doc comment (`ChatEntryButton.swift:26-30`) says the accessory's full-width
hit area exists to avoid.

Note the second-order consequence: **there is currently no way to start a second conversation
about the same window.** The repository deliberately does not deduplicate training subjects
(`MaximizeStore.swift:469-470`), so the capability exists in storage and has no door in the UI.

### 2.2 **The chat card on the workout screen is inert, and goes stale the moment it matters**

`WorkoutChatSectionView` (`WorkoutChatSectionView.swift:29-91`) renders either the invitation
copy or a preview of the last exchange with a relative timestamp (`:71-88`). It is **not a
button and has no tap target of any kind** — MAX-098 removed the "Open chat" button and did
not replace it with anything. A card that shows your last message and its timestamp reads as
tappable to every person who has used a phone. Tapping it does nothing; the way in is the
floating bar at the bottom of the screen.

Worse, the read runs in `.task { await model.load() }` (`:52`), which fires on appear and
does not re-fire when a sheet presented over the screen is dismissed. So the sequence
*open a run → Ask about this run → have a conversation → Done* returns the athlete to a
detail screen whose Chat card still shows the invitation. That is precisely the defect
MAX-098 says this card exists to fix — its own doc comment (`:15-18`) names it: "the screen
never showed that the run had already been discussed." The fix landed and is defeated by the
missing invalidation.

### 2.3 **The plan proposal card outlives the save it caused, and keeps offering it**

`ChatModel.planDrafting` is cleared only by `discardProposal()` (`ChatModel.swift:1112-1120`)
or by `load()` (`:527`). Accepting a proposal pushes `PlanAuthoringView`
(`ChatSheet.swift:118-123, 177-179`) onto the same navigation stack; `PlanAuthoringModel.save()`
stores the plan, clears its *own* prefill and shows a confirmation **without dismissing**
(`PlanAuthoringModel.swift:430-455`). Back returns to a transcript where:

- the card is still `.proposed(review)`, rendering a diff computed against the version that
  the save has now superseded — so a row reading *"Heart-rate cap · 148 · ~~152~~ · Changed"*
  is describing a change that has already happened. A statement on screen that is no longer
  true.
- **Accept this plan** is still live. Tapping it pushes a second authoring screen, which
  builds a fresh session against the now-current calendar, and a second Save writes another
  plan version identical to the first. D1 is not violated — nothing is overwritten — but the
  athlete gets a duplicate version in their history from a button that looked like the one
  they already used.

`ChatConversationView`'s `.task` (`ChatConversationView.swift:242-244`) does not re-run on pop, so nothing reloads.

### 2.4 **The thread list decodes every stored transcript to render a list that shows none of them**

`ChatThreadSummary`'s doc comment (`ChatThreadSummary.swift:134-137`) states the rule: a
summary carries no transcript, because "a list of twenty threads holding twenty full
conversations is twenty JSON blobs decoded to render twenty single lines, and — the reason
that matters more — health data in memory for a screen that shows none of it."

`MaximizeStore.threadSummaries()` (`MaximizeStore.swift:413-421`) fetches every
`ChatThreadRecord` with no predicate and no limit and calls `record.stored.toDomain()` on each
one, which decodes `messagesJSON` — an `@Attribute(.externalStorage)` blob holding the whole
conversation (`MaximizeSchema.swift:532`). It then calls `workoutFacts(for:)` per thread
(`:417`), which is a second fetch per workout thread (`:503-509`). So the screen is O(threads)
full transcript decodes plus an N+1 workout query, on the main actor, on every push of the
history button.

This is the shape CLAUDE.md predicts: the contract is in the core where CI reads it, the
implementation is in `App/` where CI compiles and never executes it (tracker R13).

### 2.5 **A failed thread delete is silent, and the row does not come back**

`ChatThreadListModel.delete(threadID:)` (`ChatThreadListModel.swift:83-92`) removes the row
from `summaries`, re-presents, then writes with `try?` (`:91`) and discards the result. The
comment (`:86-90`) cites `ChatModel`'s failed-store reasoning as precedent — but `ChatModel`
does the opposite of this: it says so plainly, with `ChatFailureNotice.couldNotSaveReply`
(`ChatModel.swift:960`), whose copy exists precisely because "the transcript and the store now
disagree" (`ChatFailureNotice.swift:174-182`).

Here the athlete sees a conversation deleted, closes the sheet, opens it again, and the
conversation is back with no explanation. That is the app inventing an outcome, which MAX-175
made a rule.

### 2.6 **`PlanAuthoringView` and `ChatSheet` present each other without bound**

`PlanAuthoringView` presents a `ChatSheet` for the conversational route
(`PlanAuthoringView.swift:91-93`, MAX-166). `ChatSheet` pushes a `PlanAuthoringView` when a
proposal is accepted (`ChatSheet.swift:118-123`). The pushed authoring screen renders
`conversationalRouteSection` unconditionally (`PlanAuthoringView.swift:103`), so its button is
there, enabled, and presents another `ChatSheet`.

Sheet over pushed-screen over sheet, arbitrarily deep, each one a modal presentation the
athlete has to dismiss individually. Not a crash; a navigation state a person can get lost in
with three ordinary taps. The two tickets that built these doors (MAX-101, MAX-166) each
knew about one direction.

### 2.7 **The transcript cap is told to the model and not to the athlete**

`ChatInstruction` drops turns beyond `maximumReplayedTurns = 40` and injects a bracketed
notice so the model knows (`ChatInstruction.swift:150-179`). `droppedTurnCount` is public
(`:123`) and **nothing reads it.** So in a long thread, the athlete scrolls up, sees their own
question from earlier, asks a follow-up about it, and gets "I no longer have that stretch of
the conversation" with nothing on screen having warned them. The honest half of the mechanism
is built; the half that faces the person is not.

---

## 3. Continuity between plans and workouts — the owner's central ask

### 3.1 What each thread actually carries, verified

**A workout thread** (`WorkoutFactSheet.swift:60-170`) renders, in order: `## Workout` (date,
type, setting, duration, distance, energy, classification), `## The plan` (version, HR cap,
cadence band, **that day's scheduled session**, goals, target event), `## Measured` (average
and maximum HR, time above cap, drift, cadence, grade-adjusted pace, zone splits, **strain**),
`## Heart-rate shape` (ten buckets), `## Pace by kilometre` (chat only), `## Score already
assigned` (value, band, rationale).

It knows the plan's *settings* and *that one day's ask*. It knows nothing about any other day:
no tallies, no streak, no arc week, no adjacent session, no load balance.

**A training thread** (`TrainingFactSheet.swift:32-51`) renders `## The window`, `## The plan
in effect` (version, cap, cadence, both thresholds, goals, target, arc week and its prescribed
long run, plan-coverage caveats, **the whole weekly template including the lift slot**),
`## The tallies over this window` (workout-days, effective sessions, average score with its
exclusion caveat, streak), and `## Sessions in this window` — one line per session carrying
day, weekday, activity and classification, the day's ask, distance, duration, average HR,
**drift**, and the verdict with any correction (`:276-295`).

It knows the shape of the block and the outline of every session. It does not know splits, the
HR curve, cadence, time above cap, route, or the scorer's rationale — all four exclusions are
stated in the prompt itself (`:267-271`), which is the right way to exclude something.

### 3.2 The gap that matters most is not the one in the brief

The app computes three things that answer "does this fit the block", and **none of them
reaches any prompt on the training side**:

- **Strain** (MAX-176/177) is on the workout fact sheet (`WorkoutFactSheet.swift:141`) and is
  absent from `TrainingContext.Session` entirely — the type has no strain field
  (`ContextBuilder.swift:334-347`), and grepping `Context/` for "strain" returns nothing
  outside `WorkoutFactSheet`.
- **Acute vs. chronic load balance** (MAX-178) is consumed only by `TrendTileData` and
  `TrendTilesModel`. `LoadBalanceCalculator` appears in no context file.
- **Per-muscle fatigue** (MAX-179/180) reaches `MuscleMapView` and no prompt. The *prescribed*
  muscle groups appear via `FactSheetFormatting.liftPrescription` (`:112-136`); what the
  athlete actually worked, and the decayed fatigue reading drawn on the detail screen, do not.

So the app can draw "your seven-day load is 1.6× your recent normal" on a tile and, one tap
away, a training thread asked *"am I ramping too fast?"* will correctly refuse to answer —
`trainingTask` forbids inventing a figure the summary does not state
(`ChatModel.swift:1198-1200`). That refusal is honest and useless, and it is the owner's exact
question. **This is the highest-value fix in this document and the cheapest.**

It is cheap for a specific reason: every one of those three is produced by a core function a
dashboard surface already reads, so §3.6(a) holds by construction rather than by care. Two
extra lines in `## The tallies over this window` and one extra field on each session line is
the whole shape.

### 3.3 The workout side: my position, and the argument for it

**The two-subject split is right and should not be merged.** §3.1 of the spec is correct that
building N workout contexts and concatenating them is the shape that sends everything, and the
roll-up is the right answer to it. Nothing below proposes changing that.

But "how does this run sit in my week?" is a fair question to ask on a run's own screen, and
today it is unanswerable. My recommendation:

> **A workout thread gains a bounded `## The week this sits in` block that carries aggregates
> only, and no sibling session lines.** Concretely: the Monday-first training week containing
> the run, its arc week and prescribed long run, that week's `Tallies` over that week alone,
> the acute:chronic ratio as of that day, and the count of sessions the week holds.

Three properties make this the right shape rather than a compromise:

1. **It is O(1) in the athlete's training volume.** Six or seven lines whether they ran twice
   that week or nine times. A block that grows with volume is `TrainingContext` arriving by a
   side door, and it would double a workout prompt for the athlete who trains most.
2. **It is built from the same functions the dashboard reads** — `TalliesCalculator` over a
   one-week `TalliesInput`, `PlanCalendar.arcWeek`, `LoadBalanceCalculator` — so it cannot
   disagree with a tile. That is §3.6(a) satisfied by construction, exactly as
   `ContextBuilder.trainingContext` already satisfies it (`ContextBuilder.swift:275-286`).
3. **It adds no new *category* of health data.** Everything in it already leaves the device
   in a training thread, in the same shape, from the same functions. What changes is that it
   now leaves for a *workout* subject too.

**Rejected: sibling session lines in a workout thread.** "The other four runs this week, one
line each" is the tempting version and it is wrong. It is `TrainingContext` with extra steps,
it reintroduces the unbounded term, and the question it answers ("what else did I do") is
already answered by the runs strip and by navigation.

**This is an amendment, not a ticket.** A12 rule 2 makes "what health data leaves the device
for a subject" an amendment-level question, and this changes the answer for the workout
subject. It needs a paragraph in `docs/PRD-AMENDMENTS.md` and a `/security-review`, per
CLAUDE.md. The ticket in §8 is written to depend on that paragraph existing.

### 3.4 The reverse direction — depth on one session from a training thread — should stay a navigation problem

I do **not** recommend putting splits or an HR curve for one session into a training thread,
and I think the current design is right. The mechanism already exists and is good:

- `trainingTask` tells the model to say the detail is not in front of it and to point at that
  session's own conversation (`ChatModel.swift:1206-1210`), and the fact sheet states the same
  exclusions in the prompt (`TrainingFactSheet.swift:267-270`).
- The runs strip is built from the thread's own context, never a second read
  (`ChatModel.swift:421-424`), and each chip pushes that session's detail screen
  (`ChatSheet.swift:124-125, 184-186`).
- That detail screen carries `chatEntryPointFocus(workoutID:)` (`WorkoutDetailView.swift:76`),
  so the Ask bar on it reads "Ask about this run" and opens that run's own thread.

The loop closes. What is missing is only that a person has to notice — the model says "ask in
that run's conversation" and the strip sitting under the transcript is the answer, but nothing
connects the two sentences. That is a copy problem worth one small ticket, not a context
problem worth an amendment. **If the owner disagrees and wants one session's depth pulled into
a training thread, I would argue against it**: it makes the training prompt's size depend on a
question the model was asked, which is exactly the thing that cannot be bounded in advance.

### 3.5 `canDraftPlan` is gated correctly. The missing thing is a door, not a gate

`ChatModel.canDraftPlan` requires `subject?.kind == .training` (`ChatModel.swift:328`),
confirmed. **Leave the gate alone.** §4.2's reasoning holds: a plan drafted from one run's
context is a plan drafted from almost nothing, and the workout fact sheet does not carry a
weekly template, an arc, or thresholds — a `PlanProposal` built from it would be inventing
most of its fields, which is exactly what MAX-175 forbids.

The real defect is what happens to the athlete who says *"my Thursday easy run is always over
cap, change the plan"* on a run's screen. The model has the plan's cap and that day's ask, so
it can answer sensibly, and then there is no route from that answer to the thing they want.
They must: dismiss the sheet, navigate to a tab root so the Ask bar re-reads "Ask", open a
training thread, and re-state the request from nothing.

Fix by navigation. When a workout thread's model has said something about the plan — or simply,
unconditionally on a workout thread — offer one affordance that opens a training thread on the
current window. This is `ChatSheet` reassigning `opening`, which it already does for **New
chat** (`ChatSheet.swift:196-200`); the mechanism exists.

### 3.6 What all of this costs

**I cannot price it, and I will not invent per-token numbers** — §8's own position, and
nothing in this repo can run `count_tokens`. What I can state is the scaling, which is the
part that actually governs:

- §3.2's addition is **two lines in the tallies block and one field per session line**. Both
  sit inside `factSheet`, which is a cacheable system block stable for the whole life of a
  thread because the scope is frozen (`ChatInstruction.swift:42-45`). It is paid once per
  thread, not once per turn. Against a roll-up already carrying up to
  `maximumRenderedSessions = 200` lines (`TrainingContext.swift:229`), this is noise.
- §3.3's block is **fixed-size, six or seven lines**, against a workout sheet that already runs
  to a ten-bucket HR curve plus a per-kilometre split table. Also inside the cached prefix.
- Neither adds a model call. A14 holds: `send()`, `retry()` and `draftPlan()` remain the only
  three paths to a model and all three are reached from a tap (`ChatModel.swift:144-152`).

**The privacy cost, stated plainly, because §3.3 has one.** Today a workout thread sends one
run. After §3.3 it sends one run plus seven aggregate figures about the week around it. The
aggregates are derived scalars over data the app already holds, they name no other session,
and they are the same figures a training thread already sends. It is still a widening, and no
amount of "it's the same numbers" makes it not one. That is why §3.3 is an amendment.

---

## 4. Threads as a system

**4.1 There is a coherent mental model, and it mostly holds.** One entry point, subject-aware
(`ChatEntryPoint.swift:133-157`); the subject decides which pile of data travels; a thread is
resolved from its subject, newest activity first; the thread list is a pushed screen inside the
sheet rather than a tab, on `RootTabView`'s own reasoning. This is a system, not a pile of
entry points. Two things spoil it.

**4.2 There are three doors, and one of them is not on the map.** The Ask accessory
(`RootTabView.swift:145-151`) is the designed one. The thread list inside the sheet is the
second and is correct. The third is `PlanAuthoringView`'s conversational route
(`PlanAuthoringView.swift:91-93`), which presents a whole second `ChatSheet` from a screen that
can itself have been pushed *out of* a chat sheet — §2.6. §2.1 of the spec says "one entry
point, everywhere, in the same place", and MAX-166 added a second without that sentence being
revisited.

**4.3 Threads accumulate weekly and there is no way to search them.** A training thread's scope
is frozen at creation (`ChatSubject.swift:40-48`) and `TrendInterval` offers only week, month
and year (`TrendInterval.swift:58-60`), all calendar-aligned. So an athlete who leaves the
dashboard on "this week" and asks a question most weeks accumulates roughly one thread per
week, each titled by its own first question (`ChatThreadSummary.swift:75-80`). After a year
that is ~50 rows, all but the newest thirty days in a single flat "Earlier" band
(`ChatThreadListPresentation.swift:16,46-47`), with no `.searchable` anywhere in `App/` and no
pagination — §2.4's unbounded fetch is the same finding from the storage side.

The titles are good — derived from the first question, falling back to the window label
(`ChatThreadSummary.swift:61-80`) — and the recency bands are the right structure. What is
missing is the one control that makes a long list usable.

**4.4 `TrainingScope` freezing and `ChatScopeNotice` are right.** The scope is resolved to
absolute days once and never slides; the context is rebuilt from storage on every load, so runs
ingested inside the window after the thread started do appear
(`ChatModel.swift:725-768`). `ChatScopeNotice` (`ChatScopeNotice.swift:32-38`) compares the
frozen scope against the dashboard's live interval and renders a one-line note that is itself
the action (`ChatConversationView.swift:333-334, 342-359`). This makes a deliberate mismatch legible
rather than pretending it cannot happen, which is the achievable goal. Do not change it.

One consequence worth naming: because the banner's action is `onStartNewChatForCurrentWindow`,
the banner *works* (the scopes differ, so `opening` genuinely changes) while the toolbar button
of the same name is inert (§2.1). Two controls, one handler, opposite outcomes.

**4.5 The runs strip is the right affordance and is correctly bounded.** Built from the
thread's own context so it cannot show a session the prompt did not
(`RunsStripData.swift:111-125`), carrying a label and an id and nothing measured
(`RunsStripData.swift:46-58`), capped at 62 chips with the remainder folded into a non-interactive count
(`RunsStripView.swift:68-78`). The header says "Sessions", not "Runs", because a chip can name
a lift. All correct.

---

## 5. Failure and honesty

Assessed against MAX-175's rule (the app does not invent) and CLAUDE.md's (absence is a
designed state).

**5.1 Mostly excellent.** Every path I traced states what happened and what to do:
no key stored, worded from the subject (`ChatFailureNotice.swift:148-157`); a key that cannot
be read, deliberately *not* "add a key" (`:86-91`); a rejected key worded around *replacing*
(`:98-103`); a refusal that says rewording beats retrying (`:118-120`); a partial reply that is
kept on screen with a caption saying so (`ChatConversationCopy.swift:98`); an empty completed
reply given its own notice rather than folded into "connection dropped" (`:166-169`); a reply
that arrived and could not be saved, which says it will be gone when the sheet closes
(`:178-182`). `.notYetScored` and `.noVerdict` are split so the app never tells someone to wait
for a score that is not coming (`ChatModel.swift:157-171`, `ChatConversationCopy.swift:74-85`).
The empty transcript, the composer placeholder and the load failure are all worded from the
subject and degrade to an honest generic when the subject is not yet known
(`ChatConversationCopy.swift:30-55`).

**5.2 The three places it falls short**, each already filed above:

- §2.5 — a failed delete says nothing, and the row silently returns. The only genuine
  invention I found.
- §2.3 — the proposal card keeps asserting a diff that the save has already applied.
- §2.7 — the model is told the transcript was truncated; the athlete is not.

**5.3 One absence is stated well but leads nowhere.** Every no-key and bad-key notice says
"in Settings" (`ChatFailureNotice.swift:83-103`), and the chat sheet's toolbar carries only the
history button, **New chat** and Done (`ChatConversationView.swift:247-268`). There is no
`settingsToolbarItem()` on this sheet and no path to Settings from inside it. The copy is
right; the app makes the reader do the navigating.

**5.4 A malformed reply is handled correctly and cannot be fixed by the athlete.**
`.unreadableResponse` says the reply arrived in a shape the app could not read, that nothing of
theirs was lost, and that asking again will not change it (`:132-138`) — and `isWorthRetrying`
is false for it (`ChatStreamError.swift:117`), so no retry button appears. That is the right
answer to an API contract mismatch. It also means the athlete's only recourse is a fix in the
app, with nothing on screen that could produce one; that is honest and there is nothing better
to do.

---

## 6. Where this falls short of a top-shelf iOS chat in 2026

Separated from §2 because these are craft, not defects. The owner funds them differently; they
are also, collectively, most of the distance between "a good chat surface" and "a chat surface
that reads as best-in-class".

**6.1 Replies are rendered as plain text, so Markdown arrives as punctuation.**
`WorkoutChatBubble` draws `Text(message.text)` (`ChatConversationView.swift:700`) where
`message.text` is a `String`. SwiftUI's `StringProtocol` overload does not parse Markdown —
only the `LocalizedStringKey` overload does. So `**bold**`, `- ` bullets, `1.` lists and
backticks come through as literal characters. `workoutTask` and `trainingTask` both ask for
short conversational answers rather than reports (`ChatModel.swift:1175-1178`, `:1221-1223`),
which reduces how often this bites, but no instruction prohibits emphasis and models emit it
routinely. The same `Text(message.text)` draws the pending reply (`ChatPendingReplyView.swift:88`),
so the same applies mid-stream.

**6.2 Nothing in the transcript can be selected or copied.** `.textSelection` appears nowhere
in `App/`, and there is no `.contextMenu` on a bubble. A person cannot copy an answer out of
this app by any means. In a chat interface that is a floor, not a nicety.

**6.3 VoiceOver cannot tell who said what.** `WorkoutChatBubble` (`:665-729`) applies no
accessibility modifier at all. User and assistant turns are distinguished visually by
alignment and fill (`:670-679`, `:699-705`) and to VoiceOver by nothing — the transcript reads as an
undifferentiated run of paragraphs. Notice rows (`:690-694`) are likewise unmarked, so
"Connection dropped…" is read in the same voice as an answer. This is the one accessibility
gap that matters here, and it stands out because the rest of the feature's accessibility work
is careful: `ChatPendingReplyView` labels its live rungs (`:59-71`), the composer's control
speaks all four of its states (`ChatComposerView.swift:191-196`), the thread row composes its
sentence in the core (`ChatThreadListView.swift:186-188`), and the jump-to-latest control
carries its difference in the label rather than a tinted badge (`ChatComposerView.swift:270-277`).

Related: nothing announces that a reply has *finished*. `pendingAccessibilityLabel` covers
waiting, streaming and stalled (`ChatConversationCopy.swift:150-157`) and the terminal rungs
deliberately return nil — correct for a label, but there is no `AccessibilityNotification`
anywhere in `App/`, so a VoiceOver user gets no event when the answer lands.

**6.4 A reply in flight cannot be stopped.** `ChatModel.stream` consumes the stream to its
terminal event with no cancellation path (`ChatModel.swift:849-897`), and
`ChatComposerSendControl` already carries the `.stop` state and the
`ChatComposerCancellation` axis for the day it exists (`ChatComposerState.swift:20-24`, `:64`).
The seam is designed and unfilled. Every mainstream chat client has a stop button; the honest
current control is a progress indicator, which is what the app draws, so this is a gap rather
than a lie.

**6.5 A draft in the composer does not survive the sheet.** `composerText` lives on `ChatModel`
(`ChatModel.swift:263`), which is `@State` on `ChatConversationView`
(`ChatConversationView.swift:93`) and is recreated on `.id(opening)` change
(`ChatSheet.swift:105`) and destroyed on dismiss. Type half a question, tap Done or drag the
sheet, come back: it is gone. Worth noting the sheet is drag-dismissible by design
(`ChatSheet.swift:181` gives the transcript the drag but the grabber still dismisses).

**6.6 There are no haptics anywhere in the app.** `.sensoryFeedback` appears in no file under
`App/`. Send, reply-complete, failure and proposal-arrival are all silent to the hand.

**6.7 The empty transcript invites and does not suggest.** `emptyTranscriptInvitation`
(`ChatConversationCopy.swift:40-46`) is one good sentence naming three example topics — and
they are prose, not taps. The athlete has no way to discover what the thread can actually see
(a training thread's runs strip is the closest thing, and it sits *below* the transcript). Two
or three tappable starters, derived in the core from the subject, would carry the same
information as an affordance.

**6.8 Bubble typography carries no timestamps and no turn grouping.** Every bubble is the same
`bodyCopy` in the same shape at the same spacing (`ChatConversationView.swift:699-705`), with
no time anywhere in the transcript and no visual grouping of consecutive turns. For a
conversation resumed across days — which is the norm here, since a weekly thread spans a
week — there is nothing on screen that says when anything was said. The thread *list* has a
compact stamp and recency bands; the transcript has neither.

**6.9 The thread list has no search.** §4.3.

---

## 7. Hypotheses I could not verify

Listed separately and deliberately excluded from §8's ranking.

**7.1 The Ask button's label may be left stale by a sheet dismissed over a pushed workout
screen.** `ChatSheet` can push a `WorkoutDetailView` from a runs-strip chip
(`ChatSheet.swift:124-125`), and that view sets `chatEntryPointFocus`
(`WorkoutDetailView.swift:76`) on the model owned by `RootTabView`
(`RootTabView.swift:178-180`). If `onDisappear` does not fire for a view inside a dismissing
sheet, the accessory behind it would keep reading "Ask about this run" on a tab root.
`ChatEntryPointFocus.release(_:)` is identifier-matched (`ChatEntryPoint.swift:54-57`), which
defends against reordering but not against the event never arriving. **I could not test this**
and SwiftUI's behaviour here is not something I will assert from reading.

**7.2 How often §6.1's Markdown actually bites** depends on model output I cannot sample. The
code fact is certain; the frequency is not.

**7.3 Whether §2.4's fetch is slow enough to be felt** depends on transcript sizes and device.
The rule violation is certain; "the history button hitches" is a prediction.

**7.4 Nothing in §1 has been seen on a device by me.** The design claims in §1.4, §1.5 and §1.6
are read from code and from the tickets' own doc comments. `docs/DEVICE-CHECKS.md` is where
those belong.

---

## 8. Ranked tickets

Two ranked lists, because a crash and a composer treatment are funded differently. Within each,
first is worst. 🔒 = `/security-review` before merge, per CLAUDE.md.

### 8.1 Defects

| # | Ticket | One line | Files | Tier | Why this tier |
|---|---|---|---|---|---|
| **MAX-185** | **"New chat" must do something** | §2.1. Either mint a genuinely new thread for an unchanged scope, or say "you are already in this window's conversation" and disable. Decide it in the core beside `ChatScopeNotice` so the toolbar button and the banner cannot disagree | `App/Chat/ChatSheet.swift`, `App/Chat/ChatConversationView.swift`, core: new state beside `ChatScopeNotice` | **Sonnet** | One inert control, but the fix is a product decision (does a second thread per window exist?) that wants an argument, not a patch |
| **MAX-186** | **The workout chat card becomes a door and refreshes** | §2.2. Make the card tappable to open that run's thread, and reload the preview when the chat sheet dismisses. Reconcile with §2.1's "two chat buttons on one screen" — the card *is* the second control now, and the answer is that it is a preview-with-affordance, not a duplicate button | `App/Workouts/WorkoutChatSectionView.swift`, `App/Workouts/WorkoutDetailView.swift` | **Sonnet** | Small diff, but it re-opens a design argument MAX-098 settled and must settle it again on the record |
| **MAX-187** | **A proposal does not outlive its save** | §2.3. Clear `ChatModel.planDrafting` when the authoring screen it opened stores a version, so the card cannot keep offering a diff that has been applied. Decide in the core whether "accepted" is a third `PlanDraftingState` case | core: `Chat/ChatModel.swift`; app: `App/Chat/ChatSheet.swift`, `App/Plan/PlanAuthoringModel.swift` | **Sonnet** | Crosses a screen boundary and touches the plan-writing path; needs care, not depth |
| **MAX-188** | **The thread list stops decoding every transcript** 🔒 | §2.4. Give `ChatThreadRecord` the fields a summary needs (preview line, last-activity) or fetch with a projection, so `threadSummaries()` reads no `messagesJSON`. Batch the workout lookup. Honour `ChatThreadSummary`'s stated contract in the one implementation the app uses | `App/Persistence/MaximizeStore.swift`, `App/Persistence/MaximizeSchema.swift` | **Sonnet** 🔒 | Schema-adjacent (every property needs a default, A8's CloudKit rules still bind) and it touches how health data sits in memory |
| **MAX-189** | **A failed delete says so** | §2.5. Restore the row and state the failure, in `ChatThreadListCopy`'s voice, the way `couldNotSaveReply` does one surface over | `App/Chat/ChatThreadListModel.swift`, core: `Chat/ChatThreadListPresentation.swift` copy | **Haiku** | Mechanical: one `try?` becomes a `do`, one string, one state |
| **MAX-190** | **The chat sheet and the plan form stop presenting each other** | §2.6. Suppress `conversationalRouteSection` on an authoring screen that was itself pushed from a chat sheet, or reassign rather than present. Whichever, say which in the PR | `App/Plan/PlanAuthoringView.swift`, `App/Chat/ChatSheet.swift` | **Sonnet** | The fix is small; choosing between suppression and reassignment is a navigation argument |
| **MAX-191** | **The athlete is told when the transcript was capped** | §2.7. Surface `ChatInstruction.droppedTurnCount` as one quiet line above the replayed window, in the same register as the scope banner | `App/Chat/ChatConversationView.swift`, core: `Chat/ChatModel.swift` (expose the count), `Chat/ChatConversationCopy.swift` | **Haiku** | The value is already computed, public, and untested against nothing; this is a read and a string |

### 8.2 Context continuity — the owner's ask

| # | Ticket | One line | Files | Tier | Why this tier |
|---|---|---|---|---|---|
| **MAX-192** | **The training roll-up carries the load figures the app already computes** 🔒 | §3.2. Strain per session on the session line; the window's acute:chronic ratio and its `.buildingHistory` absence in the tallies block. Every figure through the function the dashboard tile reads, extending `TrainingContextAgreementTests` rather than writing a parallel suite. `MAX-178`'s no-verdict rule holds — report the ratio, never call it high or low | core: `Context/TrainingContext.swift`, `Context/TrainingFactSheet.swift`, `Context/ContextBuilder.swift`; tests | **Opus** 🔒 | Touches `Context/` and changes what leaves the device, so CLAUDE.md mandates the review. The agreement property is the acceptance criterion and it is easy to satisfy carelessly |
| **MAX-193** | **A workout thread learns which week it is in** 🔒 | §3.3. A fixed-size `## The week this sits in` block: the Monday-first week, its arc week and prescribed long run, that week's tallies, the acute:chronic ratio as of that day, and the session count. **Aggregates only — no sibling session lines.** **Blocked on an amendment (A29)** stating the widened answer for the workout subject; do not dispatch before that paragraph exists | `docs/PRD-AMENDMENTS.md` first; then core: `Context/WorkoutContext.swift`, `Context/WorkoutFactSheet.swift`, `Context/ContextBuilder.swift`, `Chat/ChatModel.swift` (the widened fetch), `Chat/ChatInstruction.swift`'s `workoutTask` | **Opus** 🔒 | The hardest judgement in the list: it widens a prompt, it must not become `TrainingContext` by a side door, and `workoutTask` has been deliberately unchanged since MAX-096 as a regression promise that this ticket breaks on purpose |
| **MAX-194** | **A run's conversation has a door to the plan's** | §3.5. One affordance on a workout thread that opens a training thread on the current window — `ChatSheet` already reassigns `opening` for **New chat**. Gate it in the core, not the view. **Do not touch `canDraftPlan`'s training gate** | `App/Chat/ChatSheet.swift`, `App/Chat/ChatConversationView.swift`, core: `Chat/ChatConversationCopy.swift` | **Sonnet** | Reuses an existing mechanism; the only judgement is the copy and where the control sits |

### 8.3 Craft — the distance to top-shelf

| # | Ticket | One line | Files | Tier | Why this tier |
|---|---|---|---|---|---|
| **MAX-195** | **Replies render as Markdown and can be copied** | §6.1, §6.2. Parse assistant text as `AttributedString(markdown:)` with a plain-text fallback that never shows a parse failure; `.textSelection(.enabled)` on bubbles and a copy action in a `.contextMenu`. Decide in the core which turns are Markdown-bearing (assistant yes, user and notice no) | `App/Chat/ChatConversationView.swift`, `App/Chat/ChatPendingReplyView.swift`, core: a small `ChatMessageRendering` decision + tests | **Sonnet** | Markdown mid-stream on partial text is the trap — a half-arrived `**` must not flicker — and that is a decision worth putting under test |
| **MAX-196** | **The transcript is legible to VoiceOver** | §6.3. Speaker attribution on every bubble, a distinct trait for notice rows, and an announcement when a reply lands. Compose the sentences in `ChatConversationCopy` beside the ones MAX-150 already moved there | `App/Chat/ChatConversationView.swift`, core: `Chat/ChatConversationCopy.swift` | **Sonnet** | Accessibility is part of the ticket, not a follow-up; the announcement's timing is the only subtle part |
| **MAX-197** | **A reply in flight can be stopped** | §6.4. Cancellation on `ChatModel.stream`, a new terminal rung or a reuse of `.interrupted` on the ladder, and the call site flipping `ChatComposerCancellation` to `.available`. A cancelled turn is not persisted and its partial text stays on screen, matching the failure rule | core: `Chat/ChatModel.swift`, `Chat/ChatReplyPhase.swift`, `Chat/ChatComposerState.swift`, `Chat/StreamingChatModelInvoking.swift`; app: `App/AnthropicStreamingChatClient.swift` | **Opus** | Adds a state to a state machine that four surfaces read, and touches the transport. The seam is designed for it, which is why it is Opus and not larger |
| **MAX-198** | **A composer draft survives the sheet** | §6.5. Hold the unsent text per subject across a dismissal — in memory for the app's lifetime is enough; do not write a question to disk that was never sent, per "only completed turns are persisted" | `App/Chat/ChatSheet.swift` or `App/RootTabView.swift`, core: a small keyed store | **Sonnet** | The persistence rule is the constraint, and getting it wrong writes health-adjacent text to disk |
| **MAX-199** | **Haptics, and a way to Settings from a keyless thread** | §6.6, §5.3. `.sensoryFeedback` on send, reply-complete, failure and proposal-arrival; `settingsToolbarItem()` on the chat sheet so "add a key in Settings" is one tap | `App/Chat/ChatConversationView.swift`, `App/Chat/ChatSheet.swift` | **Haiku** | Two existing modifiers at known call sites |
| **MAX-200** | **Conversation starters on an empty thread** | §6.7. Two or three tappable prompts, derived in the core from the subject, that fill the composer rather than sending. They are also the cheapest honest answer to "what can this thing see?" | core: `Chat/ChatConversationCopy.swift` (or a new `ChatStarters`), app: `App/Chat/ChatConversationView.swift` | **Sonnet** | The copy is the whole ticket and it has to be right in two subjects' voices |
| **MAX-201** | **The thread list is searchable, and the transcript is dateable** | §4.3, §6.8. `.searchable` over titles and previews, filtering in the core; and a day separator in the transcript for a conversation resumed across days | `App/Chat/ChatThreadListView.swift`, `App/Chat/ChatConversationView.swift`, core: `Chat/ChatThreadListPresentation.swift` | **Sonnet** | Two surfaces, and search over a list whose rows are banded by recency needs the banding to survive a filter. Sequence after MAX-188 |

### 8.4 Dispatch notes

- **MAX-192 is the one to run first.** It is the owner's question, it is the cheapest of the
  three continuity tickets, it needs no amendment, and it is core-only so CI verifies it end to
  end.
- **MAX-193 is blocked on a paragraph, not on a ticket.** Writing A29 is minutes of the
  overseer's time and it must precede dispatch, per A12 rule 2.
- **MAX-192 and MAX-193 collide** in `Context/ContextBuilder.swift`. Land 192 first; it is the
  smaller and it establishes the agreement test 193 should extend rather than duplicate.
- **MAX-188 and MAX-201 collide** on the thread list. 188 changes what a summary is read from;
  201 filters summaries. Sequence 188 first.
- **MAX-185, MAX-190 and MAX-194 all touch `App/Chat/ChatSheet.swift`.** They are three
  different questions about the same 200-line file and should not run in parallel. Order:
  185 → 194 → 190.
- **Every ticket in §8.3 is App-layer**, which CI compiles and never executes (tracker R13).
  Each needs a *Needs device verification* list. §8.1's MAX-188 is App-layer too.
- Nothing here proposes moving D1, D2 or D8. MAX-187 comes closest — it touches the path from a
  proposal to a stored plan — and it must not add a write; `PlanAuthoringSession.plan(from:effectiveFrom:)`
  remains the only door (A13).

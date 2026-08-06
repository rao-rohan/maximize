# Device verification checklist

CI compiles every line of this app and never draws a pixel, opens a socket, touches a
Health store, or opens Keychain. For everything below, **CI is not the gate — this list
is.** It is gathered from the *Needs device verification* sections of the merged PRs
(`rao-rohan/maximize` #101–#157) and cross-checked against `PROJECT_TRACKER.md`'s
per-ticket write-ups, then reordered into the sequence a person would actually work
through on a phone, instead of thirty separate lists in ticket order.

**63 checks below, gathered from 32 merged PRs.** Every check names the PR it came from
so a failure can be traced back to the ticket that owns the surface. Nothing here is
invented — where a PR reported a gap rather than a check, it is noted as a gap, not
turned into a tick box.

If you only have twenty minutes, run the eight checks in **"Run these first."** They are
the ones the tickets themselves flagged as most likely to fail, and each names what a
failure would actually mean for the app.

---

## Run these first

Ranked by what the tickets that built each surface said about their own risk — not by
ticket number.

### 1. The every-launch Health nag
**Do:** Grant (or refuse) Health access on first launch, then relaunch the app *before*
authoring a plan.
**Expect:** The setup card reads **"No plan yet"** (state 2). It must not re-show
"Health access has not been requested" (state 1).
**Why this is top of the list:** three separate tickets flagged this exact failure mode
by name before it was built — MAX-162 called the per-launch-vs-device-lifetime
distinction "the likeliest wiring mistake in the set," MAX-163 built the gate specifically
to close it, and MAX-164 did a second pass to reconcile the card against MAX-163's
recording after finding the same seam. If it fails, a working install nags the athlete
for Health access on every single launch — the exact bug a fresh install exists to avoid.
**Source:** MAX-162, MAX-163, MAX-164 (#154, #155, #156).

### 2. App-layer wiring that compiles but never executes (R13)
**Do:** Exercise these four paths for real, not by reading the diff:
- Tap muscle groups on a lift, force-quit, reopen — MAX-145 (#123).
- Launch with lifting history on the device and confirm nothing hangs or errors — the
  miscategorised-score labelling pass, MAX-134/MAX-143 (#134, #136).
- Provoke a failed Keychain read in Settings and confirm **Clear** is still offered — MAX-154 (#137).
- Relaunch after the first-run cover, and confirm it does not reappear — MAX-163 (#155).

**Why:** R13 in `PROJECT_TRACKER.md` records that this exact class of bug — a defaulted
parameter silently selecting a no-op store — has already happened **twice**, the second
time the same hour the first was found, and CI could not see either instance because
`App/` compiles and never runs. Every one of the four paths above is new App-layer
plumbing (a SwiftData record, a `UserDefaults`-backed recording, a launch-time pass) that
CI has only ever compiled.

### 3. The store opening with two new record types
**Do:** Launch the app normally and, if you can attach a device, filter Console on
category `persistence`.
**Expect:** Nothing appears. The launch is unremarkable.
**Why:** This build added `MuscleGroupEntryRecord` (MAX-145) and
`MiscategorisedScoreLabelRecord` (MAX-143) to the SwiftData schema — the first time either
has opened against a real on-disk store. **If the store fails to open, every screen
degrades, ingestion falls back to the anchor-pinning sink, and nothing is written
anywhere.** Before MAX-154 (#137) that reason went nowhere at all; it is now logged, so
this check also verifies the fix.

### 4. The Ask button riding the minimizing tab bar
**Do:** On each of the three tabs, scroll down until the tab bar minimises, then scroll
back up.
**Expect:** The persistent Ask control travels with the bar and never disappears or
overlaps it.
**Why:** MAX-098 (#118) is the first real production use of `tabViewBottomAccessory` in
this codebase, chosen specifically because the alternative (an overlay capsule) couldn't
satisfy the accessibility constraint. The PR says plainly: "this is reversible in one
modifier in one file if the shape reads badly on device" — which makes this the check
most likely to trigger a design reversal, not just a bug report.

### 5. Chat's stalled-reply state
**Do:** Ask a question long enough that the reply visibly pauses mid-stream.
**Expect:** "Still connected — nothing new for a moment." appears under the partial text.
**Why this may not be checkable at all:** MAX-152 (#138) built this state from the
Anthropic API's `ping` heartbeat frames, but the PR says outright: "if it never appears in
normal use, the open question is whether the live API emits `ping` frames during a stall
at all." This is the one check on this list where a negative result doesn't necessarily
mean a bug — read the "cannot be checked" section below before filing anything.

### 6. The first plan's default effective date
**Do:** With workouts already captured and no plan authored, open plan authoring.
**Expect:** "First day governed" opens on the **earliest captured workout's date**, not
this week's Monday. Save at that date, then open a workout from before this week and
confirm it now shows derived metrics.
**Why:** this was tracker risk **R16** — "a first plan dated later than the history
already on the device destroys that history, permanently and silently." MAX-165 (#152)
calls it "the highest-value defect on the board." A wrong default here doesn't produce a
visible error; it silently and permanently strands the athlete's own captured history
with no derived metrics and no way to recover it, because a later plan version cannot
reach backward (MAX-011/D1).

### 7. Plan drafting never writes until you save
**Do:** In a training chat, draft a plan, read the proposal card, then back out without
saving.
**Expect:** The plan in force on the Plan tab is completely unchanged — no new version.
**Why:** the near-miss this ticket (MAX-101, #124) exists to avoid is named in the docs
as **A13**: a conversational path accidentally becoming a second door into storage. D1
depends on there being exactly one door (`PlanAuthoringSession`). The PR pins this in two
tests that fail if a repository write ever happens along this path — this check is the
device-side confirmation of that boundary.

### 8. The mixed-day calendar glyph
**Do:** Find or create a day where the plan prescribed both a run and a lift and only one
happened, and look at its calendar cell at both month and year density.
**Expect:** `circle.lefthalf.filled` reads legibly as "half of it happened" against the
red fill, distinguishable from a plain miss (`xmark`).
**Why:** MAX-135 (#143) names this explicitly as "the judgement nobody without a phone
can make" — the whole non-hue channel for this state is a glyph at ~42pt (and effectively
invisible at year density), and no amount of reading the diff settles whether it reads as
information or as noise.

---

## 1. First launch on a clean install

| # | Check | Expect | Source |
|---|---|---|---|
| 1.1 | Delete the app, reinstall, launch | A `fullScreenCover` appears: title, a Health paragraph, a privacy paragraph, one **Continue** button. Nothing else — no carousel, no illustration | MAX-163 (#155) |
| 1.2 | Tap Continue | The iOS Health permission sheet appears | MAX-163 (#155) |
| 1.3 | Answer the Health sheet, either way | The cover dismisses immediately claiming **no result** — no checkmark, no "you're all set" (R10 — the app can never verify a grant) | MAX-163 (#155) |
| 1.4 | Tap Continue, then background and force-quit the app before the sheet is answered; relaunch | The cover reappears rather than getting stuck presenting nothing, and a second Continue tap still works | MAX-163 (#155) |
| 1.5 | Look at the Workouts tab in every list state (loading, failed, empty, loaded) | The setup card sits above the list in all four states — it is not gated on the list having loaded | MAX-164 (#156) |
| 1.6 | Device with no Health store (an iPad, if one is available) | The card names the device can't provide Health data and offers **no button** — no plan/key steps are offered either, since neither can matter | MAX-164 (#156) |
| 1.7 | Tap "Author a plan" on the setup card | Pushes `PlanAuthoringView` (not a sheet); saving moves the card to the next state within the same visit | MAX-164 (#156) |
| 1.8 | Tap "Add a key" on the setup card | Presents Settings as a sheet; adding a key and tapping Done moves the card past that state | MAX-164 (#156) |
| 1.9 | Reach the "set up, nothing recorded yet" card state | The card's own copy is the only absence text on screen — the plain "No workouts yet…" text must **not** also appear below it | MAX-164 (#156) |
| 1.10 | Once a workout arrives | The card disappears entirely and does not return on a later launch, even if the key is later cleared in Settings | MAX-164 (#156) |
| 1.11 | Open plan authoring with captured history and no plan yet | "First day governed" defaults to the **earliest captured workout's date**, not this week's Monday | MAX-165 (#152) — see "Run these first" #6 |
| 1.12 | Drag that date forward past some captured runs | An excluded-workout count appears beneath the picker and updates live, with correct singular/plural | MAX-165 (#152) |
| 1.13 | Drag the date back to the suggested one | The count line **disappears entirely** — never "0 workouts" | MAX-165 (#152) |
| 1.14 | Check the count line at the largest Dynamic Type size | It is the longest sentence in that section — confirm it wraps legibly rather than clipping | MAX-165 (#152) |
| 1.15 | Author a **revision** (not a first plan) | No excluded-workout count appears at any candidate date | MAX-165 (#152) |
| 1.16 | Open Settings | The new API-key purpose footer ("Maximize calls Claude to score…") renders under the key controls, reads at larger Dynamic Type sizes, and doesn't crowd the Save/Clear buttons | MAX-167 (#153) |

## 2. Ingestion and scoring

| # | Check | Expect | Source |
|---|---|---|---|
| 2.1 | Record or sync a strength session on a day the plan prescribes an easy run | Appears in the workout list, keeps its heart-rate chart, shows **no score** (previously it would have shown a red/amber 20–45) | MAX-111 (#102) |
| 2.2 | Look at that same lift | No cadence is drawn — the cadence band shows its absence state, not a number | MAX-111 (#102) |
| 2.3 | Do a run on the same day | Still scores normally — the gate is on discipline, not on the day | MAX-111 (#102) |
| 2.4 | Record a lift, then a run right after it | Background delivery still drains — the run arrives (this is R11, the pipeline-wedging risk) | MAX-111 (#102) |
| 2.5 | Open a lift's detail screen | The cap line reads as **absent**, not a zero and not "no heart-rate data" — the reading is there, just not applicable | MAX-130 (#111) |
| 2.6 | Same lift | Heart-rate curve and zone splits still draw | MAX-130 (#111) |
| 2.7 | Open a lift with no muscle groups entered | Header reads "Tell me what you trained," **no spinner** | MAX-145 (#123) |
| 2.8 | Set muscle groups, force-quit, reopen | The groups are still there — see "Run these first" #2 | MAX-145 (#123) |
| 2.9 | In the muscle-group sheet, select nothing / reselect exactly what's already recorded | Save is disabled in both cases | MAX-145 (#123) |
| 2.10 | Change an existing muscle-group answer | The section reads back the new answer and the "tell me what you trained" prompt is gone | MAX-145 (#123) |
| 2.11 | Open a lift that was scored 20–45 under the old running rubric | Score, band and rationale read **exactly as before this build** (D8) — nothing about the verdict should have moved | MAX-143 (#134) |
| 2.12 | Force-quit and relaunch with that same lift on screen | The labelling pass is idempotent — writes nothing a second time, score still reads the same | MAX-143 (#134) |
| 2.13 | Delete a labelled workout | Nothing is left orphaned | MAX-143 (#134) |
| 2.14 | Open plan authoring | The minimum-session-duration control sits beside the HR cap; save, reopen, confirm it persisted | MAX-151 (#149) |
| 2.15 | With a duration floor set: a genuine short run above it, and a strength session | Both score/classify normally — neither is misclassified as a fragment | MAX-151 (#149) |
| 2.16 | Effective-days tile, streak tile, and month calendar on a run-only training history | Read **exactly as they did before** MAX-134's obligation-counting change (#136) — this is the regression the PR's own 2,048-week test suite exists to back up on a real plan | MAX-134 (#136) |

## 3. Chat

| # | Check | Expect | Source |
|---|---|---|---|
| 3.1 | Open the thread list; try swipe-to-delete and Edit-mode delete; check row layout at default and largest Dynamic Type | Both delete paths work; rows don't clip at large type | MAX-097 (#113) |
| 3.2 | From the thread list, tap a specific row | Opens **exactly that thread**, not just a thread that happens to share its scope — a real bug caught in review before merge, worth re-checking on device | MAX-097 (#113) |
| 3.3 | Scroll each of the three tabs to minimise the tab bar, then back | The Ask control travels with it — see "Run these first" #4 | MAX-098 (#118) |
| 3.4 | Open a run from Workouts, then from the Dashboard calendar, then a two-workout day and swipe between the two runs | The Ask label tracks the correct subject throughout — must not fall back to bare "Ask" mid-swipe (the ordering bug the core test pins) | MAX-098 (#118) |
| 3.5 | Dynamic Type to AX5 on the Ask control | Label drops from "Ask about this run" to "This run" rather than truncating; nothing on the screen above is obscured | MAX-098 (#118) |
| 3.6 | VoiceOver, Reduce Transparency, Increase Contrast on the Ask control | Reads as one element ("Ask about your training, button" + a date-range hint); goes solid under both accessibility settings, same as the tab bar | MAX-098 (#118) |
| 3.7 | Open a training thread with several sessions in its window | The "Sessions in this conversation" strip appears below the transcript, scrolls horizontally; tapping a chip pushes that exact run's detail screen | MAX-103 (#128) |
| 3.8 | Open a workout thread | No strip at all | MAX-103 (#128) |
| 3.9 | In a training thread, draft a plan, review the card, then back out without saving | Plan in force is unchanged — see "Run these first" #7 | MAX-101 (#124) |
| 3.10 | With lift days already on the plan, draft anything | The card names those days as carried through unchanged; asking to add a lift and drafting again does **not** imply it was done without review | MAX-101 (#124) |
| 3.11 | Tap Discard on a proposal | Transcript says the plan is unchanged; Plan tab agrees | MAX-101 (#124) |
| 3.12 | With no API key stored, tap the draft button; then try in airplane mode | Plain-language copy in both cases — never a status code (this is also the direct regression check for the #400 leak MAX-155 fixed) | MAX-101 (#124), MAX-155/156 (#147) |
| 3.13 | Send a question and watch the placeholder | A shimmering "Thinking…" bubble in the reply's own position | MAX-152 (#138) |
| 3.14 | Turn on Reduce Motion, then separately Reduce Transparency, and send again | The shimmer is **gone entirely** in both cases — not slowed, not instant — leaving static legible "Thinking…" text | MAX-152 (#138) |
| 3.15 | Watch the moment the first token lands | The placeholder disappears exactly then, not beside the arriving text | MAX-152 (#138) |
| 3.16 | Ask something long enough to stall | "Still connected — nothing new for a moment." — see "Run these first" #5 for why this may not be reachable | MAX-152 (#138) |
| 3.17 | Provoke each reachable failure (no key, key rejected, airplane mode, kill the connection mid-reply) | Every notice is free of numbers, status codes, and enum/wire names; "Try again" appears only for the transient ones | MAX-152 (#138) |
| 3.18 | Type in the composer until it wraps to 6 lines, then keep typing | Field grows upward, send-button centre doesn't move; past 6 lines (3 at accessibility sizes) it stops growing and scrolls internally | MAX-153 (#139) |
| 3.19 | Scroll up in a conversation, then tap the composer | You must **stay where you are** — this is a deliberate departure from the pre-153 behaviour and "the change most likely to be noticed"; sign off on it or reject it | MAX-153 (#139) |
| 3.20 | With the transcript scrolled to its top, drag down | The transcript scrolls; the sheet does **not** dismiss (also deliberate — the default would let an overshoot throw the conversation away) | MAX-153 (#139) |
| 3.21 | Scroll up before the first token lands, then again once real tokens arrive | Pill reads "Jump to latest" in the first case, flips to "New reply" in the second — the shimmer must never count as a reply | MAX-153 (#139) |

## 4. The screens

### Dashboard and calendar

| # | Check | Expect | Source |
|---|---|---|---|
| 4.1 | Tap a two-workout day, then swipe between the two workouts | Both load correctly; the bottom-bar "N of M" indicator tracks the active page | MAX-108 (#101) |
| 4.2 | Same day, using only the prev/next chevrons | Reaches both workouts, disables correctly at each end | MAX-108 (#101) |
| 4.3 | Tap a one-workout day | Pushes straight to detail, no paging chrome | MAX-108 (#101) |
| 4.4 | Tap a missed day, a scheduled-rest day, a forthcoming day, an unplanned day | Each shows a sensible alert and dismisses cleanly; nothing navigates | MAX-108 (#101) |
| 4.5 | VoiceOver over a week of cells, on the smallest supported device | Every cell announces as a button with a sensible sentence; tap targets near the grid edge are comfortably 44pt | MAX-108 (#101) |
| 4.6 | Look at a lift day with no verdict | Neutral cell, strength glyph — not a band colour, not the forthcoming hollow outline, not visually a miss; still carries the plan ring if prescribed | MAX-126 (#103) |
| 4.7 | VoiceOver on that same cell and on a day mixing a run and a lift | Reads the correct combined sentence ("Not scored — the plan scores runs" / plan clause where relevant) | MAX-126 (#103) |
| 4.8 | Find a mixed-obligation day (one of two met) | See "Run these first" #8 for the glyph-legibility question | MAX-135 (#143) |
| 4.9 | Compare that mixed cell to a plain miss in the same week | Reads as **worse than** a miss, but distinguishable from it | MAX-135 (#143) |
| 4.10 | A lift-only day (run slot rests) | Ringed, reads as a miss rather than a rest day | MAX-135 (#143) |
| 4.11 | The year heatmap over a mixed day | Collapses onto the miss mark by design — confirm this reads as intended, not as a bug, and that VoiceOver still distinguishes the two | MAX-135 (#143) |
| 4.12 | Increase Contrast / Reduce Transparency on a mixed cell | The glyph stays legible against the red fill | MAX-135 (#143) |
| 4.13 | Look at cards against the screen background, and gridlines on a chart | Cards should read as cards, not a "slightly-less-flat wireframe"; gridlines should read as quiet, not as noise, now that the surface is lighter — both are judgement calls the PR flagged as its main open question | MAX-127 (#105) |

### Plan

| # | Check | Expect | Source |
|---|---|---|---|
| 4.14 | Author a week with both slots: pick "Lift," open the "Groups" menu, toggle a few | "Groups" row updates live; switching back to Rest clears the groups | MAX-137 (#117) |
| 4.15 | Author a run-only plan | No added friction — the lift picker at rest reads as an addition, not a distraction | MAX-137 (#117) |
| 4.16 | Look at a full week of two-slot days | Still reads at a glance; a `.both` day's two-line value doesn't wrap or truncate awkwardly against the weekday label at large Dynamic Type | MAX-138 (#121) |
| 4.17 | VoiceOver on a two-slot day | Reads as one coherent sentence, not two separate stops | MAX-138 (#121) |
| 4.18 | Open a historical (pre-lifting) plan version | Reads identically to how it read before this build | MAX-138 (#121) |
| 4.19 | Set a lift day, open the "Duration & note" disclosure | Starts collapsed ("Not set"); move the stepper, type a note, collapse — label updates to something like "45 min · …" | MAX-148 (#133) |
| 4.20 | Switch that day back to Rest | The disclosure disappears and, switched back to Lift, both fields are blank | MAX-148 (#133) |
| 4.21 | If a chat proposal is available, propose a plan touching a lift's duration/note | The card's Lifts section shows a `.changed` row | MAX-141 (#130) |
| 4.22 | Author a revision with the back-dating rejection message, and the "first week this version governs" preview | Dates read "Aug 5, 2026" style, never "2026-08-05" | MAX-104 (#148) |

### Workout detail and the lifting surfaces

| # | Check | Expect | Source |
|---|---|---|---|
| 4.23 | Open a lift's detail screen | No cadence card, no route card, no splits card, no dashed heart-rate-cap line; a discipline-note sentence explains why | MAX-139 (#145) |
| 4.24 | Same screen, the "Scheduled" row | Shows the lift's own ask (duration + muscle groups), not the day's run ask | MAX-139 (#145) |
| 4.25 | Same screen, the heart-rate curve | Still renders avg/max HR and the curve itself — only the cap line and its caption are gone | MAX-139 (#145) |
| 4.26 | Open a run's detail screen | Completely unchanged — cadence, route, splits, cap line all still appear | MAX-139 (#145) |
| 4.27 | If a device has a historical miscategorised lift score | The new label row renders under the score chip with a correct VoiceOver reading | MAX-139 (#145), MAX-143 (#134) |
| 4.28 | Compare a lift's HR-cap-absence sentence to a run's on a day with no governing plan | The two read as genuinely different sentences — a lift's says it's not a run, a run's says no plan governs the day | MAX-104 (#148) |

## 5. Accessibility

Run as its own pass after the feature checks above — every item below is a real,
already-flagged risk, not a generic reminder.

| # | Check | Expect | Source |
|---|---|---|---|
| 5.1 | Dynamic Type at AX5 across the composer, the mixed-day glyph, plan week rows, the lift duration disclosure, and every failure/absence string added in this build | Nothing clips, nothing overlaps, nothing truncates meaning — several of the new failure strings are the longest on their screen | MAX-153, MAX-135, MAX-138, MAX-148, MAX-154 |
| 5.2 | Reduce Motion across the chat shimmer, the jump-to-latest pill, and the plan lift-duration disclosure | Motion is withheld entirely where the PR says so, not merely shortened | MAX-152, MAX-153, MAX-148 |
| 5.3 | Reduce Transparency / Increase Contrast across the Ask accessory, the composer's two glass capsules, and the mixed calendar cell | All degrade to solid chrome / stay legible, matching MAX-070's standing rule | MAX-098, MAX-153, MAX-135 |
| 5.4 | VoiceOver across the calendar (including the mixed day and the lift day), the chat thread list, the plan's two-slot week, the proposal card, and the muscle-group picker | Each reads as one coherent sentence per element, correct custom actions where relevant (e.g. swipe-to-delete on a thread row) | MAX-108, MAX-126, MAX-135, MAX-097, MAX-101, MAX-145 |
| 5.5 | Look at the mixed-day, missed-day and lift-day calendar states in greyscale or with a colour-blindness simulator, if available | Still distinguishable — MAX-135 widened the existing "no hue alone" test to cover every pair of calendar cells, but that's a computed ratio, not a look | MAX-135 (#143) |

## 6. Second launch and relaunch behaviour

The nag check is the one this section exists for — see "Run these first" #1 for the full
argument. The rest are the same category of bug (state that looks right once and wrong
forever after) surfacing on other surfaces.

| # | Check | Expect | Source |
|---|---|---|---|
| 6.1 | Relaunch a fully set-up install | The first-launch cover does **not** reappear | MAX-163 (#155) |
| 6.2 | Relaunch after granting Health access but before authoring a plan | Setup card reads "No plan yet," not a re-ask for Health — see "Run these first" #1 | MAX-164 (#156) |
| 6.3 | Force-quit mid Health-request (tap Continue, background, kill before the sheet is answered), then relaunch | Cover reappears correctly rather than getting stuck; a second Continue tap still works | MAX-163 (#155) |
| 6.4 | Delete and reinstall | The cover appears again — this is **intended** (the recording is `UserDefaults`, which resets with the app container, same as everything else under A8) | MAX-163 (#155) |
| 6.5 | Relaunch with lifting history on the device | The miscategorised-score labelling pass writes nothing on the second pass | MAX-143 (#134) |
| 6.6 | Relaunch after a workout has arrived, even if the API key is later cleared in Settings | The setup card does not resurface | MAX-164 (#156) |

---

## What a device visit will not settle

Two categories of fact iOS itself will not surrender, however carefully you look —
recorded so time isn't spent chasing a confirmation the platform will not give.

- **Whether HealthKit *read* access was actually granted (tracker risk R10).**
  `authorizationStatus(for:)` reports *share* status only, by Apple's own design. A
  refused read and "no workouts recorded yet" are indistinguishable from inside this app,
  on any device, in any build. Every first-run and setup-card string was written to never
  claim otherwise (`FailureCopyTests` bans the words "connected" and "denied" from every
  Health-related string) — if a check above shows an empty workout list, that is
  consistent with either cause and cannot be told apart by looking harder.
- **Background-delivery timing under real conditions.** MAX-030 documented that
  `.immediate` delivery frequency is a *request* iOS may clamp, and PRD §2's p50 target
  (< 2 minutes) has never been measured against a real wake, only reasoned about. A wake
  that takes longer once is not evidence of a regression; a pattern across many wakes
  would be, and that needs days of ordinary use, not a checklist item.
- **Whether the Anthropic API actually emits `ping` frames during a stalled reply**
  (MAX-152, #138) — the chat stall indicator (checks 3.16 and "Run these first" #5) may
  simply never fire in normal use if it does not. A negative result there is not
  necessarily a bug.
- **Whether prompt caching engages for plan-drafting calls** (MAX-100, #114) — the PR
  states an expectation ("task + schema is long enough to plausibly cross the cacheable
  minimum") but says plainly it cannot be confirmed without `count_tokens` against the
  real model, which no device check can run either.
- **Whether the Keychain retains the API key across an app deletion and reinstall**
  (MAX-161, #151) — Apple's documented behaviour is that it does, but nothing in this
  repo can test it, and it only affects how the setup card's copy reads on a reinstall,
  not anything either code path depends on.

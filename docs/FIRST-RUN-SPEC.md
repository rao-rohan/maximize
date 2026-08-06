# The first-run experience — product specification

**Ticket:** MAX-161
**Date:** 2026-08-06
**Status:** proposal. Nothing here is built. **No view code and no core code was written.**
**Deliverable:** this document, the ticket breakdown in §12, and amendments **A23–A24**
drafted into [docs/PRD-AMENDMENTS.md](./PRD-AMENDMENTS.md).

---

## What this document is, and what it cannot be

**I have not run this app.** There is no Swift toolchain in this container, no simulator,
no device (tracker R1, R2). Every claim below about *what the app does today* is read from
source and cited by file. Every claim about *what a screen looks like* is inference from
view structure and committed tokens. The owner is the only person who has used it.

Two things follow. Every recommendation that depends on a platform behaviour I cannot
test says so at the point it matters and appears again in §13. And the copy below is
written out in full, not described — "explain the key" is not a specification, the
sentence is.

I separate **decisions** (where I resolved a tension and will defend it) from
**recommendations** (where the owner should overrule me freely). §11 is the part where I
argue against the shape of the request itself, as invited.

---

## 0. The recommendation, in six sentences

**A first-run *wizard* is the wrong investment, and I am not proposing one.** The app has
three prerequisites — Health access, a plan, an API key — and the existing screens for two
of them are already correct; what is missing is that nothing on a fresh install points at
any of them, and one of them silently destroys data on the day it is used. So the proposal
is four small things, not a flow: **one full-screen cover on first launch whose single
action is the Health permission sheet**, because that sheet is one-shot and currently sits
three taps deep behind a toolbar button; **a setup card on the Workouts tab** that names
what is left in dependency order and disappears step by step; **a fix to the first plan's
default effective date**, which today strands up to ninety days of just-captured runs as
permanently unscorable; and **a designed waiting state** for the days between "set up" and
"first workout scored". Chat carries none of it, and §10 argues that case against its own
grain. Nothing here may claim Health is connected (R10), and §9 is the rule plus the test
that enforces it.

---

## 1. What a fresh install actually is today

Verified by reading, not assumed. There is no first-run path in the app: searching `App/`
for `onboard`, `welcome`, `first run` and `firstRun` returns only
`AnchoredIngestionPolicy.firstRunBackfill` and a comment in
`App/FileWorkoutQueryAnchorStore.swift`. Neither is a user-facing anything.

So the first launch is this:

| Prerequisite | State on a fresh install | What the athlete is told |
|---|---|---|
| **Health read access** | Never requested. `requestReadAuthorization()` has exactly one call site — `App/HealthAccessSettingsSection.swift:58` — reached only from the Settings *sheet*, itself behind a toolbar button (`settingsToolbarItem()`) | Nothing |
| **A plan** | None. `PlanView` shows its designed empty state with an "Author a plan" button (`App/Plan/PlanView.swift:76`), on the third tab | Only if they open the third tab |
| **An Anthropic API key** | None. Scoring throws `ScoringModelError.noAPIKeyStored`; chat shows `ChatFailureNotice`'s "Add an Anthropic API key in Settings to chat…" | Only after they try to chat |
| **Any workout** | None yet | `FailureCopy.noWorkoutsRecorded` — the R10-correct sentence, on the launch tab |

The launch tab is Workouts (`RootTab.allCases`' order, mounted in `RootTabView`). So the
first thing a new install shows is an empty list whose copy is about a permission the app
has never asked for.

**The observer query *is* registered at launch** (`MaximizeAppDelegate
.application(_:didFinishLaunchingWithOptions:)` → `startObservingWorkouts()`), and the
comment there is honest about what that buys: *"cheap when HealthKit access has not been
granted: the query is registered and simply never fires."* Registration is not permission.
A fresh install is wired end to end and receives nothing, forever, until somebody finds a
button on a sheet.

### 1.1 The two findings that are worse than "nothing points at it"

**(a) The first plan's default effective date strands the backfill.**
`AnchoredIngestionPolicy.standard` fetches **90 days** of history on the first successful
pass (`firstRunBackfill: 90 * 24 * 60 * 60`). `PlanAuthoringSession` for `.firstPlan` sets
`suggestedEffectiveFrom: try today.startOfTrainingWeek()` and `earliestEffectiveFrom: nil`
(`Sources/MaximizeCore/Plan/PlanAuthoring.swift:402–411`). A workout on a day no plan
version governs is stored without derived metrics and can never acquire them — MAX-011
forbids a later version from reaching back, which `App/IngestionComposition.swift:84`
states plainly. **So the default first plan permanently strands every run older than this
Monday**, which on day one is most of what the app just spent its first minute fetching.
Nothing on screen says how many runs that is. §7 fixes this and it is the highest-value
change in this document.

**(b) The one prerequisite the app cannot verify is the one it never asks for.** R10 means
an empty workout list and a refused Health read are indistinguishable from inside the app.
Today the app compounds that: it never asks, so the ambiguous state is also the *default*
state. Asking once, early, does not make read access knowable — nothing can — but it
removes the single largest contributor to the ambiguity, which is that the question was
never put.

---

## 2. The honest minimum, ranked by what breaks without it

The intuitive order is key-first, because the key feels like "setup". That order is wrong,
and the argument is mechanical.

### Rank 1 — Health read access. Total, silent, and the least recoverable.

Without it there is no data, so there is nothing to plan against, score, chart or ask
about. It fails *silently*: the observer query never fires, the list says "No workouts
yet", and that sentence is also what a correctly-working empty app says. And it is the
only one of the three the app cannot check afterwards (R10) — the other two have honest
presence checks (`StoredAPIKeyPresence`, `PlanRepository`).

Recoverable, but only through iOS Settings once the sheet has been answered, and only
back to the 90-day backfill horizon. A month of not noticing is a month gone.

### Rank 2 — A plan. Partial, and the lost part is lost permanently.

Without a plan, capture still works: the workout, its samples, its route are all stored.
What is missing is **derived metrics, a score, a calendar colour, and chat for that run**
(`ContextBuilder` throws `no plan version has been authored`; `WorkoutIngestionPipeline`
reports `.storedWithoutPlan(.noPlanAuthored)`).

It ranks second rather than third for one reason only: `.noPlanAuthored` is completed
later, but `.workoutPredatesEveryPlan` never is. A missing plan is recoverable *for the
future* and irrecoverable *for anything before the date the athlete eventually chooses*.
That asymmetry is what makes §7 a real ticket rather than a nicety.

### Rank 3 — The Anthropic API key. Total for scoring and chat, and fully recoverable.

Without it, nothing is scored and chat cannot open. But `WorkoutIngestionPipeline`'s own
documentation calls the no-key path *"the app's ordinary state on the day it is
installed, not an error"*, and scoring is retried on first view
(`completeIngestion(forWorkout:)`, MAX-033). **Enter a key on day thirty and the previous
thirty days of captured runs get scored.** Nothing is lost by deferring it.

That recoverability is the entire argument for asking last: it is the only step that costs
the athlete money, and it is the only one that can be deferred at no cost. Asking for a
paid API key before the app has shown a person a single one of their own runs is asking
them to fund a promise.

### The ordering that falls out

**Health → plan → key.** Not "most important first" — it is exactly that, but it is also
the order in which each step's *value* becomes visible: access makes runs appear, a plan
makes them measurable, a key makes them judged.

---

## 3. What is proposed, concretely

Four surfaces. Two are new; two are edits to screens that already exist and are already
right.

| # | Surface | New? | Why it exists |
|---|---|---|---|
| **A** | **The first-launch cover** (§4) | New | The Health sheet is one-shot and undiscoverable. This is the only step that cannot be retried into the same UI |
| **B** | **The setup card** on the Workouts tab (§5, §8) | New | Names what is left, in dependency order, one action at a time; and carries the waiting state after the last step |
| **C** | **The API key section** in Settings (§6) | Edit | Reworded. No new place to type a key |
| **D** | **The plan authoring screen's date control** (§7) | Edit | The default that strands history, and the number that makes the cost visible |

**All four read one value.** `FirstRunChecklist`, in `MaximizeCore`, computed from four
facts the app can honestly establish — whether the Health sheet has been *presented*,
whether a plan version is stored, `StoredAPIKeyPresence`, and whether any workout is
stored — and answering with an ordered list of remaining steps and **the single next
one**. Every branch, every ordering rule and every sentence lives there and is tested;
the views observe and render. That is CLAUDE.md's thin-shell rule, and it is what makes
the R10 guarantee in §9 a CI check rather than a promise.

---

## 4. Where the athlete lands, and the single next action

**They land where they land today — the Workouts tab — with one full-screen cover over
it. The single next action is the Health permission sheet.**

### 4.1 Why a cover, when I have just argued against wizards

Because this step, alone of the three, cannot be offered twice. iOS presents the Health
permission sheet once per data type per install; after that, the request returns without
showing anything, and the app cannot tell the difference (R10 again). The sentence that
explains what will be read has exactly one moment in which it can be read, and that moment
is before the sheet. Every other step in this document is an invitation that can sit in a
card until it is taken.

It is a `fullScreenCover`, not a `sheet`: a sheet is dismissible by drag, and a drag past
the one screen that explains what the app is about to ask for is a gesture nobody meant to
make.

### 4.2 What it says

Three elements. Nothing else — no carousel, no feature tour, no illustration.

> **Maximize scores your runs against your plan.**
>
> Next, iOS will ask which health data Maximize may read. It reads completed workouts,
> heart rate, distance, energy, steps and route. It never writes to Health.
>
> Maximize keeps your workouts on this device. The only thing that ever leaves it is a
> summary of a run, or of a training block, sent to Claude when you ask a question.
> Nothing is backed up, so deleting Maximize deletes its history.
>
> [ **Continue** ]

Notes on each, because each is load-bearing:

- **The title states the product, not a greeting.** "Welcome to Maximize" tells a person
  nothing they did not know from tapping the icon.
- **The second paragraph reuses the existing Health sentence verbatim** from
  `HealthAccessSettingsSection` — *"reads completed workouts, heart rate, distance,
  energy, steps and route. It never writes to Health."* One fact, one wording, two places.
- **The third paragraph is the CloudKit answer** (§9.2). It is the only screen in the app
  where an honesty claim has leverage, because it is the only screen that asks for
  something.
- **"Continue", not "Allow" or "Connect".** "Allow" is the system sheet's own word and
  pre-empting it is a small lie about which button does what. "Connect" implies a
  verifiable connected state, which is exactly R10's forbidden claim.

### 4.3 What happens after the sheet

**The cover dismisses. It shows no result.** The app cannot know the result — and this is
precisely the place where a "Connected ✓" would be most tempting and most wrong. There is
no second screen, no checkmark, no "great, you're all set".

If access was refused, the athlete sees the Workouts tab's existing empty-state copy,
which already names the recovery path: *"…if you have recorded some, check Maximize under
Settings › Health › Data Access & Devices."* That sentence is already correct, already
tested (`FailureCopyTests.testTheEmptyListCopyNamesTheUnknowableWithoutAssertingIt`), and
writing a second one for this flow would be the parallel-copy mistake CLAUDE.md warns
about.

### 4.4 Shown once, and how "once" is stored

A device-local flag, not an athlete setting. It goes in `UserDefaults` behind a core
protocol (`FirstRunPresentationRecording`) with the app supplying the adapter — the same
shape `FileWorkoutQueryAnchorStore` uses for the ingestion anchor, and for the same
reason: *"has this device shown this screen"* is device state, not configuration.

**Deliberately not in `AppSettings`.** A SwiftData record that fails to open would make
the cover reappear on every launch, and the one screen guaranteed to appear when the store
is broken should not be the one that asks for health permissions.

Consequence, stated rather than hidden: a reinstall shows the cover again. That is
correct — a reinstall *is* a fresh install as far as the Health sheet and the empty store
are concerned.

---

## 5. The setup card

A `contentSurface(.card)` at the top of the Workouts list, above the rows. Not a modal,
not blocking, not a tab.

### 5.1 Why the Workouts tab only

It is the launch tab, so it is where a person who has just dismissed the cover is
standing. The Plan tab already has a correct, designed empty state with its own "Author a
plan" button; duplicating the invitation there would be two tellings of one fact, which is
the drift `PlanView`'s own comment warns about. The Dashboard's absence is legible from
its own tiles.

### 5.2 Its four states

`FirstRunChecklist` resolves to exactly one of these. The card renders whichever it is
handed and decides nothing.

**State 1 — the sheet has not been presented.** Unreachable in practice (the cover
presents it), reachable in the type — a cover dismissed by a crash, a store that failed at
the wrong moment. Copy:

> **Health access hasn't been requested yet**
> Maximize can't see any workouts until iOS has asked you.
> [ Request Health access ]

**State 2 — no plan.**

> **No plan yet**
> Runs are being captured, but until a plan exists there's nothing to measure them
> against — no metrics, no score, no chat about a run.
> [ Author a plan ]

**State 3 — a plan, no key.**

> **No Anthropic API key**
> Your runs are captured and measured. Scoring and chat both call Claude, which needs a
> key of your own. Runs recorded before you add one are scored when you next open them,
> so nothing is lost by waiting.
> [ Add a key in Settings ]

That last sentence is the one that makes this step honest rather than nagging, and it is
true: `completeIngestion(forWorkout:)` is why.

**State 4 — everything set, nothing recorded yet.** §8.

**State 5 — everything set, and at least one workout stored.** No card. It does not
return.

### 5.3 One action per state, and why the card is not a checklist

A checklist with three rows and three buttons is a list of three things a person must
decide between. `FirstRunChecklist` publishes the *next* step and the view draws one
heading, one sentence, one button — the remaining steps are not hidden, they are simply
not yet the question. If the owner wants the full list visible, the type already carries
it (`remainingSteps`) and it is a view change, not a redesign.

### 5.4 What makes the card go away

Each state's own condition, checked on appear and after returning from the screen it sent
the athlete to. **It does not reappear when a condition later becomes false.** If the key
is cleared in Settings six weeks later, chat and the plan card already say so where it
matters (`ChatFailureNotice`, `PlanDraftingNotice`). A first-run affordance that returns
as a status panel is a nag, and this app has no other nags.

---

## 6. The API key, asked for without it reading as developer setup

Read `App/SettingsView.swift:110–147` and `App/KeychainAnthropicAPIKeyStore.swift` first;
what follows changes neither the store nor where the field lives.

### 6.1 Nothing new is built here, on purpose

There is exactly one `SecureField` that writes to the Keychain, one `saveKey()`, one
`AnthropicAPIKey` validating initialiser. **A second entry point on a first-run screen
would be a second place key material exists in view state**, and the current one already
handles four failure modes carefully (MAX-154). The setup card's action *navigates to the
existing Settings section*. That is a deliberate refusal of the nicer-feeling design.

**A5's tripwire binds this section.** The key is on-device only because this app is
single-user and never distributed. Nothing below implies a hosted key, a shared key, a
trial, an account, or a "sign in" — and none of the copy would survive distribution
unchanged, which is the correct property for copy governed by a tripwire.

### 6.2 What makes it feel like setup today

The section is titled "Anthropic API key" and its body is a presence line, a secure field
and a Save button. It states a mechanism and never states a purpose. A person who does not
already know what an Anthropic API key is learns nothing, and a person who does still is
not told why this app wants one or what it costs.

### 6.3 The change: one sentence above the field

Add a footer to the existing `Section("Anthropic API key")`, at `.metricLabel` /
`Color.textSecondary`, matching the plan section's existing explanatory footer:

> Maximize calls Claude twice: once per workout to score it, and whenever you ask a
> question in chat. Both use your own key, billed to your Anthropic account, and the key
> is stored in this device's Keychain — it is never sent anywhere except to Anthropic.
> Create one at console.anthropic.com.

Four claims, each checkable against source: two call sites (`AnthropicScoringModelClient`,
`AnthropicStreamingChatClient` — plus `AnthropicPlanProposalClient`, which is the chat
path's tap, so "whenever you ask" covers it); the athlete's own account (A5); Keychain
(`KeychainAnthropicAPIKeyStore`); and no third destination.

**The URL is text, not a link.** A tappable link out of a Settings form to a browser, from
a screen holding a `SecureField`, is a control nobody needs on a device where the key is
being pasted from a password manager anyway.

### 6.4 What is *not* proposed

- **No "test this key" button.** It would spend a real call on a real bill to answer a
  question the next scored workout answers for free, and a failed test is
  indistinguishable from a network problem.
- **No key masking or partial display.** `SettingsView`'s own documentation forbids
  reading the stored key back onto the screen. That rule stands.
- **No key entry on the first-launch cover.** §4 asks for one thing.

---

## 7. The plan: seed, offer, or insist — and the date that matters more

### 7.1 Decision: offer. Which is what the app already does, so the ticket is elsewhere.

`StandardPlanSeed` exists and is already the authoring screen's starting draft. The three
options:

**Auto-seed version 1 on first launch — rejected, and not on taste.** D8 makes auto-scores
immutable and D1 makes a correction a *new version that cannot reach backwards*. So a plan
nobody wrote would score every captured run against a 150 bpm cap and a five-run week that
may be nothing like the athlete's training, **and those scores could never be corrected —
only superseded from a later date onwards.** Auto-seeding converts an honest absence ("not
scored yet") into a permanent wrong answer. That is decisively worse, and it is the
strongest argument in this document that comes straight from the locked decisions rather
than from judgement.

**Insist the athlete authors from nothing — rejected.** `StandardPlanSeed`'s own
documentation makes the case: *"shipping no seed and asking the athlete to hand-assemble
an ordered list of rubric bands before the app can score anything is not a defence of D1,
it is a product that does not start."*

**Offer — chosen.** One deliberate tap; the screen it opens is prefilled with the seed, so
the first plan is an edit rather than an assembly. This is exactly the current behaviour.
**So the plan half of first run needs no new mechanism. It needs to be pointed at (§5,
state 2) and it needs its date fixed.**

### 7.2 The date. This is the ticket.

Today, a first plan defaults to `startOfTrainingWeek()` and every captured run before that
Monday is permanently unscorable (§1.1a). On the day the app is installed, that is
essentially the entire 90-day backfill.

**Decision: for a first plan — and only a first plan — the suggested effective date
becomes the day of the earliest workout stored on the device, falling back to
`startOfTrainingWeek()` when no workout is stored.**

**Why this cannot violate D1.** D1 protects the *reproducibility of stored scores*. A
first plan cannot make any stored score irreproducible because there are none: scoring
requires a plan (`ContextBuilder` throws without a `PlanCalendar`), so no score can exist
before version 1 does. `earliestEffectiveFrom` is already `nil` for `.firstPlan` — the
core already permits this; the screen simply never suggests it. For a *revision*, nothing
changes: `earliestEffectiveFrom` still bounds it and `wouldRewriteHistory` still guards
it.

**Why back-dating is honest.** The plan records the athlete's training intent, and that
intent predates the app being installed. Scoring last month's runs against the plan they
were actually run under is more truthful than declaring them unmeasurable because a
piece of software was not present.

### 7.3 The number, which matters more than the default

Whatever the default, the athlete can move the date, and today the screen does not say
what moving it costs. Add, below the date control, a line computed in core:

> **14 captured workouts fall before this date.** They will never be scored: no later plan
> version may reach back past the first one's start date.

Zero-state: the line is absent when the count is zero, rather than rendering "0 captured
workouts".

`PlanAuthoringFormatting.explain(.firstPlan)` already states the permanence in prose. What
it cannot state is the number, because the number depends on what is stored. CLAUDE.md:
numerals do the hierarchy work — a count of one's own runs is the difference between a
caveat and a decision.

**This is a pure core function** — days in, count out — so it is tested on every commit
and it is the single most valuable CI-verifiable thing in this proposal.

### 7.4 Reported, not taken

A workout that syncs *after* the first plan is saved but is dated before its effective
date is permanently unscorable, and nothing tells anyone. A late Watch sync, or a Health
import from another app, does this. It is outside first run and belongs on the board as
its own ticket; naming it here so it is not rediscovered.

---

## 8. The window before anything is scored

Three prerequisites met, and no workout on screen. This lasts until the athlete's next run
finishes and syncs — realistically hours, and legitimately days. **It is the app working
correctly, and it must not read as a failure or as an empty list.**

The card's state 4:

> **Set up. Nothing recorded yet.**
> Maximize is registered for new workouts and will pick up the next one your Watch syncs,
> usually within a few minutes. Workouts from the last 90 days are fetched once, the first
> time access is granted.
>
> If a run you have already recorded never appears, iOS may not have granted read access —
> it never tells the app either way. Check Maximize under Settings › Health › Data Access
> & Devices.

Every clause is checkable: registration (`startObservingWorkouts()` at launch), the pickup
(`applicationDidBecomeActive` → `ingestPendingWorkouts()`, plus background delivery), the
90 days (`AnchoredIngestionPolicy.standard.firstRunBackfill`).

**Read the first sentence of the second paragraph against R10.** "Maximize is registered
for new workouts" is a claim about the observer query, which is true unconditionally. It
is *not* a claim about permission, and the paragraph that follows exists to stop it being
read as one. This is the sentence in the whole document most likely to drift into a lie
during implementation, which is why §9's test enumerates `FirstRunCopy` rather than
trusting a reviewer.

The `.metricLabel` second paragraph is deliberately the same fact as
`FailureCopy.noWorkoutsRecorded`, worded for a person who has just finished setting up
rather than for a person opening an empty app. **If a reviewer thinks the two should be
one string, they are probably right** — the implementing ticket should try collapsing them
first and only add a second sentence if the collapse reads badly in both places.

---

## 9. R10, and the other thing the app must not claim

### 9.1 The rule

**No first-run copy may state, imply, or visually suggest that Health access has been
granted.** Not "Connected", not a green checkmark next to a Health row, not a step marked
done because the sheet was answered.

The app may honestly say: that the sheet has not been presented; that it has been
presented; that this device provides no Health data
(`HealthAccessState.healthDataUnavailable`); and that the request itself did not complete.
`HealthAccessState` has no `granted` case and no `denied` case for exactly this reason,
and `FirstRunChecklist` must reuse that type rather than introduce a boolean beside it.

**A checklist is where this rule dies**, because a checklist wants a tick beside each row
and the athlete has visibly just answered a permission sheet. Two structural defences:

1. **The Health step has no completed state.** It is either "not requested yet" (state 1)
   or it is absent from the card. There is no third rendering for it to be ticked in.
2. **`FirstRunStep` does not model completion.** The checklist publishes what is *next*,
   derived from facts; it does not carry a `isComplete` flag per step that a view could
   decide to draw as a tick.

### 9.2 CloudKit, and whether first run mentions the reinstall

**Yes, once, on the cover, at secondary weight — and nowhere else.** A8 defers CloudKit,
so history does not survive a reinstall, and there is nothing the athlete can do about it.
A warning nobody can act on is noise everywhere except the one screen where the app is
asking to be trusted with health data; there it is what earns the ask.

It appears in §4.2's third paragraph and it also gets the *other* half of the honesty
right — "the only thing that ever leaves it is a summary of a run… sent to Claude". A
first-run screen that said "everything stays on your device" would be false the first time
the athlete opened a conversation, and that is a worse lie than the one R10 forbids
because the athlete would have no way to discover it.

### 9.3 The test

`FailureCopyTests.testNoHealthCopyClaimsAccessWasGrantedOrRefused` already enumerates a
banned-phrase list over `HealthAccessState.allCases`. **Extend it to every string
`FirstRunCopy` can produce, rather than writing a parallel test** — CLAUDE.md says so
about the score-band hue rule and the reasoning is identical: two tests asserting one rule
drift, and the one that drifts is the one nobody remembers to update.

Add to the banned list: `"you're all set"`, `"you are all set"`, `"health is on"`,
`"reading your workouts"` — each a phrase a well-meaning edit would reach for.

---

## 10. Could first run be a conversation? No, and here is the case against my own instinct

The app pivoted chat-first (A9–A15), plan authoring by conversation works
(`ChatConversationView`'s "Draft a plan from this conversation"), the Ask button is
already on every tab, and a training thread does not require a plan — `ContextBuilder`
builds a `TrainingContext` with a nil `PlanCalendar` (`TrainingContext.plan` is optional).
Technically, a conversational first run is buildable today.

**The case for it,** put as strongly as I can: the 419-line authoring form is the least
pleasant screen in the app and CHAT-FIRST §1.1 says so; a person describing their training
in a sentence is how they actually think about it; and a first-run conversation could
gather the plan, the goal and the athlete's context in one exchange instead of three
screens.

**The case against, which wins on four independent grounds:**

1. **The dependency order is inverted, mechanically.** Chat requires an API key. The key
   ranks *third* precisely because it is worthless without data (§2). A conversational
   first run therefore requires the athlete to obtain and enter a paid API key **before
   the app has captured anything at all** — the exact ask §6.1 argues is unearned. This is
   not a preference; it is a hard ordering constraint, and it alone settles it.
2. **Chat cannot write, and that is an invariant.** CHAT-FIRST §2.5: a chat turn may not
   store a plan version, may not change a setting, may not touch the Keychain. Every
   actual first-run step ends in a screen. A conversational onboarding would be a chattier
   index of the same three buttons.
3. **A14 forbids the shape it would want.** "No unattended chat call, ever." A first run
   that greets the athlete is an unattended call at launch; the compliant version is a
   screen with a "start the conversation" button, which is a worse welcome screen than a
   welcome screen.
4. **First run is a state problem, not an interpretation problem.** CHAT-FIRST §1.1 puts
   chat where interpretation is needed. "No key is stored" is a fact the app knows with
   certainty. Paying a model to say it, in wording that varies between askings, is the
   wrong instrument for the one class of statement this app can make deterministically.

**Where chat does belong, and the recommendation I hold loosely.** Once a key exists, a
plan drafted from a conversation is genuinely better than the form, and it already ships.
The setup card's plan step still routes to `PlanAuthoringView` — one deterministic action
that works with no key — and the *authoring screen* is where the conversational route
should be offered, since that is where a person who dislikes the form is standing. That is
a small ticket (§12, MAX-166) and dropping it costs nothing else.

**If the owner overrules any single thing in this document, I expect it to be this**, and
it is one button.

---

## 11. Where I think the request is bigger than the problem

The owner's direction — *"should we have a great experience to create a workout plan,
measure workout efficacy and details"* — reads naturally as "build an onboarding flow". I
think that would be the wrong build, and the case should be on the record rather than in
my head.

**This app has one user, and CLAUDE.md's A5 tripwire says it must keep having one.** A
first-run flow therefore runs at most once per reinstall, for a person who wrote the app.
Measured by use, it is the least-exercised surface in the product. A four-screen wizard
would be a week of work whose main output is a screen its author will see twice.

What is *not* small is the damage the current absence does, and every one of those is a
specific defect rather than a missing flow:

- The 90-day backfill is silently stranded by the default plan date (§7.2). **Data loss,
  permanent, on day one.**
- The Health sheet is one-shot and three taps deep behind a toolbar button on a modal
  (§4.1). **A prerequisite that fails silently and cannot be re-asked.**
- The days-long "set up but nothing recorded" window reads as an empty app (§8).
- The key section states a mechanism and never a purpose (§6.2).

So the proposal is deliberately shaped as **one new screen, one new card, and two edits to
screens that already exist** — roughly a third of what a first-run *flow* would be. If the
owner wants more, the highest-value next thing is not another onboarding screen; it is the
plan screen and the dashboard carrying more numbers, which is MAX-082's board and the
"highly detailed" brief.

**And if only one ticket from this document is ever built, it should be MAX-165** (§7).
It is the only one that prevents permanent data loss, it is pure core logic, and CI proves
it end to end.

---

## 12. Proposed ticket breakdown

Ordered. Each is one agent's work. Files named so collisions are visible. Numbering starts
at **MAX-162** — MAX-157 is the highest merged and 158–160 are assumed taken by work in
flight this session; the overseer should renumber if not.

| # | Ticket | Scope, one line | Files | Depends on | Tier |
|---|---|---|---|---|---|
| **MAX-162** | `FirstRunChecklist` and `FirstRunCopy` | The four facts in, the ordered steps and the single next action out; every sentence in §4, §5 and §8 as a value; reuses `HealthAccessState` and `StoredAPIKeyPresence` rather than introducing booleans | new `Sources/MaximizeCore/FirstRun/FirstRunStep.swift`, `FirstRunChecklist.swift`, `FirstRunCopy.swift`; ⚠️ `Tests/MaximizeCoreTests/FailureCopyTests.swift` (extend the R10 test, §9.3) | — | **Opus** 🔒 |
| **MAX-163** | The first-launch cover | `fullScreenCover` at the root; the one action presents the Health sheet; dismisses with no result claimed; `FirstRunPresentationRecording` protocol in core with a `UserDefaults` adapter in the app | new `App/FirstRun/FirstRunCoverView.swift`, `App/FirstRun/UserDefaultsFirstRunPresentationStore.swift`; core `FirstRun/FirstRunPresentationRecording.swift`; ⚠️ `App/RootTabView.swift` | 162 | Sonnet — **needs device** |
| **MAX-164** | The setup card | States 1–5 (§5.2, §8) rendered from `FirstRunChecklist`; one heading, one sentence, one action each; disappears and does not return | new `App/FirstRun/FirstRunCardView.swift`, `App/FirstRun/FirstRunModel.swift`; ⚠️ `App/WorkoutsView.swift` | 162 | Sonnet — **needs device** |
| **MAX-165** | **The first plan's effective date** | `.firstPlan`'s `suggestedEffectiveFrom` becomes the earliest stored workout's day (fallback unchanged); a core function counting workouts excluded by a candidate date; the line that states it. **Revisions unchanged** | ⚠️ `Sources/MaximizeCore/Plan/PlanAuthoring.swift`, new `Plan/FirstPlanDating.swift`; `App/Plan/PlanAuthoringModel.swift`, `App/Plan/PlanAuthoringView.swift`, `App/Plan/PlanAuthoringFormatting.swift` | — | **Opus** |
| **MAX-166** | The conversational route to a first plan | An "or describe it in a conversation" affordance on the authoring screen, gated on a stored key. **Independent and droppable** (§10) | `App/Plan/PlanAuthoringView.swift`, `App/Chat/` | 165 | Sonnet |
| **MAX-167** | The API key section's purpose footer | §6.3's sentence, in core beside the other key copy; no change to the store, the field, or `saveKey()` | ⚠️ `Sources/MaximizeCore/Failure/FailureCopy.swift`, `App/SettingsView.swift` | — | Sonnet 🔒 |

🔒 = `/security-review` before merge. **MAX-162** because `FirstRunChecklist` reads
`AnthropicAPIKeyStoring` presence and decides what is said about a key; **MAX-167** because
it is key-handling copy. Neither touches a prompt.

### Collisions

- **MAX-163 and MAX-164** both read `FirstRunChecklist`; only 163 touches `RootTabView`,
  only 164 touches `WorkoutsView`. Parallel-safe after 162.
- **MAX-165 touches `PlanAuthoring.swift`**, which is core plan machinery several tickets
  have historically wanted. Land it alone.
- **MAX-165 and MAX-166** both touch `PlanAuthoringView.swift`. Sequence 165 first; 166 is
  droppable.
- **MAX-167 touches `FailureCopy.swift`**, which MAX-162's test file also touches. Copy in
  one file, test in another — no textual conflict, but review them together.

### Suggested order

**MAX-165 first and alone**, because it is the only one preventing permanent data loss and
the only one CI proves end to end. Then **162 → (163 ‖ 164)**. **167** parallelises with
everything. **166** last, or never.

---

## 13. What CI can and cannot prove

**CI can prove**, on every commit:

- `FirstRunChecklist` resolves the right next step from every combination of the four
  facts, including the ones the app should never reach.
- No `FirstRunCopy` string claims Health access was granted or refused (§9.3), for every
  case of every enum it switches over.
- The first-plan suggested date is the earliest stored workout's day, and
  `startOfTrainingWeek()` when nothing is stored.
- The excluded-workout count is right at the boundaries — a workout *on* the effective
  date is included, one the day before is not.
- Revisions are unaffected: `earliestEffectiveFrom` still bounds a revision and
  `wouldRewriteHistory` still fires.

**CI cannot prove any of the following, and every PR above says so:**

- That the cover appears exactly once, or that `UserDefaults` persistence behaves across a
  real relaunch.
- That tapping Continue actually presents the iOS Health sheet, or what it looks like.
- That the cover's copy fits at Dynamic Type AX5, or that the card does not push the first
  workout row off screen at large sizes.
- That the 90-day backfill actually arrives before the athlete authors a plan — which is
  what makes MAX-165's default useful in practice rather than only in principle.
- Whether the Keychain retains the API key across an app deletion and reinstall. Apple's
  documented behaviour is that Keychain items survive deletion; **I could not verify this
  and no test in this repo can.** It matters only for how a reinstall's card reads on
  state 3, and MAX-164 should not depend on either answer.

**Device checklist for whoever installs this** (delete the app first, so it is a genuine
fresh install):

1. Launch. The cover appears; Continue presents the iOS Health sheet.
2. Grant access. The cover dismisses with no claim of success.
3. Relaunch. **No cover.**
4. Workouts tab: the card reads state 2 (no plan). Backfilled runs appear underneath
   within a launch or two.
5. Tap "Author a plan". The suggested date is the oldest backfilled run's day, and the
   excluded-count line is absent (count zero).
6. Move the date forward a week. The count line appears and the number matches the runs
   above it.
7. Save. The card becomes state 3 (no key). Runs acquire metrics but no scores.
8. Add a key in Settings. The card disappears. Open an unscored run: it scores.
9. Delete the app, reinstall, deny Health access. The cover appears and dismisses; the
   list shows the existing R10 empty-state copy; **nothing anywhere says "connected".**

---

## 14. Amendments

Drafted into [docs/PRD-AMENDMENTS.md](./PRD-AMENDMENTS.md) in this PR.

| # | Supersedes / adds | In one line |
|---|---|---|
| **A23** | — (clarifies D1) | A **first** plan may be dated to cover what has already been captured, and does so by default. D1 is untouched, because no stored score can exist before version 1 |
| **A24** | — (bounds A9) | First run is not a conversation. Chat's three jobs do not grow a fourth, and the reason is a dependency order, not a preference |

**No amendment is needed for the cover or the card.** The PRD says nothing about first
launch, so nothing is superseded — this is a gap being filled, not a decision being
reversed. Saying so explicitly because a new top-level screen is exactly the kind of
change that *looks* like it should have one.

---

## 15. What I am deliberately not deciding

| # | Question | Who decides | My lean |
|---|---|---|---|
| 1 | Whether a first-run flow is worth building at all (§11) | Owner | Build MAX-165 and MAX-162/164. MAX-163's cover is the one I would drop if the owner wants less |
| 2 | Whether the card shows the next step only, or all three (§5.3) | Owner | Next step only. The type carries both; it is a view change |
| 3 | Whether the first plan's default should back-date at all, or just show the count (§7.2/§7.3) | Owner | Both, but **the count is the part that must ship**. The default is convenience; the count is the decision |
| 4 | Whether §8's waiting copy and `FailureCopy.noWorkoutsRecorded` should be one string | Whoever builds MAX-164 | Try collapsing them first |
| 5 | Whether the conversational plan route is offered at all (§10, MAX-166) | Owner | Offer it, from the authoring screen only, gated on a stored key |
| 6 | Whether the Keychain survives a reinstall, and what state 3 should read if it does | Whoever builds MAX-164, on a device | Do not depend on either answer |
| 7 | The late-syncing workout dated before the first plan (§7.4) | Overseer | Its own ticket. Reported, not taken |

And one thing explicitly *not* open: **nothing in this proposal moves D1, D2, D8, A5 or
R10.** §7.2 is the one place that comes close, and the argument there is that a first plan
cannot invalidate a score that cannot exist. If an implementing ticket concludes otherwise,
that is an escalation to the overseer, not a change to make.

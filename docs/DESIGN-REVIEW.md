# Design review — the whole app

**Ticket:** MAX-082
**Date:** 2026-08-05
**Scope:** every screen, read as one product, against PRD §7.4 (FR-4.1–4.5) and FR-1.x / FR-3.x.
**Deliverable:** this document. No view code was changed.

---

## What this review is, and what it cannot be

**I have not seen this app.** There is no Swift toolchain in this container, no simulator,
and no device anywhere in this project's CI (R1, R2). Every visual judgement below is read
from source: token values, spacing constants, view structure, and contrast ratios computed
arithmetically from `DesignPalette`. The owner is the only person who has actually looked at
the thing.

Concretely, I **cannot** assess:

- how Liquid Glass renders over these particular surfaces, or whether the tab bar's
  refraction reads well against a near-black background;
- real Dynamic Type reflow — whether the two-column tile grids wrap acceptably at AX5,
  whether the verdict header's 56pt hero numeral pushes the "Effective" label off the row,
  whether calendar cells stay square when their glyphs grow;
- motion — timing, whether the streaming reveal reads as smooth or as jitter;
- perceived colour. Contrast ratios are arithmetic; "does this violet look right on an OLED
  phone at 3am" is not.

Where a finding depends on something I cannot see, it says so. Where a finding is arithmetic
from committed values, the number is in the text and can be checked.

I also separate **defects** — where the code contradicts the PRD, or contradicts its own
stated contract — from **taste**, where I would do it differently and reasonable people
would not. Taste is quarantined in §9. Everything before §9 is a defect or a measurement.

---

## The headline

Twelve agents built twelve screens against one token file, and the tokens did their job:
there are no rogue colour literals, the spacing ramp is used, the type scale is used. The
system is consistent. **The problem is not inconsistency; it is that consistency was
mistaken for design.** Nobody ever asked what the app looks like when it is assembled, and
three things fall out of that:

1. **The app the owner opens is entirely in its empty state, and its empty states promise
   things that will never happen.** (§1)
2. **In dark mode the app is one flat field.** A card differs from the screen behind it by a
   contrast ratio of **1.09:1**. There are no borders, no shadows, no strokes. This is the
   mechanical reason it reads as a competent wireframe. (§2)
3. **The accent colour never reaches a single system control.** `.tint()` is called nowhere;
   there is no asset catalog. Every picker, date picker, button and tab-bar selection in the
   app is untinted iOS blue — which is precisely the thing `ColorTokens.swift`'s own comment
   says the accent must not be mistaken for. (§3)

Fix those three and the app changes character. Everything after them is refinement.

---

## 1. The app the owner actually opens — highest impact

### 1.1 There is no way to author a plan, and the whole product is downstream of one

**Defect (product gap, not styling).**
`PlanRepository.store(_:)` exists (`Sources/MaximizeCore/Persistence/Repositories.swift:141`)
and has **no call site anywhere in `App/`**. `SettingsView` offers rest-day budget, distance
unit and appearance. It does not offer a plan.

This is not a cosmetic point, because almost every state the owner is currently looking at is
a consequence of it. With no plan authored:

| Surface | File | What renders |
|---|---|---|
| Verdict header | `App/Workouts/VerdictHeaderView.swift:90` | "Scheduled: No plan for this day", then a **spinner that never stops** |
| Score | `Sources/MaximizeCore/Scoring/ScoringError.swift:73` | `.noPlanInEffect` — `isWorthRetrying == false`. The run will never score |
| Chat | `App/Workouts/WorkoutChatView.swift:73` | "chat opens once it has a score" — it will not |
| HR curve | `App/Workouts/HRCurveView.swift:125` | Curve draws; no cap line; "No plan governs this day…" |
| Cadence | `App/Workouts/CadenceBandView.swift:46` | Average draws; no band; "No plan governs this day…" |
| Calendar | `App/Dashboard/ScoreCalendarView.swift:160` | Every day `.unplanned` → `surfaceInset` + a `minus` glyph. A month of identical grey squares |
| Drift overlay | `HeartRateDriftOverlayData` line 345 | Every run excluded for want of a stored classification — the chart PRD §1 says no other app can draw shows an apology |
| Trend tiles | `Sources/MaximizeCore/Metrics/TrendTileData.swift:100–118` | Mileage-vs-arc, effective days and avg score all require a plan or a score. Only `streak` survives. **The dashboard's Summary card is one tile reading `0`.** |

**Why it matters.** The owner asked to "modernise the design" while looking at an app in
which the single most prominent element on the detail screen is an indeterminate spinner
under copy that is false, and the dashboard's flagship chart is a sentence explaining its own
absence. No amount of surface polish changes that. This is the review's top finding and it is
not a design finding — it is the reason the design cannot be evaluated in situ.

**Proposed change.** Out of MAX-082's scope; reporting rather than doing, per CLAUDE.md.
Dispatch a plan-authoring ticket (see §10, T1). Until it lands, §1.2 is the mitigation.

### 1.2 The unscored state lies, and it lies with a spinner

**Defect.** `App/Workouts/VerdictHeaderView.swift:90–104`:

```swift
HStack(spacing: Spacing.compact) {
    ProgressView()
    …
    Text("Not yet scored")
    Text("Scoring runs automatically once the run is captured.")
}
```

`WorkoutVerdict.scoring` has exactly two cases — `.unscored` and `.scored` — so this one
branch covers three materially different situations:

- **scoring is in flight** (seconds after capture) — spinner correct, copy correct;
- **scoring failed and will be retried** — spinner defensible;
- **no plan governs this day** — scoring returned `.noPlanInEffect`, which
  `ScoringError.isWorthRetrying` explicitly marks as *not worth retrying*. **Nothing is
  happening. Nothing will happen.** The spinner is animating over a dead process, and the
  copy is a promise the system has already declined to keep.

The view's own doc comment is careful and correct about *not* colouring an undecided state.
It then undermines that care by animating one.

**Why it matters.** A perpetual spinner is the strongest "something is broken" signal iOS
has. The owner's most-visited screen currently leads with it on every workout. Of everything
in this document, this is the single cheapest change with the largest effect on whether the
app feels finished.

**Proposed change.** Split the unscored state in the **core**, not the view —
`WorkoutVerdict.scoring` gains a third case (or `.unscored` gains a reason), decided where CI
can test it. The view then renders:

- *in flight* → spinner + current copy;
- *blocked, no plan* → **no spinner**, a `.metricLabel` line ("No plan covers this day, so
  there is nothing to score against"), and — once T1 exists — an inline affordance to author
  one. This is the one place in the app where the accent earns a call-to-action.
- *failed, retryable* → no spinner, a stated reason.

### 1.3 There are twenty-two distinct absence strings and they are written by three authors

**Defect (voice consistency).** Inventory of every absence/failure string in the app:

| Voice | Files | Examples |
|---|---|---|
| **"Could not …"** (formal) | `WorkoutsView.swift:29`, `WorkoutDetailView.swift:53`, `RouteMapView.swift:96`, `WorkoutChatView.swift:65`, `SettingsView.swift:245,261,270`, `HealthAccessSettingsSection.swift:63` | "Could not load workouts." |
| **"Couldn't …"** (contracted) | `TrendIntervalSelectorView.swift:29`, `ScoreCalendarView.swift:55`, `DriftOverlayView.swift:65`, `TrendTilesView.swift:60` | "Couldn't load the calendar." |

The split is **exactly by directory**: everything under `App/Workouts/` and the root uses
"Could not"; everything under `App/Dashboard/` uses "Couldn't". Two agents, two habits, one
app. A reader will not name it, but they will feel it.

The type treatment splits the same way: Workouts-tab failures render at `.bodyCopy`
(`WorkoutsView.swift:30`, `WorkoutDetailView.swift:54`), Dashboard-tab failures at
`.metricLabel` (`ScoreCalendarView.swift:56`, `TrendTilesView.swift:61`,
`DriftOverlayView.swift:66`). So a failure on the Workouts tab is visibly larger than a
failure on the Dashboard tab, for no reason.

And the *surface* treatment splits a third way. Absences inside detail-screen cards sit on
`.contentSurface(.inset)` — a visible well saying "this is where the thing would be"
(`HRCurveView.swift:150`, `CadenceBandView.swift:128`, `RouteMapView.swift:100`,
`SplitsView.swift:40`, `DriftOverlayView.swift:110`). Dashboard failures are bare text with
no well at all. So of the twenty-two absences, some are framed and some are floating.

**Why it matters.** This app is honest about absence to an unusual degree, and that honesty
is a genuine asset — it is why "no splits recorded" reads better than a fabricated zero. But
twenty-two differently-dressed apologies read as a wall, not as a considered position. The
fix is not fewer absences; it is one absence *component*.

**Proposed change.** Add a single `AbsenceNote` view to `App/DesignSystem/` with two
variants — `.absent` (there is nothing here, and that is fine) and `.failed` (something went
wrong) — that fixes the surface (`.inset`), the font (`.metricLabel`), and the colour
(`textSecondary`). Then normalise voice to one form; I recommend the contracted form
("Couldn't"), because §5 describes a single technical user and the formal register reads as
enterprise boilerplate. Copy itself stays where it is — most of it is already generated in
`MaximizeCore` (`exclusionNotes`, `stackSummary`), which is correct and should not move.

### 1.4 Absence with no route forward

**Taste-adjacent, but worth stating as a pattern.** Several absences state a fact and stop
where a next step exists:

- `SplitsView.swift:37` — "No splits recorded for this run." Every run on the device predates
  MAX-046 (tracker, MAX-067), so this is on *every* outdoor run. It is a backfill, not a
  permanent property of the run, and the copy does not say so.
- `HealthAccessSettingsSection.swift:20` — "Health access has not been requested yet on this
  launch." Truthful and careful (R10), but "on this launch" is implementation detail
  surfacing as user copy.
- `WorkoutsView.swift:35` — "No workouts yet." The one state where a first-run app should
  explain what will make workouts appear, and it says four words centred in a void.

I am not proposing chatty empty states — §5 says the user is technical and the UI should not
hand-hold. I am proposing that an absence with a known remedy should name it in one clause.

---

## 2. Surface and depth — why it reads as a wireframe

### 2.1 The three-level surface system is a 9% step

**Defect, measured.** From `Sources/MaximizeCore/Accessibility/DesignPalette.swift:41–60`,
dark values:

| Step | Values | Contrast |
|---|---|---|
| `surfaceElevated` on `surface` | `#16161C` on `#0B0B0F` | **1.09:1** |
| `surfaceInset` on `surfaceElevated` | `#1F1F27` on `#16161C` | **1.10:1** |
| `separator` on `surfaceElevated` | `#2C2C36` on `#16161C` | **1.30:1** |
| `chartGridline` on `surfaceInset` | `#2A2A33` on `#1F1F27` | **1.15:1** |

For reference, Apple's own dark ramp steps at **1.23:1** (`systemBackground` →
`secondarySystemBackground`) and again at **1.22:1**. Ours is roughly **half the platform's
own separation, applied twice.**

And nothing else carries the boundary. `ContentSurfaceModifier`
(`App/DesignSystem/Surfaces.swift:111–118`) draws a fill and a clip shape — no stroke, no
shadow, no inner highlight. So a card is a 9%-lighter rounded rectangle on black, with no
edge.

**Why it matters.** This is the single largest reason the app reads flat. Every screen in the
app is a vertical stack of `.contentSurface(.card)` blocks; if a card has no visible edge, the
screen is not a stack of cards, it is a column of text and charts floating on black. Robinhood
— the stated content reference — is flat but not *edgeless*: its separation comes from a
genuine surface step plus a lot of white space. We took the flatness and left out the step.

Note that this is **not** a WCAG failure. Surface-to-surface separation is not a WCAG
criterion (1.4.11 governs UI components and graphical objects, not decorative background
steps). It is a design failure measured against the platform's own convention.

**Proposed change** — pick one, not both:

- **(a) Widen the ramp.** `surfaceElevated` dark `#16161C` → about `#1C1C25` (1.16:1 on
  surface), `surfaceInset` → about `#2A2A35` (1.19:1 on the new elevated). Closer to Apple's
  step while staying darker and cooler than the system greys, which is what makes this
  palette its own.
- **(b) Give cards an edge.** Keep the fills; add a hairline stroke at
  `LayoutMetrics.hairline` in a new `surfaceBorder` token (dark ≈ `#32323C`, 1.33:1 on the
  card) to `ContentSurface.card` only — not `.tile`, or the tile grids turn into a wire mesh.

(a) is more "Robinhood", (b) is more "iOS 26". I lean (a) with a light dose of (b) on `.card`
alone. **Both belong in `DesignPalette.swift` as semantic tokens** so `WCAGContrastTests`
covers them — do not add raw values in `ColorTokens.swift`.

### 2.2 The gridlines are effectively invisible

**Defect, measured.** `chartGridline` `#2A2A33` on `surfaceInset` `#1F1F27` is **1.15:1**.
Used at `HRCurveView.swift:102,110`, `CadenceBandView.swift:111`,
`DriftOverlayView.swift:139,151,324,336`. Its doc comment
(`App/DesignSystem/ColorTokens.swift:144`) says gridlines "should be visible and never
compete with the series." They achieve the second half only.

**Proposed change.** Raise dark `chartGridline` to ≈ `#383843` (1.46:1 on inset), which
is still far below `chartThreshold` at 9.96:1 and `chartSeriesPrimary` at 13.42:1 — so it
cannot compete — but is actually present. In `DesignPalette.swift`.

### 2.3 The time-above-cap shading is the faintest mark on the chart that exists to show it

**Defect.** `App/Workouts/HRCurveView.swift:74`:

```swift
.foregroundStyle(Color.chartThreshold.opacity(0.2))
```

Composited over `surfaceInset`, that is `#41414A` — **1.62:1**. PRD §9 calls time-above-cap
"the primary easy-run discipline metric"; FR-1.2 names the shading as a requirement in its own
right. It is currently a neutral grey wash, in the *same hue as the cap line itself*, at the
lowest contrast of any deliberate mark on the screen.

This is a hierarchy inversion: the most important derived fact on the detail screen is drawn
more faintly than the axis labels beside it (`textTertiary` at 4.80:1).

**Why the neutral choice was made, and why I think it was over-applied.** FR-4.3 reserves the
three saturated score-band colours for the calendar and verdict header, and MAX-042 correctly
did not reach for red. But "do not use the *score-band* red" and "the excursion region must be
neutral grey at 20%" are different constraints, and only the first is in the PRD.

**Proposed change.** Two options, in preference order:

1. **Introduce a `chartExcursion` token** in `DesignPalette.swift` — a desaturated warm tone
   distinct from all three score bands (so it cannot be misread as a verdict) at roughly
   2.0–2.5:1 over `surfaceInset`. It is a fill, not text; 3:1 would be too loud for a large
   region.
2. If a new hue is unacceptable, raise the existing neutral to `chartThreshold.opacity(0.35)`
   → `#5A5A64`, **2.40:1** — a fourfold improvement in perceived presence with no new token.
   Weaker than option 1 because the shading still shares its hue with the cap rule.

Either way, opacity should not be a literal at the call site; put it in the token or in
`HeartRateChartData`.

### 2.4 The oldest curves in the drift overlay are below the visibility floor

**Defect, measured.** `HeartRateDriftOverlayData.oldestContextOpacity = 0.28` applied to
`chartSeriesMuted` `#5A5A66` over `surfaceInset` composites to `#303039` — **1.25:1**, drawn
as a **1pt** line (`DriftOverlayView.swift:131`).

The constant's own comment says it is "deliberately not near-invisible — it is the 'before'
in a before-and-after." At 1.25:1 on a 1pt stroke, on a phone, it is near-invisible. FR-3.3 is
about watching drift flatten *across* an interval, which requires the far end of the interval
to be legible; the far end is the end that disappears.

**Proposed change.** Raise `oldestContextOpacity` to ≈ 0.45 (`#3A3A44`, 1.46:1) **and** raise
`chartSeriesMuted`'s base value so the whole ramp sits higher — at full strength it is only
2.41:1 today. Both are one-constant changes with existing test coverage in
`MaximizeCore`. Needs device verification: this is exactly the judgement I cannot make from
arithmetic, because twelve overlapping faint lines behave differently from one.

---

## 3. Chrome, tinting, and whether this looks like iOS 26

### 3.1 The accent reaches nothing the system draws

**Defect, and the most visible one after §2.1.** `.tint()` appears **nowhere** in `App/`.
There is no `.xcassets` in the repo at all, so there is no `AccentColor` asset either.
`Color.accent` has exactly **two** call sites in the shipped app:

- `App/Workouts/WorkoutChatView.swift:115` — the send button's arrow;
- `App/Workouts/WorkoutChatView.swift:139` — the user chat bubble fill.

Both are buried at the bottom of the detail screen's scroll. Everything the *system* draws
falls back to untinted iOS blue:

| Control | File |
|---|---|
| Tab bar selected item | `App/RootTabView.swift:11–26` |
| Segmented interval picker | `App/Dashboard/TrendIntervalSelectorView.swift:55` |
| Week/month chevron buttons | `TrendIntervalSelectorView.swift:77,94` |
| Custom-range `DatePicker`s | `TrendIntervalSelectorView.swift:108,116` |
| Every `Form` picker and button | `App/SettingsView.swift:80,84,122,145,156` |
| Every `ProgressView` | 6 call sites |
| Navigation back chevron | `WorkoutsView.swift:11` |

`ColorTokens.swift:116` states the requirement against itself:

> it must not read as the untinted iOS system blue, which users parse as "default app, no
> design applied", and which is also the color of a link.

The app currently *is* that app. A carefully-argued violet was chosen, tested for contrast,
and then wired to a send button.

**Proposed change.** One line at the root:
`RootTabView`'s `TabView` (or `MaximizeApp`'s `WindowGroup` content) gets `.tint(.accent)`.
That propagates to every control listed above. Then audit for places where the accent should
*not* apply — the chat send arrow is already explicit and stays; destructive actions
(`SettingsView.swift:84`) keep `role: .destructive`.

This is the highest ratio of visible change to lines edited in the entire review.

### 3.2 Two of three tabs have no navigation chrome, so FR-4.1 does not apply to them

**Defect.** FR-4.1 requires Liquid Glass on "tab bar, navigation bars, toolbars, sheets, and
floating controls", largely free from the iOS 26 SDK. It is free only where system chrome
exists.

- `App/WorkoutsView.swift:11–14` — `NavigationStack` + `.navigationTitle("Workouts")`.
  Correct: large title, collapse on scroll, glass bar.
- `App/DashboardView.swift:20–26` — **no `NavigationStack`.** The title is a hand-drawn
  `Text("Dashboard").font(.screenTitle)` inside the `ScrollView`, which scrolls away and never
  becomes a bar.
- `App/SettingsView.swift:56` — a bare `Form`, **no `NavigationStack`, no title at all.**

So the app has three tabs with three different title treatments: a real collapsing large
title, a fake static one, and none. Switching tabs makes the top of the screen jump. This is
the most legible "twelve agents built this" artefact in the app.

`glassChrome(_:)` — the design system's own Liquid Glass entry point — has **zero call sites
outside `DesignSystemGallery.swift:246`.** That is defensible (system chrome supplies its own
glass), but it means the only glass in the app is whatever the SDK grants the one nav bar and
the tab bar.

**Proposed change.** Wrap `DashboardView` and `SettingsView` in `NavigationStack` with
`.navigationTitle("Dashboard")` / `.navigationTitle("Settings")`, and delete the hand-drawn
`Text("Dashboard")`. Note this is adjacent to the navigation restructuring already in flight —
sequence accordingly.

### 3.3 iOS 26 tab-bar behaviour named by FR-4.1 is absent

**Defect.** FR-4.1: "Scroll-collapsing tab bar behavior is expected."
`App/RootTabView.swift` uses the legacy `.tabItem` builder and sets no
`.tabBarMinimizeBehavior`. Nothing in the app collapses.

**Proposed change.** Migrate to the iOS 26 `Tab(_:systemImage:)` builder and add
`.tabBarMinimizeBehavior(.onScrollDown)`. Also consider `.scrollEdgeEffectStyle` on the
scrolling screens so content dissolving under the glass bar reads correctly rather than
hard-clipping. **I cannot verify how either looks** — flag as needs-device.

### 3.4 The Settings screen has a developer section at the top of it

**Defect.** `App/SettingsView.swift:57–59`:

```swift
Section("MaximizeCore") {
    Text("MaximizeCore \(MaximizeCore.version)")
}
```

A package version string in a section named after an internal Swift module, positioned above
Health access and the API key. It is the first thing on the screen.

Beyond that, `SettingsView` is the one screen that uses **none** of the design system — no
`contentSurface`, no `Font` tokens except two `.metricLabel` status lines, no screen title.
It is a raw grouped `Form`. That is not automatically wrong (a system `Form` is a legitimate
iOS pattern and gets its own iOS 26 treatment), but it means the app's visual language stops
at the third tab.

**Proposed change.** Move the version string to the bottom, as a footer, styled `.microLabel`
/ `textTertiary` — where every iOS app puts it. Decide deliberately whether Settings is a
system `Form` (fine, but then say so and drop the two stray design-system fonts) or a
`contentSurface` screen like the other two. Do not leave it as an accident.

### 3.5 There is no app icon

**Observation.** No `.xcassets` anywhere in the repo; `project.yml` generates the Info.plist
with no icon asset. The owner's home screen shows a blank placeholder. A 2026 iOS app that
looks unfinished before it is opened is a design finding, even though it is a one-asset fix.

---

## 4. Hierarchy, screen by screen

### 4.1 The workout list shows everything except whether the run was any good

**Taste, with a defensible counter-argument — but I think the current call is wrong.**
`App/Workouts/WorkoutRow.swift` renders date, activity type, distance, chevron. Nothing about
execution. The app's opening screen — the one the owner lands on — answers "when did I run and
how far", which is the question PRD §1 says Apple Fitness already answers and the question the
owner explicitly does not have.

`WorkoutRow.swift:7–11` explains the omission: FR-4.3 confines the three saturated score-band
colours to the calendar and verdict header, and a fourth place showing green/amber/red would
dilute the signal. **That reasoning is correct and should be kept.**

But it proves too much. FR-4.3 restricts the *colours*, not the *score*. A row could show
`87` at `.metricSecondary` in `textPrimary`, right-aligned, with no colour at all — and the
list would immediately answer the question the product exists to answer, without touching the
band palette.

**Proposed change.** Add the numeric auto-score (or the honest absence of one) to
`WorkoutRow`, uncoloured, at `.metricSecondary`. `WorkoutsListModel` would need to read the
score ledger alongside the workout. The three-colour restriction stays intact.

### 4.2 The dashboard leads with a control, not with a fact

**Taste.** `DashboardView.swift:27` puts `TrendIntervalSelectorView` — a full
`.contentSurface(.card)` containing a segmented picker, a navigation header and, in custom
mode, two `DatePicker`s — as the first thing under the title. The tiles that answer "am I
executing the plan" (FR-3.4) are last, below a calendar and two full-height charts.

FR-3's ordering ("interval selector, calendar, overlay, tiles") is a list of requirements, not
a z-order, and `DashboardView.swift:29` treats it as one.

The interval selector is *scope*, not *content*. On iOS 26 the natural home for scope is the
navigation bar — a `Menu` in the toolbar, or (once §3.2 lands) a title-adjacent control —
leaving the content column to start with a fact.

**Proposed change.** Move the week/month/custom control into the navigation bar as a toolbar
`Menu`, with the resolved interval label as the navigation subtitle; keep the custom-range
`DatePicker`s in a sheet. Then lead the content column with the trend tiles. This is the
change I am least certain about without seeing it, and it interacts with the navigation work
in flight — sequence it after.

### 4.3 The drift overlay card is two charts, a twelve-row legend, and a nested heading

**Defect (structural), plus taste on the remedy.** `App/Dashboard/DriftOverlayView.swift`
renders inside **one** `.contentSurface(.card)` (line 72):

1. `sectionHeading` "HR drift across runs" (line 55)
2. overlay chart, `minHeight: 220` (line 157)
3. stack summary sentence (line 86)
4. legend — up to twelve tappable rows (line 181)
5. **`sectionHeading` "Drift trend"** (line 262) — a heading at the *same weight* as the card's
   own heading, nested inside it
6. trendline chart, `minHeight: 220` (line 346)
7. exclusion notes (line 366)

That is roughly 700pt of card. More importantly, item 5 flattens the hierarchy: the type scale
has exactly one `sectionHeading`, so a subsection inside a section is rendered identically to
the section containing it. A reader scrolling past cannot tell whether "Drift trend" is a peer
of "HR drift across runs" or a child of it.

**Why it matters.** This is the chart PRD §13 calls the ticket that justifies the project. It
is currently the least navigable surface in the app.

**Proposed change.** Two parts:

- **Split the card.** "HR drift across runs" and "Drift trend" become sibling
  `.contentSurface(.card)`s. They already share their data source (`data.curves`), which is the
  invariant MAX-065 was careful to establish and which splitting does not touch.
- **Add a `subsectionHeading` token** to `Typography.swift` — `.subheadline`/`.semibold` —
  for genuine subsections. Needed independently of the split; the type scale currently jumps
  from `sectionHeading` (headline) straight to `metricLabel` (subheadline, regular) with no
  intermediate structural step.

### 4.4 The chat composer is the last thing in a long scroll

**Observation, likely already in flight.** `WorkoutDetailView.swift:66` puts
`WorkoutChatView` — including a `TextField` — as the seventh section of a `ScrollView`. FR-1.6
asks for "an entry point into the per-workout Claude thread"; this is the thread itself,
inlined, below the route map and the splits.

The keyboard consequences are the other agent's ticket and I am not duplicating them. The
*design* consequence is that FR-2's headline capability is the least discoverable thing in the
app, and that as the transcript grows it pushes the composer further from the finger.

**Proposed change.** Make it an entry point, as FR-1.6 words it: a card that shows the last
exchange (or the invitation copy) and opens a dedicated sheet or pushed view for the
conversation. That view can own the keyboard properly and can be `.glassChrome(.sheet)` — the
first honest use of the design system's sheet role.

---

## 5. Does it read as one product

Beyond §1.3 (three voices for absence) and §3.2 (three title treatments):

### 5.1 The verdict header is the only card in the app with roomier internal spacing

**Defect.** `App/Workouts/VerdictHeaderView.swift:35`:

```swift
VStack(alignment: .leading, spacing: Spacing.regular) {   // 16
```

Every other card on every screen uses `Spacing.compact` (12): `HRCurveView.swift:43`,
`CadenceBandView.swift:36`, `RouteMapView.swift:40,46`, `SplitsView.swift:34,44`,
`SummaryTilesView.swift:37`, `WorkoutChatView.swift:44`, `ScoreCalendarView.swift:44`,
`DriftOverlayView.swift:54`, `TrendTilesView.swift:34`, `TrendIntervalSelectorView.swift:19`.

**The detail screen therefore starts loose and tightens as you scroll**, by 4pt, once, at the
top. Small, but it is the first card on the app's most-visited screen and it is the sole
outlier in eleven.

**Proposed change.** `Spacing.regular` → `Spacing.compact` at `VerdictHeaderView.swift:35`.
One line. If the header genuinely wants more room, the answer is `Spacing.roomy` deliberately
and a note saying why the hero card breathes — not a silent 4pt.

### 5.2 Two different cards are both titled "Summary"

**Defect (naming).** `SummaryTilesView.swift:38` (workout detail, FR-1.5) and
`TrendTilesView.swift:36` (dashboard, FR-3.4) both render `Text("Summary")`. Different
screens, so they never co-occur — but they mean different things, and on the dashboard
"Summary" is the weakest available name for the tiles that answer FR-3's actual question.

**Proposed change.** Dashboard → "This week" / "This month" / the resolved interval label
(`TrendIntervalFormatting.label(for:)` already produces it). Detail stays "Summary".

### 5.3 The gallery and the app disagree about section headings

**Defect (minor).** `DesignSystemGallery.swift:252–256` renders headings as `.sectionHeading`
in **`Color.textSecondary`**. Every real screen renders `.sectionHeading` in
**`Color.textPrimary`**. The specimen sheet — the artefact whose whole purpose is to show a
human what the system looks like — shows a treatment the app does not use.

**Proposed change.** Align the gallery to `textPrimary`.

### 5.4 The calendar has no legend and no "today"

**Taste.** `ScoreCalendarView` renders seven weekday initials and a grid of coloured cells
carrying six distinct states across six SF Symbols, with no key. VoiceOver users get a full
sentence per cell (`ScoreCalendarFormatting.accessibilityLabel`) — sighted users get nothing.
There is also no indication of which cell is today.

I am calling this taste rather than defect because a single technical user learns six glyphs
once, and D4's whole argument is that the *colour* is the message. But "today" is cheap and I
would add it — a 1pt accent ring on the current day, now that §3.1 gives the accent a job.

---

## 6. Colour, and a recommendation on A7

### 6.1 A7 — recommendation: **ratify the existing violet `#8E7CFF` / `#5B3FE8`, and close the question**

A7 and tracker Q1 both record the accent as open, with `#8E7CFF` in place as "a defensible
default, not a decision". My recommendation is to make it the decision. Reasoning:

**It survives every collision the PRD sets up.** `ColorTokens.swift:112–121` lists three, and
the violet clears all three: it is not Robinhood's green; it is far from all three score bands
on the wheel; it is not iOS system blue.

**It measures well, in both appearances** (computed from `DesignPalette.swift`; the 6.06:1
figure is already pinned by `WCAGContrastTests`):

| Pair | Dark | Light |
|---|---|---|
| accent on `surface` | **6.06:1** | **6.32:1** |
| accent on `surfaceElevated` | 5.56:1 | 5.81:1 |
| accent on `surfaceInset` | 5.05:1 | 5.32:1 |
| `textOnSaturatedFill` **on** accent | 6.06:1 | 6.32:1 |
| Increase Contrast, on `surface` | 9.18:1 | 9.49:1 |

Every figure clears WCAG AA for normal text (4.5:1) against every surface level in both
appearances, and clears AAA (7:1) under Increase Contrast. The accent is legible as *text*,
not merely as a fill — which matters, because §3.1's fix will put it on tab labels, picker
segments and button titles, all of which are text.

Note the pleasing property that `textOnSaturatedFill` **on** the accent measures identically to
the accent on `surface`, in both appearances — the palette's near-black/near-white ink pair
happens to sit symmetrically. Reversed chips will read as well as accent text does.

**The one real argument against it** is that violet-on-near-black is a recognisable current
palette (it is Linear's register), and a discerning viewer may find it familiar rather than
distinctive. Against that: this is a single-user app that will never be distributed (A5, A8),
so "reads as someone else's brand" costs approximately nothing, and re-theming is one
declaration.

**Alternatives I measured and rejected**, for the record (dark value on `surface`):

| Candidate | Contrast | Why not |
|---|---|---|
| Cyan `#32D6E0` | 11.07:1 | Excellent contrast, but only 1.14:1 from `scoreEffective` — accent and "this run went well" would sit at near-identical luminance on the same screen |
| Teal `#2FD4C4` | 10.60:1 | Same collision, worse (1.09:1 from green) |
| Electric blue `#4D9BFF` | 6.97:1 | Reads as system blue at a glance — the exact failure mode the brief names |
| Magenta `#FF4FD8` | 6.89:1 | Clears the bands, but is louder than a colour used "sparingly" should be |
| Lime `#C6F24E` | 15.17:1 | Too close to `scoreEffective` in hue family; also very loud |

**Decision to record:** A7 is resolved as `accent = #8E7CFF` (dark) / `#5B3FE8` (light), with
`#B3A6FF` / `#3B22C4` for Increase Contrast — i.e. the committed values. The change this
implies is not to `DesignPalette.swift` but to `docs/PRD-AMENDMENTS.md` (A7 becomes resolved)
and to the tracker's Q1 row. **Owner's call — I am recommending, not deciding.**

### 6.2 Is the rest of the app too monochrome as a result?

**Partly, and not for the reason the brief anticipated.** The `ScoreBandColors` restriction is
not the cause: it reserves three colours for two surfaces, which is a good rule and produces a
disciplined calendar. The cause is §3.1 — the accent that was supposed to be the app's fourth
colour is wired to two controls at the bottom of one screen.

With `.tint(.accent)` set at the root, the app gains violet in the tab bar, the interval
picker, the date pickers, every ProgressView and every Settings control. That is *enough*.
I would not add further hues. Specifically I would **not** colour-code the summary tiles or
the cadence marker; `CadenceBandView.swift:20` and `SummaryTilesView.swift:18` both argue
explicitly for restraint there and both are right.

The one place I would spend new colour is `chartExcursion` (§2.3), because that region is a
*fact about the plan* and currently reads as background.

### 6.3 Light mode is undesigned, and one screen will make that visible

**Observation.** `ColorTokens.swift:22–26` states plainly that light values are a fallback and
"no screen has been reviewed in light appearance." That is an honest and acceptable position
for a dark-first single-user app — except that `SettingsView` offers a Light option
(`SettingsView.swift:164`) which §7.1 shows is currently inert. If §7.1 is fixed by *wiring*
the picker, light mode ships to the owner unreviewed. If it is fixed by *deleting* the
picker, it does not. See §7.1.

---

## 7. Inert controls and motion

### 7.1 `AppearancePreference` is persisted and read by nothing

**Defect.** `AppSettings.appearance` is written by `SettingsView.swift:156–166`, persisted
through `StoredAppSettings` (`Sources/MaximizeCore/Persistence/StoredPlanRecords.swift:189`),
and **never read by any view**. `preferredColorScheme` appears nowhere in `App/` except the two
`#Preview` blocks in `DesignSystemGallery.swift:261,268`.

This is precisely the defect MAX-047 was raised and closed for on `distanceUnit`, and which
the tracker articulates at line 229: *"a switch that persists a value nothing consumes is
worse than no switch, because it looks like one."* The same defect is still live one field
over.

**Proposed change** — the ticket should be phrased as a choice, exactly as MAX-047 was:

- **Wire it**, by applying `.preferredColorScheme(_:)` at `RootTabView` from the loaded
  settings — which means light mode ships and §6.3 says it has never been reviewed; or
- **Delete it** — the field, the picker, and the stored column — on the grounds that a
  dark-first single-user app whose light values are an explicit fallback should not offer a
  control that selects the un-designed appearance.

I lean delete, and I hold that lightly. Wiring it is more honest to the Settings screen; it
also silently commits the project to a light-mode review nobody has scoped.

### 7.2 Motion exists as a seam with one user

**Defect against FR-4.4, mild.** `Motion.swift` provides exactly one modifier,
`accessibleAnimation(_:value:)`, and its own header says "This file adds no animation. It is
the seam later tickets attach to." Those later tickets did not attach. The only call site in
the app is `WorkoutChatView.swift:207` — the streaming-text reveal.

FR-4.4 names three things: "chart transitions, the tab-bar collapse, streaming-text reveal."
One of three is built; the tab-bar collapse is not configured at all (§3.3).

**What is conspicuously unanimated**, in descending order of how much it would help:

- **Interval changes on the dashboard.** `DashboardView.swift:31` swaps the calendar, overlay
  and tiles wholesale when `intervalModel.state.interval` changes. Three cards' worth of
  content replaced with no transition — the hardest cut in the app, on the control the user
  touches most.
- **Load-state transitions.** Every model in the app goes `.loading → .loaded`; every view
  swaps a `ProgressView` for content instantly. Six call sites, one modifier each.
- **The score's arrival.** The verdict header's most significant moment — a run going from
  unscored to scored — happens as a hard cut.

**Proposed change.** One ticket adding `accessibleAnimation` at those three classes of site,
using a single shared duration constant added to `Motion.swift` (there is currently no
duration token; `WorkoutChatView.swift:207` hardcodes `0.15`). Chart mark transitions
specifically need `Charts`' own animation support, not a blanket `.animation`. **I cannot
assess whether any of this feels right** — this is inference from absence, not observation.

---

## 8. Accessibility as design

The accessibility groundwork here is better than most shipped apps: a four-way `Ink` per
token, an Increase Contrast path wired end to end, `UIFontMetrics` scaling on the fixed-size
metric fonts, Reduce Transparency handled once in `glassChrome`, and a real WCAG test suite.
Three gaps remain, and the first is a genuine defect.

### 8.1 Effective and marginal are indistinguishable to a colour-blind reader

**Defect, and it contradicts the file's own stated contract.**

`ScoreCalendarView.swift:19–28` claims colour is never the only channel, and gives two
independent backups: distinct glyphs, and full-sentence VoiceOver labels. **That guarantee
holds for `.missed` vs `.ineffective`, and fails for `.effective` vs `.marginal`.**

Two independent reasons:

1. **Luminance.** `scoreEffective` `#30D158` has relative luminance **0.4693**;
   `scoreMarginal` `#FF9F0A` has **0.4608**. They contrast with each other at **1.02:1**. In
   greyscale they are the same square. (Red is separated: 0.2582.)
2. **Glyph.** `ScoreCalendarFormatting.systemImageName(for:)` (line 29–44) returns
   `systemImageName(for: activityType)` for **both** `.scored(band, activityType)` and
   `.awaitingScore(activityType)`. The glyph encodes *what you did*, not *how it went*. So a
   green run day and an amber run day carry the identical glyph at the identical luminance,
   differing only in hue — and green-vs-orange is the exact axis deuteranopia and protanopia
   collapse.

The good day / not-quite day distinction is the calendar's primary output, and it is carried
by one channel that a meaningful fraction of readers cannot see.

**Proposed change.** Add a third channel that is neither hue nor activity glyph. Options, in
preference order:

1. **A corner mark per band** — a small filled dot for effective, hollow for marginal, none
   for ineffective — drawn in `textOnSaturatedFill`, which already contrasts 9.72:1 / 9.56:1
   against those fills. Cheap, and reads in greyscale.
2. **Retune the fills for luminance separation**, keeping hue: pull `scoreMarginal` dark
   toward ≈ 0.30 relative luminance. This affects the verdict header too, which is good — the
   header has the same problem.
3. Print the numeric score in the cell. Rejected: at `microLabel`/caption2 in a cell that must
   also hold a date and a glyph, it will not fit at accessibility text sizes.

The doc comments in `ScoreCalendarView.swift` and `ScoreCalendarFormatting.swift` should be
corrected in the same change — they currently assert a property the code does not have, which
is how this survived review.

### 8.2 Dynamic Type at accessibility sizes is untested and structurally at risk

**Cannot assess — flagged.** The type scale does the right thing (`UIFontMetrics` scaling,
`@ScaledMetric` on the calendar glyph box). What I cannot verify, and what the layouts suggest
is fragile:

- `VerdictHeaderView.swift:108–115` — an `HStack` holding a `metricHero` (56pt base) numeral
  *and* a `metricSecondary` "Effective"/"Not effective" label. At AX3+ the hero numeral alone
  may exceed the screen width. There is no `ViewThatFits` and no `@Environment(\.dynamicTypeSize)`
  fallback to a vertical stack anywhere in the app.
- `SummaryTilesView.swift:31–34` and `TrendTilesView.swift:28–31` — fixed two-column
  `LazyVGrid`s of `metricPrimary` (32pt base) values. At large sizes these will either wrap
  badly or truncate. `GridItem(.adaptive(minimum:))` would degrade to one column gracefully.
- `ScoreCalendarView.swift:41` — seven fixed flexible columns. A seven-day week cannot become
  fewer columns, so at AX sizes the cell content must shrink or clip; `@ScaledMetric` on the
  glyph makes the glyph grow while the cell width cannot.

**Proposed change.** One ticket: audit at AX1 / AX3 / AX5 on device, and (a) give the verdict
header a `ViewThatFits` vertical fallback, (b) move both tile grids to
`GridItem(.adaptive(minimum: 150))`. The calendar needs a decision, not a fix — probably
`.dynamicTypeSize(...DynamicTypeSize.accessibility1)` clamped on the cell content, with the
VoiceOver label carrying the full meaning as it already does.

### 8.3 Reduce Transparency is handled; Increase Contrast is only handled for colour

**Observation, not a defect.** `GlassChromeModifier` reads
`accessibilityReduceTransparency` and falls back to `chromeOpaque` — correct, and centralised.
`Ink`'s four-way resolution handles Increase Contrast for every token. What neither handles is
*non-colour* contrast: `LayoutMetrics.hairline` stays 0.5pt and chart stroke widths stay
1–1.5pt under Increase Contrast. Apple's own controls thicken under that setting.

Low priority, but if §2.1(b) lands (card borders), the border width should read
`accessibilityContrast` too.

---

## 9. Taste, declared as taste

Everything above is a defect, a measurement, or a stated inability to assess. These are
preferences. An implementer may reject them without argument.

1. **I would give the verdict header a real hero moment.** Today it is `labeledRow`,
   `labeledRow`, divider, band chip. FR-1.1's numeral is the app's one `metricHero` and it
   sits *inside* a coloured chip below two label/value rows. I would invert it: score first
   and large, rationale under it, scheduled-vs-actual as a quiet footer.
2. **I would not use a filled colour block for the band.** A large saturated rectangle
   with dark ink on it is the loudest object in the app and it appears on every workout. A
   coloured rule, or the numeral itself in the band colour, would carry the same signal with
   less weight. This is directly counter to how the calendar works, though, and there is a
   real argument that the header and calendar should look alike.
3. **`Spacing.hero` (48) is defined and never used.** Only in `padding(.top,)` on two loading
   states and in `WorkoutChatView`'s bubble `Spacer(minLength:)`. Either the app has no single
   most important element (in which case §9.1) or the token is dead.
4. **The chat user bubble's accent fill is a lot of accent.** Once `.tint` is set app-wide,
   a full-saturation bubble may read as too much. A tinted-background variant would be
   quieter. Needs to be seen.
5. **I would set `.monospacedDigit()` in one place.** It is in the `Font` tokens
   (`Typography.swift:32,37,42,64`) and *also* applied again at `SplitsView.swift:84`.
   Harmless, but it suggests the token's guarantee is not trusted.

---

## 10. Suggested tickets

Grouped so each is a coherent slice. Findings map to sections above; nothing needs
re-deriving.

| # | Ticket | Findings | Files | Tier |
|---|---|---|---|---|
| **T1** | **Plan authoring UI** — the owner cannot create a plan, so the app is permanently in its empty state | §1.1 | New; `SettingsView`, `PlanRepository.store` | **Opus** |
| **T2** | **Make the app look designed**: `.tint(.accent)` at the root; `NavigationStack` + title on Dashboard and Settings; iOS 26 `Tab` builder + `.tabBarMinimizeBehavior`; move the version string to a footer | §3.1–3.4 | `RootTabView`, `DashboardView`, `SettingsView` | Sonnet |
| **T3** | **Give surfaces depth**: widen the dark surface ramp and/or add a `surfaceBorder` token; raise `chartGridline`; raise `chartSeriesMuted` and `oldestContextOpacity`; add `chartExcursion` for time-above-cap | §2.1–2.4 | `DesignPalette.swift`, `ColorTokens.swift`, `Surfaces.swift`, `HRCurveView`, `HeartRateDriftOverlayData` | **Opus** (touches the contrast suite) |
| **T4** | **Fix the unscored state**: a third `WorkoutVerdict.scoring` case distinguishing "in flight" from "blocked, no plan"; kill the perpetual spinner | §1.2 | `WorkoutVerdict` (core), `VerdictHeaderView` | Sonnet |
| **T5** | **One absence component, one voice**: `AbsenceNote` in the design system; normalise 22 strings to one register, one font, one surface | §1.3, §1.4 | `App/DesignSystem/`, 11 views | Sonnet |
| **T6** | **Colour-blind separation of the score bands**: third non-hue channel, plus correct the doc comments that claim it already exists | §8.1 | `ScoreCalendarFormatting`, `ScoreCalendarView`, possibly `DesignPalette` | Sonnet |
| **T7** | **Dynamic Type audit at AX sizes**: `ViewThatFits` on the verdict header, adaptive tile grids, a decision on the calendar | §8.2 | `VerdictHeaderView`, `SummaryTilesView`, `TrendTilesView`, `ScoreCalendarView` | Sonnet — **needs device** |
| **T8** | **Split the drift overlay card**; add `subsectionHeading` to the type scale | §4.3 | `DriftOverlayView`, `Typography.swift` | Sonnet |
| **T9** | **`AppearancePreference`: wire it or delete it** — same shape as MAX-047 | §7.1, §6.3 | `SettingsView`, `RootTabView`, `AppSettings` | Sonnet |
| **T10** | **Motion**: interval transitions, load-state transitions, score arrival; a duration constant in `Motion.swift` | §7.2 | `Motion.swift`, `DashboardView`, 6 models' views | Sonnet — **needs device** |
| **T11** | **Small consistency fixes**: `Spacing.regular`→`compact` in the verdict header; dashboard "Summary"→interval label; gallery heading colour; score on the workout row | §5.1, §5.2, §5.3, §4.1 | 4 files | Sonnet |
| **T12** | **App icon** | §3.5 | New `.xcassets`, `project.yml` | Haiku-shaped, but see the tracker's tiering note |

**Suggested order.** T2 first — it is nearly free and changes the app's character more than
anything else here. Then T4 and T1 together (T4 is the honest interim, T1 the real fix). Then
T3. Everything else is parallelisable.

**Sequencing note.** T2 and §4.2 both touch navigation, which another agent is restructuring
now. Land that work first.

---

## Appendix — measured contrast

All ratios computed from the committed values in
`Sources/MaximizeCore/Accessibility/DesignPalette.swift` using the WCAG 2.x relative-luminance
formula. Ratios marked † are already asserted by `WCAGContrastTests`.

**Accent (`#8E7CFF` dark / `#5B3FE8` light)**

| Against | Dark | Light |
|---|---|---|
| `surface` | 6.06:1 † | 6.32:1 |
| `surfaceElevated` | 5.56:1 | 5.81:1 |
| `surfaceInset` | 5.05:1 | 5.32:1 |
| `textOnSaturatedFill` on it | 6.06:1 | 6.32:1 |
| Increase Contrast on `surface` | 9.18:1 | 9.49:1 |

**Score bands on `surface`**

| Band | Dark | Light | Relative luminance (dark) |
|---|---|---|---|
| effective | 9.72:1 | 5.40:1 | **0.4693** |
| marginal | 9.56:1 | 5.20:1 | **0.4608** |
| ineffective | 5.77:1 | 5.38:1 | 0.2582 |

effective↔marginal contrast: **1.02:1** (§8.1).

**Surface separation, dark** — Apple's system dark ramp steps at 1.23:1 and 1.22:1 for
comparison.

| Step | Ratio |
|---|---|
| `surfaceElevated` on `surface` | **1.09:1** |
| `surfaceInset` on `surfaceElevated` | **1.10:1** |
| `separator` on `surfaceElevated` | 1.30:1 |

**Chart marks on `surfaceInset`, dark**

| Mark | Ratio |
|---|---|
| `chartSeriesPrimary` | 13.42:1 |
| `chartThreshold` | 9.96:1 |
| `chartSeriesMuted`, full strength | 2.41:1 |
| `chartSeriesMuted` @ `oldestContextOpacity` 0.28 | **1.25:1** |
| above-cap shading, `chartThreshold` @ 0.20 | **1.62:1** |
| `chartGridline` | **1.15:1** |

**Text on `surfaceInset`, dark** (the most demanding surface) — all clear AA.

| Token | Ratio |
|---|---|
| `textPrimary` | 15.03:1 |
| `textSecondary` | 6.33:1 |
| `textTertiary` | 4.80:1 † |

---

## What a follow-up must not undo

Several decisions in this codebase look like omissions and are not. Recording them so a second
round does not "fix" them:

- **Score-band colours confined to the calendar and verdict header** (`ScoreBandColors.swift`,
  FR-4.3). §4.1 proposes showing the *score* in the workout list; it must stay uncoloured.
- **`Color.scoreBand(_:)` takes a band, never an `Int`** (D1). No follow-up may add
  `scoreBand(for: 84)`.
- **Cadence and the drift trendline draw no verdict** (`CadenceBandView.swift:20`,
  `DriftOverlayView.swift:292`). Both refuse to colour-code good and bad on purpose. Adding a
  slope-based tint would be a regression, not a modernisation.
- **Manual score annotations carry no band colour** (`VerdictHeaderView.swift:135`). D8 plus
  the fact that a manual score has no stored band to read.
- **Absent figures are omitted, never zeroed** (`SummaryTileData`, `TrendTileData`,
  `SplitsListData.noRoute`). §1.3 proposes unifying how absences *look*, not replacing them
  with placeholder values.
- **No glass over data** (FR-4.2, enforced by `Surfaces.swift`'s environment tripwire). None
  of the modernisation above requires translucency on a chart.

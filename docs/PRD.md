# PRD — Automated Workout Capture, Scoring & Analysis

**Owner:** Rohan
**Status:** Draft v1 (for review)
**Last updated:** 2026-08-04

> ⚠️ **This document is preserved as received and is no longer accurate in one major
> respect: there is no backend.** The app is fully on-device. §6, §8, §11 and parts of
> §5 are superseded — see **[PRD-AMENDMENTS.md](./PRD-AMENDMENTS.md)**, which wins
> wherever the two conflict. §14's open questions are also resolved there.

---

## 1. Problem statement

Run-logging is manual today: the workout happens on the Apple Watch, then a row gets hand-typed into a tracker and mentally scored against a training plan. This is friction that decays — the days you skip logging are disproportionately the days worth analyzing. Meanwhile, the data that actually matters for the current goals (HR-drift over time, time-above-cap, cadence, grade-adjusted pace) is never looked at, because Apple Fitness shows raw numbers with no relationship to the plan.

There is no consumer app that (a) knows the training plan, (b) draws the HR cap on the curve, (c) scores execution, or (d) lets you interrogate a specific run in natural language against real data. This project builds exactly that thin slice and nothing Apple already does well.

## 2. North star & success metrics

**North star:** Never hand-type a workout log row again.

| Metric | Target |
|---|---|
| Manual log entries after launch | 0 |
| Runs auto-captured & scored without user action | ≥ 95% |
| Time from "End workout" to scored & visible in app (p50) | < 2 min |
| Time from "End workout" to visible (p95) | < 15 min |
| User-initiated scoring corrections | Tracked; high rate = scoring is wrong |

The p95 target is soft: it is bounded by Watch→iPhone HealthKit sync and iOS background-delivery throttling, neither of which is under our control (confidence: high).

## 3. Goals & non-goals

### Goals
1. **Zero-touch capture** of completed Apple workouts (runs first).
2. **Full-fidelity data** — per-sample HR series, GPS route, cadence, energy — not summaries.
3. **Plan-aware scoring** — score each run against the active plan's HR cap, cadence target, weekly template, and long-run arc, reproducing the existing 0–100 effectiveness rubric and effective-day / streak tallies.
4. **Interrogable workouts** — ask Claude questions about a specific run, in context, from inside its detail view.
5. **Longitudinal analysis** — dashboard showing the plan-relevant trends (esp. cross-run HR-drift), over selectable intervals.

### Non-goals (v1)
- Live / in-workout coaching. Post-workout only.
- Manual entry, editing, or a general logging UI. The thing being killed.
- Strength-training analysis. Lifts are submaximal and don't need HR scoring; deferred, possibly permanently.
- Writing to HealthKit. Read-only.
- Multi-user. Single user; auth is a device token, nothing more.
- Diet / nutrition tracking. Weight-loss is background context, not a feature.
- Claude on the dashboard tab ("summarize my month"). Deferred to avoid scope creep.

### Full scope (v1) — everything below ships as one product; build order is an engineering concern, not part of this spec

**Backend / pipeline**
- HealthKit background-delivery ingestion (observer + anchored incremental fetch).
- Full-fidelity extraction: HR sample series, GPS route, cadence, summary, energy.
- Idempotent ingestion endpoint (dedupe on `workoutUUID`).
- Versioned `plan` model + materialized `plan_day` calendar (D1).
- Derived-metrics computation at ingestion, stored (D2): time-above-cap, HR drift, cadence, grade-adjusted pace, zone splits.
- Shared workout-context builder (D3).
- Plan-aware scorer (0–100 + effective flag + rationale) via Claude.
- Streaming contextual-chat endpoint with persisted per-workout threads (D6, D10).
- Additive manual-score annotations, non-destructive (D8).
- Tallies rollup (workout-days, effective-days, avg score, streak, current week), respecting annotations + rest-day overrides.

**iOS app**
- Detail view: plan-verdict header, HR curve with cap line + time-above-cap, cadence vs target, route map (outdoor), splits/summary tiles.
- Per-workout streaming Claude chat surface.
- Dashboard tab: interval selector, score-colored calendar with rest-day budget & missed→rest conversion (D4, D9), cross-run HR-drift overlay (D5), summary tiles.
- Settings: rest-days-per-week, display/accessibility prefs.
- Offline read of cached workouts/scores.

**Design (cross-cutting)**
- iOS 26 Liquid Glass on navigation/chrome only; flat, high-contrast, Robinhood-clean content surfaces; no glass over data; dark-first; Reduce-Transparency/Contrast honored (§7.4).

**Cross-cutting**
- Device-token auth; Anthropic key server-side only; TLS; health-data-at-rest handling.

## 4. Locked decisions (veto candidates)

These were open questions; locked here with rationale so the rest of the spec is deterministic. Any can be overturned.

- **D1 — Plan lives in the backend as versioned data, not code.** The weekly template, 16-week arc, HR cap, cadence target, and scoring rubric are stored as a `plan` record with a version. Scoring reads the plan version in effect on the workout's date. *Rationale:* the plan changes every cycle; hardcoding it means a rewrite every 16 weeks, and makes historical scores irreproducible.
- **D2 — Derived metrics computed server-side once, at ingestion, and stored.** Detail view, chat, and dashboard all read the same stored numbers. *Rationale:* on-device recomputation drifts from what Claude "sees." (confidence: high this matters)
- **D3 — One shared "workout context builder."** A single server-side function assembles {raw workout + derived metrics + resolved scheduled session + plan}. Both the scorer and the chat endpoint consume its output. *Rationale:* two notions of "what Claude knows about this run" will diverge otherwise.
- **D4 — Calendar colored by score, not by type.** Green / amber / red on the effective-day threshold (≥ 70), with a small type glyph in the corner. *Rationale:* coloring by type is what Apple does and answers a question you don't have; you care whether you executed the plan.
- **D5 — "HR over multiple workouts" = normalized drift overlay.** Multiple full HR curves plotted on a shared x-axis of *% run elapsed* (0–100%), filtered to easy/long runs, so drift *shape* is comparable across weeks. A commodity "avg HR trend line" is a cheap add but not the headline chart. *Rationale:* the overlay is the only view that makes aerobic-efficiency progress visible, and no other app can draw it.
- **D6 — Chat history persisted per workout, server-side.** Survives reinstalls; phone stays dumb. *Rationale:* revisiting "what did Claude say about the bad week-3 run" is worth the schema cost.
- **D7 — HR series stored as a JSON blob** on the workout record, not normalized rows. *Rationale:* simpler; the drift overlay reads whole curves, not ad-hoc SQL over samples. Revisit only if server-side per-sample querying becomes necessary.
- **D8 — Auto-score is canonical; manual re-scores are additive annotations, never overwrites.** The Claude-assigned score is the permanent record; a manual override is stored as a separate annotation layered on top, with both visible. *Rationale:* preserves auditability and — for free — produces the auto-vs-manual divergence signal that measures scorer quality (the correction-rate metric in §2). An overwrite would destroy exactly the telemetry we want.
- **D9 — Missed scheduled sessions surface as red days, tempered by a weekly rest-day budget.** A day with a scheduled session and no workout shows red. A user setting defines *N discretionary rest days per week*; the user can convert a red (missed) day into a neutral rest day, consuming budget, up to N. Beyond budget, days stay red. *Rationale:* legitimate unplanned rest shouldn't read as failure, but an unlimited "mark as rest" escape hatch would make the calendar meaningless. Open sub-decision noted in §14.
- **D10 — Chat responses stream.** Token-streaming in the per-workout chat is a v1 requirement, not a nice-to-have.

## 5. Users & context

Single user. iOS engineer, comfortable with the raw metrics — the UI can be dense and quantitative, not hand-holdy. Existing SwiftUI / SwiftData / CloudKit app to extend; existing FastAPI + Postgres + Redis backend to host ingestion and the Claude calls. Apple Watch as the capture device.

## 6. Architecture (high level)

```
Apple Watch ──sync──▶ iPhone (HealthKit)
                          │  HKObserverQuery + background delivery
                          ▼
                    iOS app: extract raw workout (HR series, route, summary)
                          │  POST (device token)
                          ▼
                    FastAPI backend
                       ├─ dedupe on workoutUUID (idempotent)
                       ├─ compute & store derived metrics        (D2)
                       ├─ resolve scheduled session from plan     (D1)
                       ├─ context builder → Claude → score        (D3)
                       └─ persist: workout, derived, score, tallies
                          ▲
                    iOS app reads back via API:
                       - Detail view (thin raw + plan overlay)
                       - Contextual chat (context builder → Claude)  (D3,D6)
                       - Dashboard (calendar + drift overlay)         (D4,D5)
```

The Anthropic API key never touches the device. The phone authenticates to the backend; the backend holds the model key and makes all Claude calls.

## 7. Features (user stories + functional requirements)

### 7.0 Ingestion pipeline (invisible surface)
> As the user, I finish a run on my Watch and do nothing else; the run appears scored in the app shortly after.

**FR-0.1** App registers an `HKObserverQuery` + background delivery for `HKWorkoutType` once at launch.
**FR-0.2** On wake, fetch new workouts via anchored query (persisted anchor → incremental, no duplicates across relaunches).
**FR-0.3** For each workout extract: type, start/end, duration, distance, active energy, full HR sample series (time-range predicate), GPS route (absent for indoor).
**FR-0.4** Upload via a background `URLSession` so the POST survives app suspension.
**FR-0.5** Backend is idempotent on `workoutUUID`; duplicate deliveries are no-ops.
**FR-0.6** Indoor/treadmill runs (no route) are first-class — HR curve is the point, not GPS.

### 7.1 Workout detail view
> As the user, I open a run and see everything about it, with my plan drawn on top.

**FR-1.1** **Plan verdict header:** scheduled session (from plan), actual type, effectiveness score (0–100), effective/not, one-line rationale.
**FR-1.2** **HR curve** with the HR cap (currently 150 bpm) drawn as a horizontal line; time-above-cap shaded.
**FR-1.3** **Cadence** plotted against the target band (currently 165–170); current-run average called out.
**FR-1.4** **Route map** — outdoor runs only; omitted cleanly for treadmill.
**FR-1.5** **Splits** and summary tiles (distance, duration, avg/max HR, energy, drift %, grade-adjusted pace). Thin — displayed because cheap, not lovingly built.
**FR-1.6** Entry point into the per-workout Claude thread (§7.2).

### 7.2 Contextual chat
> As the user, from a run's detail view I ask Claude why my HR drifted at mile 3 and get an answer grounded in that run's actual data.

**FR-2.1** Per-workout thread, seeded with the context builder output (D3): raw + derived + scheduled session + plan + the score already assigned.
**FR-2.2** Messages routed through the backend; key stays off-device.
**FR-2.3** Thread persisted server-side (D6); reopening the workout restores history.
**FR-2.4** Responses stream token-by-token (D10) — required, not deferred.

### 7.3 Overview / dashboard tab
> As the user, I pick a time interval and see whether I'm executing the plan and whether my aerobic efficiency is improving.

**FR-3.1** Interval selector: this week / this month / custom range.
**FR-3.2** **Color-labeled calendar** (D4, D9): each day colored by score band, type glyph in corner, planned rest days marked, missed scheduled sessions shown red. A settings-defined *rest-day budget (N/week)* lets the user convert a red missed day into a neutral rest day, up to N; over-budget days stay red. Converted days are excluded from streak/effective-day penalties.
**FR-3.3** **Cross-run HR-drift overlay** (D5): easy/long-run HR curves on a % -elapsed x-axis; selectable which runs are stacked; ideally a trendline showing drift flattening over the interval.
**FR-3.4** Summary tiles: weekly mileage vs arc target, effective-day count, current streak, avg score — the existing tallies, computed from stored scores.
**FR-3.5** No Claude on this tab in v1 (non-goal).

### 7.4 Design & UX (cross-cutting)
> As the user, the app should feel like a polished iOS 26 app — Liquid Glass where the system expects it — with the data clarity of Robinhood.

**The two references are in tension, and the resolution is not "use both everywhere."** Liquid Glass is a translucent, refractive *navigation-layer* material; Apple's own guidance is that it floats above content and is **never applied to the content itself** — lists, charts, media stay primary while controls recede. Robinhood's aesthetic is the opposite surface: flat, high-contrast, generous negative space, oversized legible numerals, restrained palette with a single vivid accent, chart-forward. These don't fight once you assign them to different layers.

**FR-4.1 — Liquid Glass on chrome only.** Tab bar, navigation bars, toolbars, sheets, and floating controls adopt Liquid Glass (largely free by building against the iOS 26 SDK / Xcode 26). Scroll-collapsing tab bar behavior is expected.
**FR-4.2 — Content stays flat and Robinhood-clean.** HR curves, the drift overlay, the calendar, and summary tiles are rendered on opaque, high-contrast surfaces. **No glass/translucency over data** — refraction and blur destroy the legibility of fine chart lines and the cap threshold, which is the whole point of those views. (Apple's HIG and independent usability critiques both flag translucency-over-content as a legibility failure — confidence: high.)
**FR-4.3 — Visual language:** dark-first; one accent color used sparingly for the "on-plan / effective" state; the score bands (green/amber/red) are the only other saturated color and appear only in the calendar and verdict header; typography does the hierarchy work (large numerals for the metrics that matter, quiet labels).
**FR-4.4 — Motion:** purposeful and physical, not decorative — chart transitions, the tab-bar collapse, streaming-text reveal. Nothing that competes with reading the data.
**FR-4.5 — Accessibility:** honor Reduce Transparency / Increase Contrast (iOS 26 added user controls specifically because early Liquid Glass over-transparency hurt readability); the app must degrade gracefully to solid chrome.

## 8. Data model (Postgres, indicative)

- **plan** — `id, version, effective_from, weekly_template (json), longrun_arc (json), hr_cap, cadence_target_lo, cadence_target_hi, rubric (json), goals (json)`.
- **plan_day** — resolved calendar: `date, plan_version, scheduled_session, scheduled_distance` (materialized so scoring is deterministic).
- **workout** — `uuid (PK), activity_type, start, end, duration_s, distance_m, energy_kcal, has_route, source, ingested_at`.
- **hr_series** — `workout_uuid, samples (json blob: [{t, bpm}])` (D7 — blob, not normalized rows).
- **route** — `workout_uuid, points (json: [{t, lat, lon, alt, speed}])`.
- **derived_metrics** — `workout_uuid, avg_hr, max_hr, time_above_cap_s, drift_pct, avg_cadence, grade_adjusted_pace, zone_splits (json)`.
- **score** — `workout_uuid, plan_version, scheduled_session, actual_type, score, is_effective, rationale, scored_at`. The canonical auto-score; immutable (D8).
- **score_annotation** — `id, workout_uuid, manual_score, note, created_at`. Additive manual override layered on top of `score`; never mutates it (D8). Divergence between the two feeds the correction-rate metric.
- **chat_thread** — `id, workout_uuid, messages (json: [{role, content, ts}])`.
- **rest_day_override** — `date, converted_from_missed (bool), created_at`. Records missed→rest conversions against the weekly budget (D9).
- **settings** — `rest_days_per_week (int)`, plus display/accessibility prefs.

Tallies (workout-days, effective-days, avg-score, streak, current-week) are computed on read from `score` + `score_annotation` + `plan_day` + `rest_day_override`; cache in Redis if needed. Where a manual annotation exists, tallies use it; the auto-score remains recorded.

## 9. Derived metric definitions

- **Time above cap** — seconds where HR > `hr_cap`. Primary easy-run discipline metric.
- **HR drift (aerobic decoupling)** — `(avg HR 2nd half / avg HR 1st half) − 1`, at controlled/steady effort. Most meaningful on easy and long runs; near-meaningless on interval/hard runs, so surfaced conditionally.
- **Average cadence** — steps/min over the run; compared to target band.
- **Grade-adjusted pace** — pace corrected for route grade (outdoor only), so HR-vs-effort is interpretable on hilly runs.
- **HR-zone splits** — time in each zone relative to the plan's cap-anchored zones.

## 10. Scoring logic

The scorer consumes the context builder output and applies the plan's rubric (stored, versioned — D1). It must:
1. Resolve the **scheduled session** for the workout's date from `plan_day`.
2. Classify the **actual** workout (easy / hard / long / other) from type + HR profile.
3. Score 0–100 per the rubric (e.g. easy run: HR ≤ cap with low drift → 90–100; under cap but late drift → 75–89; avg 151–158 → 55–74; avg ≥ 159 or hard-instead → 20–45; skipped → 0–15).
4. Mark **effective** if score ≥ 70.
5. Emit a one-line rationale for the detail-view header.

The auto-score is written immutably. If the user disagrees, they attach a `score_annotation` (D8) — an additive manual score that the app uses for tallies while the original auto-score stays on record. The gap between the two *is* the scorer-quality signal; never collapse them.

The rubric is data, not code: changing thresholds is a new `plan` version, not a deploy.

## 11. Non-functional requirements

- **Latency:** scoring completes within seconds of ingestion (single Claude call); chat interactive (< few seconds to first token if streaming).
- **Reliability:** at-least-once delivery from HealthKit; idempotent ingestion; no duplicate scores.
- **Offline:** app shows cached workouts and past scores offline; chat and fresh scoring require network.
- **Security/privacy:** Anthropic key server-side only; device→backend over TLS with a device token; health data is PII — encrypt at rest, minimal retention discipline.
- **Cost:** one Claude call per workout for scoring + on-demand for chat; negligible at single-user volume.

## 12. Out of scope / future (v2+)

- Strength-training scoring and volume tracking.
- "Summarize my week/month" Claude action on the dashboard.
- Nutrition/weight integration.
- Anomaly flags (e.g. HR spikes worth a health look) — deliberately deferred; not a diagnostic tool.

## 13. Risks & sharpest tensions

- **iOS timing is not controllable.** "Immediately after finishing" is really "after Watch sync + whatever background-delivery cadence iOS grants." The p95 target may not hold on some days. (confidence: high)
- **Background-delivery entitlement.** `com.apple.developer.healthkit.background-delivery` must be present or the wake silently never happens. (confidence: moderate-high on exact key — verify against Apple docs)
- **Reimplementing Apple.** Every hour spent polishing the route map or splits (things Apple does better) is an hour not spent on the overlay/chat/scoring that justify the project. Scope discipline is the top execution risk, not any technical unknown.
- **Scoring correctness.** If auto-scores routinely disagree with your own judgment, the loop loses trust fast. Track correction rate as an early signal; be ready to iterate the rubric.
- **Plan/actual classification ambiguity.** A "hard run then legs" Thursday vs an "easy run" Tuesday must be disambiguated from data + calendar; misclassification poisons the score. The `plan_day` calendar is load-bearing.

## 14. Open questions

The four prior questions are resolved as D7–D10. One sub-decision remains, plus one new one from the design direction:

1. **Rest-day conversion: manual or auto?** D9 locks a weekly rest-day *budget*, but not whether missed days convert to rest **manually** (user taps a red day → rest, capped at N) or **automatically** (the system spends the budget on the least-costly missed days each week). Manual gives control and intent; auto is zero-touch and consistent with the north star. Leaning manual, since a converted rest day is a judgment ("that was a real rest day, not a fail") the system can't reliably infer — but it's the one place the north star and honesty about your week pull apart. Your call.
2. **Accent color.** The palette reserves one vivid accent for the on-plan/effective state (§7.4). Robinhood's is its green; you'll want your own so this doesn't read as a Robinhood clone. Not blocking — a token to set later.

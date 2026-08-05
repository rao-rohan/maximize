# Building Maximize onto your iPhone

CI never produces an installable build, deliberately — signing a device build needs
credentials, and this repo holds none. This is the local path instead.

It takes about five minutes the first time and one command after that.

> ## ⛔ Before you give this build to anybody else
>
> **This app may be installed on your own device. It must not be distributed** — not to
> TestFlight, not to the App Store, not sideloaded onto a friend's phone — **until the
> Anthropic API key is moved off the device and behind a server.**
>
> The key lives in Keychain on the phone ([A5](./PRD-AMENDMENTS.md#a5--the-anthropic-api-key-lives-in-keychain-on-device)),
> which supersedes PRD §6's "the key never touches the device". That was accepted on
> exactly one condition: the app is single-user and is never shipped. Anyone holding the
> binary can extract the key from it and spend against the account it belongs to. **This
> is a release blocker, not a follow-up**, and it is recorded as R3 in
> [`PROJECT_TRACKER.md`](../PROJECT_TRACKER.md).
>
> A second, quieter one travels with it: CloudKit backup is deferred
> ([A8](./PRD-AMENDMENTS.md#a8--cloudkit-backup-is-deferred-d6-is-downgraded-to-on-device-durability)),
> so history does not survive a reinstall and a second device starts empty. That is a
> tolerable trade for one person who knows it. It is not something to ship to someone
> who does not.
>
> This notice is here rather than only in `CLAUDE.md` and `docs/PRD-AMENDMENTS.md`
> because this is the file someone reaches for when they set a real bundle identifier
> and start paying Apple $99 — which is the last moment before the tripwire matters and
> the first moment anybody reads about signing at all. Added by MAX-072.

## What you need

- **A Mac with Xcode 26.** The app targets iOS 26 for Liquid Glass (PRD §7.4), so
  earlier Xcode cannot build it.
- **An iPhone running iOS 26.** The deployment target is a hard floor, not a warning —
  an iPhone on iOS 25 will not appear as a run destination.
- **XcodeGen**: `brew install xcodegen`.
- **An Apple ID.** A free one may be enough — see [the caveat](#the-one-thing-that-might-cost-money).

## First-time setup

```sh
cp Support/Signing.local.xcconfig.example Support/Signing.local.xcconfig
```

Open that file and change two values:

- **`PRODUCT_BUNDLE_IDENTIFIER`** — reverse-DNS on something you control, e.g.
  `com.rohanrao.maximize`. It must be globally unique. Do not keep `com.example.*`;
  that prefix is reserved for documentation and Xcode may refuse to register it.
- **`DEVELOPMENT_TEAM`** — your 10-character Team ID. With a paid account it is at
  developer.apple.com → Membership. With a free one, Xcode → Settings → Accounts →
  your Apple ID → the team row.

That file is gitignored. Nothing personal to you ever reaches a commit.

## Every time

```sh
xcodegen generate
open Maximize.xcodeproj
```

Plug in the phone, pick it as the run destination, press ⌘R. On the first install the
phone will refuse to launch the app until you trust the certificate: Settings →
General → VPN & Device Management → your Apple ID → Trust.

You only need `xcodegen generate` again after `project.yml` changes or after files are
added or removed — the `.xcodeproj` is generated and gitignored, so it will not be
waiting for you on a fresh clone.

## The one thing that might cost money

The app declares `com.apple.developer.healthkit.background-delivery` (MAX-030), which
is what lets iOS wake it when a workout finishes. That entitlement has to be present in
the provisioning profile Xcode issues.

**Whether a *free* Apple ID can issue a profile carrying that entitlement is genuinely
unclear**, and rather than assert either way, the honest answer is: try it. If the build
signs and installs, you are done. If Xcode reports that the profile does not include the
entitlement, that is the answer, and a paid Apple Developer Program membership
($99/year) is required.

Two things to know if you are on a free account regardless:

- **Apps expire after 7 days.** You will re-run ⌘R weekly. Paid accounts get a year.
- You are limited in how many distinct app IDs you can register per week.

## What actually works on device vs. simulator

This is why the local build matters rather than a CI simulator artifact.

| | Simulator | Device |
|---|---|---|
| UI, layout, dark mode, Dynamic Type | yes | yes |
| Reading real workouts from Health | no | yes |
| **HealthKit background delivery** | **no — unsupported by Apple** | yes |
| Watch → iPhone sync timing | no | yes |
| Whether zero-touch capture works at all | no | **yes** |
| **CloudKit sync between two devices** | n/a — deferred, see A8 | n/a — deferred, see A8 |

Background delivery not working in the Simulator is Apple's documented behaviour, not a
limitation of this project's setup. It is the single reason a simulator build cannot
verify the product's central claim.

## Verifying CloudKit sync (MAX-021) — deferred, nothing to verify today

**Skip this section.** [A8](./PRD-AMENDMENTS.md#a8--cloudkit-backup-is-deferred-d6-is-downgraded-to-on-device-durability)
removed the iCloud entitlements from `project.yml` and flipped `makeOnDisk`'s
`cloudKitDatabase` default to `.none`, so the store is local-only: no workout, curve,
route, score or chat message leaves the phone through iCloud. Nothing below will
happen, and step 3 or 4 appearing to fail is the expected result rather than a bug to
chase. The steps are kept because re-enabling mirroring is a two-line change and this
is the checklist for the day it happens. Flagged at MAX-072, which found this section
still describing sync as live.

Same story as background delivery: nothing in CI touches this, and there is no
simulator substitute — CloudKit sync needs two real endpoints signed into the same
iCloud account, and the Simulator's iCloud support is unreliable enough that it is not
trustworthy for this even as a first check. This needs a human on real hardware.

**What to check:**

1. **Both devices signed into the same Apple ID**, with iCloud Drive/iCloud enabled in
   Settings (Settings → [your name] → check the account matches on both).
2. Install on device A (`⌘R`). Let a workout ingest (or wait for the next real run —
   ingestion itself is not this ticket's concern, only whether what lands in the store
   reaches device B).
3. Install on device B, signed into the *same* Apple ID. Open the app. Within a few
   minutes to an hour (CloudKit sync is opportunistic, not instant — see `project.yml`'s
   note on the omitted push-notification background mode), the workout from device A
   should appear.
4. **Delete-and-reinstall check (the actual D6 requirement):** delete the app from
   device A, reinstall, sign into the same Apple ID, open it. Workout history should
   reappear without a fresh HealthKit ingest — this is the "survives reinstall" half of
   D6, and it is the one CI can least stand in for.
5. **First-sync duplicate check:** if a workout is recorded on both devices before
   either has synced (e.g. both were offline, or the app was just installed on both),
   confirm it appears once, not twice, on each device after sync catches up. Two
   `WorkoutRecord`s for the same `workoutUUID` can legitimately exist transiently —
   `MaximizeStore` resolves to the oldest by `ingestedAt` — but the UI should not show a
   duplicate workout once both devices have synced.
6. **What NOT to see:** on a device that has never had HealthKit access granted or has
   never ingested a given workout locally, that workout's *HealthKit anchor position*
   should not silently skip past workouts it never fetched. This is R12 in
   `PROJECT_TRACKER.md` and is why the anchor file is deliberately excluded from
   CloudKit — there's no positive way to observe this from the UI, only its absence:
   watch for any workout that HealthKit has but the app never shows on a device where
   ingestion should still be running.

If step 3 or 4 does not happen within a reasonable window, check Settings → [your
name] → iCloud → that this app (once it has a real bundle ID and provisioning, not the
placeholder) is listed and not disabled, and that the CloudKit container was actually
provisioned — the first signed run with the iCloud capability is normally what creates
it; the CloudKit Dashboard (icloud.developer.apple.com) can confirm the container and
schema exist under your team.

## What to expect on a real run

The capture-to-score loop is complete (MAX-033). Finish a run on the Watch and, without
opening the app, it should be captured, measured, classified, scored and stored.

**Anything recorded while the pipeline was pinned drains on the first wake** after you
install a build containing MAX-033 — so the first run may bring several older workouts
with it. That is the anchor doing its job, not a duplicate-ingestion bug.

**With no API key stored, workouts still land.** They arrive complete — measured,
classified, stored — just unscored, and the detail view renders that as a first-class
state rather than an error. Scoring fills in later once a key exists. This is the app's
ordinary condition on the day it is installed, so it is worth confirming deliberately:
install, record a run, and check it appears *before* you enter a key.

Worth watching in Console.app (subsystem `Maximize`, category `ingestion`) on the first
device run — the pipeline reports its own state there, deliberately without any health
data in the messages:

- `Gave up on a workout at …` is R11's escape firing. It should be rare, and it is the
  one place the pipeline abandons a workout permanently.
- `Workout stored but unscored (…)` is the expected line before a key is entered.
- `Ingestion pass stopped after N batches` means a wake ran out of budget; the rest
  resumes next pass.

## If it will not build

- **"Signing for 'Maximize' requires a development team"** — `Support/Signing.local.xcconfig`
  is missing or `DEVELOPMENT_TEAM` is still the placeholder. It must be the 10-character
  ID, not your email.
- **"Provisioning profile doesn't include the com.apple.developer.healthkit.background-delivery
  entitlement"** — see [above](#the-one-thing-that-might-cost-money). This is the paid-account question answering itself.
- **The phone is not offered as a destination** — it is on iOS 25 or older, or it is
  locked. Unlock it and trust the Mac.
- **"Unable to install ... The maximum number of apps for free development profiles has
  been reached"** — free-account limit. Delete an older sideloaded app from the phone.
- **Changes to `project.yml` seem ignored** — you did not re-run `xcodegen generate`.

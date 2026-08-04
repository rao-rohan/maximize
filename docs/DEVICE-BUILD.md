# Building Maximize onto your iPhone

CI never produces an installable build, deliberately — signing a device build needs
credentials, and this repo holds none. This is the local path instead.

It takes about five minutes the first time and one command after that.

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

Background delivery not working in the Simulator is Apple's documented behaviour, not a
limitation of this project's setup. It is the single reason a simulator build cannot
verify the product's central claim.

## Expected behaviour right now

**Until MAX-033 lands, ingestion deliberately fails.** MAX-031's placeholder sink
throws, which holds the HealthKit anchor in place so no workout is skipped in the
meantime. On device today the correct symptom is:

- one logged ingestion failure per background wake, and
- the anchor never advancing.

That is the pipeline working as designed, not a bug. Everything captured meanwhile
drains on the first wake after MAX-033 ships.

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

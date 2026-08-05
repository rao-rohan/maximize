# Security review — MAX-072

**Date:** 2026-08-05 · **Reviewer:** agent, working ticket MAX-072 · **Tree reviewed:**
`origin/main` at `5fd2383` (MAX-049)

Audited against the standard in [`CLAUDE.md`](../CLAUDE.md) — "Health and privacy" —
together with PRD §6 and §11, and amendments
[A5](./PRD-AMENDMENTS.md#a5--the-anthropic-api-key-lives-in-keychain-on-device) and
[A8](./PRD-AMENDMENTS.md#a8--cloudkit-backup-is-deferred-d6-is-downgraded-to-on-device-durability).

**Headline: no high or critical findings. One medium, three low, three informational.**
The medium is a process gap, not a code defect — the distribution tripwire was not
recorded anywhere a person about to ship would actually look. That is fixed here. The
key handling, the prompt-minimisation boundary and the logging discipline all hold up;
they are, genuinely, better than the average codebase this reviewer sees, and most of
this document is a record of checks that passed.

**This review was done by reading code. There is no Swift toolchain in this container —
`swift build` and `swift test` were not run, and cannot be. CI is the first real
compile.**

---

## 1. Scope audited

| Area | Files |
|---|---|
| Keychain and key handling | `App/KeychainAnthropicAPIKeyStore.swift`, `Sources/MaximizeCore/AnthropicAPIKey.swift`, `Sources/MaximizeCore/AnthropicAPIKeyStoring.swift`, `App/SettingsView.swift`, `App/SettingsModel.swift` |
| Key on the wire | `App/AnthropicScoringModelClient.swift`, `App/AnthropicStreamingChatClient.swift` |
| Data at rest | `App/Persistence/MaximizeModelContainer.swift`, `MaximizeSchema.swift`, `MaximizeStore.swift`, `PersistenceComposition.swift`, `App/FileWorkoutQueryAnchorStore.swift` |
| Prompt minimisation (D3) | `Sources/MaximizeCore/Context/**`, `Sources/MaximizeCore/Chat/ChatInstruction.swift`, `Sources/MaximizeCore/Scoring/WorkoutScorer.swift` |
| Logging | every `.swift` file under `App/` and `Sources/` (grep for `Logger`, `os_log`, `OSLog`, `print`, `NSLog`, `debugPrint`, `dump`) |
| Distribution tripwire | `CLAUDE.md`, `docs/PRD-AMENDMENTS.md`, `PROJECT_TRACKER.md`, `docs/DEVICE-BUILD.md`, `README.md` |
| Secrets in the repo | working tree **and all 216 commits of history**, plus `.gitignore`, `project.yml`, `Support/*`, test fixtures |

### Explicitly not in scope

- **The chat UI (MAX-051) was not part of the audited tree.** There is no `App/Chat`
  directory at `5fd2383`; `AnthropicStreamingChatClient` exists but has no caller in the
  app layer. MAX-051 changes what enters a chat prompt and lands after this review
  started. It runs its own `/security-review`, and **that** is the review of the chat
  prompt path — not this one.
- MAX-046 (splits) and MAX-047 (distance unit) were also in flight and are not covered.
- Cryptographic review of iOS Keychain or Data Protection themselves. Both are treated
  as trusted primitives; what is reviewed is how this app configures them.
- Anything requiring execution: see §5.

---

## 2. Findings by severity

### MEDIUM

#### M1 — The A5 distribution tripwire was not discoverable by someone about to ship
**Reachable today.** `docs/DEVICE-BUILD.md` (before this PR)

A5 permits the Anthropic API key on-device on exactly one condition — the app is
single-user and never distributed — and makes moving it behind a server a release
blocker. That tripwire was recorded in three places: `CLAUDE.md`'s "Health and privacy"
section, `docs/PRD-AMENDMENTS.md` A5, and `PROJECT_TRACKER.md` R3.

All three are documents you read when you are *contributing*. None is the document you
read when you are *shipping*. `docs/DEVICE-BUILD.md` is that document — it is where
someone goes to set a real bundle identifier, get a Team ID, and decide whether to pay
Apple $99 — and it said nothing about the tripwire at all. It is possible to follow that
file end to end, arrive at a signed build with a real bundle ID, and never encounter the
constraint that build is conditioned on.

`README.md` is one line (`# maximize`), so it catches nobody either. **The repository
went public today**, which widens who might pick this up and follow the build
instructions without having read `CLAUDE.md` first.

This is a finding about a control that exists but cannot be found, which is a real class
of failure and not a theoretical one. The severity is medium rather than high only
because nobody has shipped and the current owner wrote the constraint.

**Fixed in this PR** — see §3.

---

### LOW

#### L1 — An arbitrary `Error` was logged at `privacy: .public`
**Reachable today.** `App/HealthKitWorkoutObserver.swift:141` (pre-fix)

```swift
let reason = error.map { String(describing: $0) } ?? "no error reported"
ingestionLog.error("HealthKit background delivery NOT enabled: \(reason, privacy: .public)")
```

`App/IngestionComposition.swift:128-143` sets the house rule and states it at length:
payload-free diagnostic enums may be `.public`; an *arbitrary* `Error` goes `.private`,
because an `NSError`'s `userInfo` is not something the call site can bound. This was the
one place in the app layer that broke the rule.

Two things keep it at low rather than medium. The error comes from
`HKHealthStore.enableBackgroundDelivery`, so realistically it is an `HKError` carrying a
code and a localized string — **the PII exposure is theoretical, not demonstrated.** But
the *reachability* is not theoretical: this branch fires on every launch where the
background-delivery entitlement is missing, which is precisely tracker R5's scenario, and
`.public` means the string is written into the unified log store and travels in a
sysdiagnose — a wider audience than a debugger.

"Unlikely to contain PII" is not the bar the rest of this codebase holds itself to.

**Fixed in this PR** — see §3.

#### L2 — `MaximizeModelContainer`'s doc comment claimed CloudKit mirroring was on
**Documentation defect, reachable by any reader.** `App/Persistence/MaximizeModelContainer.swift:50-59`

The `## CloudKit mirroring (MAX-021, D6)` block opened with "Defaults to `.automatic`"
and went on to describe, in the present tense, health data being written to the user's
private CloudKit database. The actual parameter default has been `.none` since A8, and
the parameter's own documentation forty lines below said so — so the file contradicted
itself.

The consequence is specific: someone auditing "does health data leave this device"
reads the prose block first (it is the section header) and gets the wrong answer. In a
file whose entire purpose is data-at-rest posture, that matters more than an ordinary
stale comment.

**Fixed in this PR** — see §3.

#### L3 — `applyFileProtection` names three files; the store writes more than three
**Theoretical — the directory attribute covers the gap.** `App/Persistence/MaximizeModelContainer.swift:174-184`

`applyFileProtection(around:)` explicitly sets `.completeUntilFirstUserAuthentication`
on `Maximize.store`, `-wal` and `-shm`, and its comment presents that as the complete
set. It is not. Three models use `@Attribute(.externalStorage)` —
`HeartRateSeriesRecord.samplesJSON`, `RouteRecord.pointsJSON`,
`ChatThreadRecord.messagesJSON` (`MaximizeSchema.swift:166, 188, 338`) — and Core Data
writes those bytes into its own support directory beside the store rather than into the
SQLite row. Between them that is the heart-rate curve, the GPS track and the chat
transcript: the most re-identifying content in the store.

**Why this is theoretical and not a real exposure.** `prepareStoreURL()` creates the
`Store` directory with `attributes: [.protectionKey: fileProtection]`
(`MaximizeModelContainer.swift:158-162`), and iOS applies a directory's protection class
as the default for files created inside it. The external-data files are created inside
it. Separately, `.completeUntilFirstUserAuthentication` is already iOS's default class
for app files, so both mechanisms land on the same value. The bytes are protected.

The defect is that the code's own reasoning was incomplete — it described the belt as
belt-and-braces when the belt is doing all the work for a third of the sensitive data.
A future edit that removed the directory attribute as redundant would have silently
uncovered the blobs, and the comment would not have warned anyone.

**Comment fixed in this PR; the code is deliberately unchanged** — see §3 and §4/R1.

---

### INFORMATIONAL

#### I1 — `SettingsView.enteredKey` holds typed key text in `@State` for the view's lifetime
`App/SettingsView.swift:39, 249-264`

The `SecureField`'s backing string is cleared on successful save (line 253) and on a
non-`emptyKey` failure (line 262). It is *not* cleared if the user types a key and then
navigates away without tapping Save — SwiftUI keeps `@State` alive as long as the view's
identity persists, so the plaintext sits in the process heap.

Not raised as a finding: this is unavoidable for any text field (the string exists in
`SecureField`'s own storage regardless), the process is the same one that legitimately
holds the key to put it in a request header, and there is no attacker in the threat
model who has the process heap but not the Keychain item. Recorded because the file's
doc comment claims the key "never round-trips back onto screen once saved", which is
true and is a different claim from "is not held in memory".

#### I2 — `AppSettingsRecord` mixes user-scoped and device-scoped fields
`App/Persistence/MaximizeSchema.swift:436`, documented at `MaximizeModelContainer.swift:96-113`

`reducesTransparency` / `increasesContrast` / `reducesMotion` are this device's OS
accessibility state, stored alongside genuine user preferences. Under CloudKit mirroring
one device could overwrite another's. **Inert today on two counts:** mirroring is off
(A8), and MAX-064 explicitly declined to seed these fields from `UIAccessibility`
(`SettingsView.swift:215-236`), so nothing populates them. The existing comment names
MAX-064 as the ticket that would resolve it; MAX-064 has since landed and decided not to.
Not a security issue in any configuration reachable today. Recorded so the stale
ownership pointer does not mislead.

#### I3 — `FileWorkoutQueryAnchorStore` creates its directory without a protection attribute
`App/FileWorkoutQueryAnchorStore.swift:87`

Unlike `prepareStoreURL()`, `anchorFileURL()` calls `createDirectory` with no
`attributes:`. The anchor file itself is written with an explicit
`.completeFileProtectionUntilFirstUserAuthentication` (line 69), so the data is
protected, and the anchor is an opaque HealthKit cursor with no workout content in it.
No action needed; noted only because the two file stores in this app take visibly
different approaches to the same problem.

---

## 3. What was fixed in this PR

Three files, all small and local. No architectural change, no change to what any stored
record contains, no behaviour change outside one log statement.

| Finding | File | Change |
|---|---|---|
| M1 | `docs/DEVICE-BUILD.md` | Added a blocking notice at the top of the file — the first thing anyone setting up a signed build reads — stating that the app must not be distributed until the key moves behind a server, with links to A5 and R3. Also flagged the A8 CloudKit consequence in the same block, and corrected two places in the same file that still described CloudKit sync as live behaviour to verify (the capability table row and the "Verifying CloudKit sync" section). |
| L1 | `App/HealthKitWorkoutObserver.swift` | Split the failed-`enableBackgroundDelivery` log into two statements: `NSError.domain` + `code` at `.public` (payload-free, and the part someone diagnosing R5 actually reads, so it still survives into a sysdiagnose), and the full `Error` at `.private`. This now matches the rule `IngestionComposition` states. |
| L2 | `App/Persistence/MaximizeModelContainer.swift` | Rewrote the `## CloudKit mirroring` doc block to lead with the current state (`.none`, nothing leaves the device) and re-cast the CloudKit exposure analysis into the conditional — it describes what re-enabling *would* do, and is kept for that reason. |
| L3 | `App/Persistence/MaximizeModelContainer.swift` | Corrected `applyFileProtection`'s doc comment to name the three `.externalStorage` blobs it does not cover and to state plainly that the directory attribute — not this function — is what protects them. |

Nothing in the diff is a code path change other than L1's logging privacy level.

---

## 4. Reported for follow-up, not fixed

**R1 — Consider extending `applyFileProtection` over the external-storage directory.**
(From L3.) Belt-and-braces parity would mean walking Core Data's support directory and
setting the attribute there too. Deliberately not done here: it is a behaviour change on
a code path that has never executed anywhere in this pipeline (tracker R2), the exact
directory name is a Core Data implementation detail this code would then depend on, and
the protection is already correct via inheritance. If it is done, it belongs in a ticket
that can be verified on a device with `ls -l@` / a data-protection check — see §5.

**R2 — Give `README.md` content, including the distribution constraint.** The repo is
public as of today and its README is one line. M1 is fixed for the person following the
build instructions; the person who lands on the repo front page still sees nothing.
Outside this ticket's scope (it is a docs ticket, not a security fix), but it is now the
weakest remaining link in the tripwire's discoverability.

**R3 — `docs/PRD-AMENDMENTS.md` A8's "why the schema does not change" section and
`MaximizeModelContainer`'s CloudKit block now overlap substantially.** Not a defect;
noted because the next person to touch either should keep them consistent, and this
review has already had to correct one of them for drift.

**R4 — The chat prompt path needs its own review.** Stated again here so it is not lost:
MAX-051 introduces the first caller of `AnthropicStreamingChatClient` and therefore the
first code that decides what a chat prompt contains. Per `CLAUDE.md` that PR requires a
`/security-review`, and this document does not stand in for it.

---

## 5. Checks that passed

Recorded because a review that only lists problems tells you nothing about coverage.

**Keychain (`KeychainAnthropicAPIKeyStore.swift`).** Accessibility is
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly` (line 57) — the tightest class compatible
with a foreground-only key read, and `ThisDeviceOnly` excludes the item from iCloud
Keychain sync and from device-to-device restore, which is what A5's single-device
bounding actually requires. `kSecAttrSynchronizable = false` is set redundantly and
explicitly (line 62). The update-then-add ordering means a routine key replacement does
not reset the accessibility attribute. `OSStatus` values are mapped through
`SecCopyErrorMessageString` (line 113-118), which is system-supplied text that never had
access to the key. **No defects found.**

**Key material handling.** `AnthropicAPIKey` (`Sources/MaximizeCore/AnthropicAPIKey.swift`)
wraps the raw string in a private stored property and overrides *both*
`CustomStringConvertible` and `CustomDebugStringConvertible` to `<redacted>` — which is
the difference between a `print("\(key)")` leaking and not leaking, and
`AnthropicAPIKeyTests` asserts the interpolated form specifically, not just the
`.description` accessor. `revealed()` is the single exit, and it has exactly two call
sites in the app (`AnthropicScoringModelClient.swift:130`,
`AnthropicStreamingChatClient.swift:230`), both of which pass the result directly into an
`x-api-key` header with no intermediate binding. `AnthropicAPIKeyError`'s cases carry an
adapter-supplied `String` and structurally cannot hold key material. **No defects found.**

**The Settings screen cannot display a stored key.** `SettingsView` calls
`keyStore.retrieve()` in exactly one place and compares it against `nil`
(line 242) — the returned `AnthropicAPIKey` is never bound, rendered, or interpolated.
The UI shows "A key is stored." / "No key is stored." and nothing else. There is no
masked-preview affordance, which is the right call. **Confirmed.**

**Nothing logs the key.** The app layer contains exactly one `Logger`, declared at
`IngestionComposition.swift:17`; there is no `print`, `NSLog`, `os_log`, `debugPrint` or
`dump` in non-test code anywhere in `App/` or `Sources/`. Neither Anthropic client has a
logger at all — `AnthropicStreamingChatClient`'s doc comment (lines 29-33) states this as
a deliberate design decision rather than an omission, and the code matches. **Confirmed.**

**Nothing logs health data.** All eleven `ingestionLog` call sites were read
individually. Nine interpolate payload-free diagnostic enums at `.public`; the enums
were checked in the core and carry no measurement, date, or identifier. Two interpolate
arbitrary `Error` values, both at `.private`, both with the reasoning written down
(`IngestionComposition.swift:128-143, 161-165`). The one exception was L1, now fixed. No
message body, metric, date, workout UUID or route coordinate appears in any log
statement in the app. **The precedent holds everywhere.**

**Prompt minimisation (D3).** `WorkoutContext.factSheet()`
(`Sources/MaximizeCore/Context/WorkoutFactSheet.swift`) is the only function in the
codebase that renders workout data into prompt text, and both consumers take it
verbatim: `WorkoutScorer.instruction` appends `context.factSheet()` as a whole
(`WorkoutScorer.swift:97`) and `ChatInstruction` takes it as an opaque `String` it
refuses to touch. A grep for every reference to `factSheet`, `ScoringInstruction` and
`ChatInstruction` outside the context builder found no second assembler — the only
non-test hits are the two transport clients, and neither reads a `Workout`,
`DerivedMetrics` or `Score`.

What is *excluded* from the prompt is the part worth stating: **no route coordinates**
(the most re-identifying data in the record — a month of GPS is a home address; the
scorer gets grade-adjusted pace instead), **no raw heart-rate samples** (a bounded
10-bucket shape instead of thousands of points), and **no workout UUID, source device or
ingestion timestamp**. `ChatTurn.Speaker` structurally omits the `system` case so a
caller cannot smuggle the fact sheet in as a user message. `existingScore` is present for
chat and absent for scoring, which is a correctness property but also means the scorer
sends strictly less. This is a deliberate, documented, minimal payload and it matches
what `CLAUDE.md` asks for. **No defects found.**

> **Amended by MAX-068 (2026-08-05).** The exclusion list above was accurate at the time
> of the review and is no longer complete: **the per-kilometre pace breakdown is now sent,
> to chat only.** What changed, so this record stays the one place the payload is stated:
>
> - **Added, chat only:** `WorkoutContext.paceBreakdown` — `DerivedMetrics.distanceSplits`
>   read at ingestion-time values (D2), rendered as one `## Pace by kilometre` section of
>   ordered per-split paces. FR-2's worked example is *"why did my HR drift at mile 3"*,
>   and before this the prompt had no distance index to locate "mile 3" on the
>   elapsed-time heart-rate curve it was already sending.
> - **Still excluded from every prompt:** route coordinates, raw heart-rate samples, the
>   workout UUID, source device and ingestion timestamp. Unchanged.
> - **Still excluded from the scoring prompt:** `existingScore` **and now the pace
>   breakdown**. The scorer's call is automatic and unattended — one per ingested run,
>   with nobody asking — and the rubric (§10, D1) reads no split. `WorkoutScorer` refuses
>   a context assembled for chat rather than trusting the convention.
> - **The mile cut is stored and not sent.** The prompt is fixed to kilometres, matching
>   every other distance in the fact sheet, so content cannot vary with
>   `AppSettings.distanceUnit`.
> - **Bounded:** `WorkoutContext.maximumRenderedSplits` (200) caps what is listed, so a
>   corrupted `distanceMeters` cannot size a prompt full of health data. Above the cap the
>   section states the count and lists nothing.
>
> Net effect on egress: a chat prompt now carries a bounded, ordered list of per-kilometre
> elapsed times for a run whose distance, duration and heart-rate shape it already
> carried. It carries no new *kind* of identifier — no location, no timestamps — but it is
> a finer-grained record of one person's movement than anything previously sent, and it is
> sent only when the athlete has opened a thread and typed a question.

**Both Anthropic endpoints are hardcoded constants** — `endpointURLString` in each client
is a `private static let` never derived from user input, plan data, settings or a server
response, so there is no surface for redirecting a request carrying health data. HTTPS,
no certificate-validation overrides, no custom `URLSessionDelegate` anywhere in the tree.
`AnthropicStreamingChatClient` deliberately does not read a non-2xx response body
(line 160-163) — status codes are carried, server prose is not. **Confirmed.**

**Data at rest.** `.completeUntilFirstUserAuthentication` is set explicitly rather than
inherited (`MaximizeModelContainer.swift:46`), on both the directory and the store plus
sidecars, and the choice over `.complete` is justified by the background-wake
requirement rather than by convenience. `cloudKitDatabase` defaults to `.none` per A8, so
**no health data leaves the device at rest today**; `makeInMemory()` passes `.none`
explicitly rather than relying on `makeOnDisk`'s default, which is why it needed no
change when A8 flipped that default. `MaximizeStore` contains no logging and no error
type carrying row values. **No defects found beyond L3's documentation gap.**

**Secrets in the repo — tree and history.** `Support/Signing.local.xcconfig` has **never
existed in any of the 216 commits** in this repository (verified with
`git log --all --diff-filter=A --name-only`); only the committed
`Signing.xcconfig` and the `.example` template have. `.gitignore` covers
`Support/Signing.local.xcconfig`, `*.xcconfig.local`, `*.p12`, `*.mobileprovision`,
`.env*` and `secrets.json`. `Support/Signing.xcconfig` holds a documentation-reserved
placeholder bundle ID and an empty `DEVELOPMENT_TEAM`; the `.example` holds
`ABCDE12345`, which is a template, not a credential. `project.yml` contains no
identifiers. A pickaxe search of full history for `sk-ant` and a regex sweep of the whole
tree for API-key, AWS-key, PEM-block and bearer-token shapes returned nothing.
`AnthropicAPIKeyTests` uses `"unit-test-fixture-value"` and
`FakeAnthropicAPIKeyStore` is never seeded with anything credential-shaped. **Clean.
Given the repo went public today, this was the check most worth being certain about, and
it is.**

---

## 6. `/security-review` skill output

The skill **is** available in this environment and was run over the working tree. Two
things about it should be stated plainly rather than glossed:

1. **Its automated context capture came back empty.** The harness reported the branch and
   the three modified filenames correctly, but its `git diff`, file-list and commit
   blocks were all blank — the changes were unstaged at the point it snapshotted. I
   retrieved the diff manually (`git diff`) and performed the skill's analysis against
   the real content rather than against an empty diff.
2. **Its scope is "vulnerabilities newly introduced by this PR"**, not a standing audit of
   the codebase. Its exclusion list explicitly rules out findings in documentation files
   and defence-in-depth/hardening observations. So it is structurally incapable of
   surfacing M1, L2, L3 or the informational items, and the fact that it reports nothing
   is not evidence those are absent. §2 above is the audit; this section is only the
   skill's verdict on the diff.

**Result: no HIGH or MEDIUM findings in this PR's diff.**

Reasoning, per file:

- `App/HealthKitWorkoutObserver.swift` — the only functional change in the PR, and it
  strictly *reduces* exposure: an unbounded `Error` moves from `.public` to `.private`,
  and what remains public is `NSError.domain` and `.code`, neither attacker-controlled
  nor PII-bearing. `$0 as NSError` is a total bridging cast on Darwin and introduces no
  force unwrap or new failure mode. No new attack surface; net security-positive.
- `App/Persistence/MaximizeModelContainer.swift` — documentation only, no executable
  line changed.
- `docs/DEVICE-BUILD.md` — documentation only.

No input-validation, injection, authentication, authorization, crypto, deserialization or
data-exposure vulnerability is introduced by this diff.

---

## 7. What this review did **not** cover

Stated explicitly, because a security review's boundary is part of its result.

- **Anything requiring execution.** There is no Swift toolchain in this container. I did
  not run `swift build` or `swift test`, and neither did I run the app. Every statement
  above is from reading source. **CI is the first real compile of this branch.**
- **The chat UI and its prompt content (MAX-051).** Not in the audited tree; lands after
  this. It runs its own `/security-review` and this document does not substitute for it.
  MAX-046 and MAX-047 likewise.
- **Runtime verification of every control asserted here.** Specifically not verified:
  that the Keychain item is actually created with
  `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` on a device; that
  `.completeUntilFirstUserAuthentication` is actually applied to the store, its sidecars
  and the external-storage blobs on a real filesystem; that the external-data files
  actually inherit the directory's protection class (L3's entire mitigation rests on
  this); and what is actually transmitted on the wire to `api.anthropic.com`. Every one
  of these is a device check — see the PR's **Needs device verification** section.
- **iOS Keychain and Data Protection as primitives.** Trusted, not reviewed.
- **The Anthropic API's own handling of prompt content** once it leaves the device.
- **Dependency and supply-chain review.** The package has no third-party dependencies,
  but no audit of the toolchain or GitHub Actions supply chain was performed.
- **Threats requiring a jailbroken or physically compromised unlocked device.** A5
  accepts "someone extracts the key from my own phone" as the residual risk; this review
  did not attempt to bound how hard that is.

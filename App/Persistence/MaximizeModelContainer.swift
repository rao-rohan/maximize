import Foundation
import MaximizeCore
import SwiftData

/// Builds the app's `ModelContainer`.
///
/// ## File protection
///
/// The store holds workouts, heart-rate curves and GPS tracks. CLAUDE.md treats all of
/// it as PII and says to rely on iOS file protection, so the class is chosen here rather
/// than inherited by accident.
///
/// **`.completeUntilFirstUserAuthentication`, deliberately, and not `.complete`.**
///
/// The strongest class, `.complete`, makes a file unreadable whenever the device is
/// locked. That is wrong for this app specifically, and the reason is the same one
/// MAX-030 flagged for the anchor file: HealthKit wakes the app in the background to
/// deliver a new workout, and that wake can land while the phone is locked in a pocket
/// immediately after a run — which is the *normal* case for this product, not an edge
/// case. With `.complete`, the write would fail, the sink would throw, and the anchor
/// would stay pinned; nothing would be lost (the ingester is built for exactly that),
/// but zero-touch capture would stall until the athlete next unlocked the phone, and
/// the product's whole claim is that they never have to think about it.
///
/// `.completeUntilFirstUserAuthentication` keeps the store encrypted at rest before the
/// device has been unlocked once since boot, and readable thereafter — including while
/// locked. That is the same trade `FileWorkoutQueryAnchorStore` already makes, and
/// keeping the two consistent matters: a pipeline where the anchor is readable during a
/// wake but the workout store is not would fail in a way that looks like a HealthKit
/// bug.
///
/// It is also iOS's default class for app files. It is set explicitly anyway, because a
/// default is a thing that can change out from under a decision, and this one is
/// load-bearing enough to write down.
///
/// **Not verified by CI.** No line in this file has ever executed — there is no
/// simulator or device in this pipeline (tracker R2). See the PR for what a human should
/// check.
enum MaximizeModelContainer {
    /// Where the store lives. Application Support rather than Documents: this is app
    /// state, not user-visible content, and it should not appear in Files.
    static let storeDirectoryName = "Store"
    static let storeFileName = "Maximize.store"

    /// The protection class applied to the store and its sidecar files.
    static let fileProtection: FileProtectionType = .completeUntilFirstUserAuthentication

    /// The on-disk container the app runs against.
    ///
    /// ## CloudKit mirroring (MAX-021, D6)
    ///
    /// Defaults to `.automatic` — mirror to the private database of whichever iCloud
    /// container `project.yml`'s entitlement names — rather than a literal container
    /// identifier. `.automatic` reads that container out of the app's own entitlements
    /// at runtime, so this file never duplicates the container ID string that
    /// `project.yml` already owns; the two cannot drift apart because there is only one
    /// copy. The schema was already built to CloudKit's restrictions by MAX-020 — no
    /// unique constraints, no relationships, defaults on every non-optional property —
    /// so turning this on is configuration, not a redesign.
    ///
    /// **What this puts in the user's private CloudKit database:** every record in
    /// `MaximizeSchemaV1.models` — workouts, HR curves, routes, derived metrics, scores,
    /// annotations, chat threads, the plan, rest-day overrides, and settings. That is
    /// health data leaving the device. It is *not* the same exposure as a third-party
    /// server (CLAUDE.md's "Health and privacy" section): it is the user's own private
    /// CloudKit database, under their Apple ID, encrypted in transit and at rest by
    /// Apple's iCloud infrastructure, and never visible to this app's developer or
    /// anyone else. But it is data leaving the phone, which CLAUDE.md's "health data
    /// never leaves the device except as prompt context" line does not anticipate — so
    /// the position is stated here explicitly rather than assumed: private-database
    /// CloudKit sync between a user's own devices is treated as a deliberate, in-bounds
    /// exception to that rule, not a violation of it. Flagged for `/security-review` in
    /// MAX-021's PR per CLAUDE.md's "any PR touching what enters a Claude prompt" rule
    /// or its neighbors — this doesn't touch a Claude prompt, but it does change where
    /// health data can live, which is the same family of concern.
    ///
    /// **What stays off CloudKit, on purpose:**
    /// - The HealthKit query anchor (`FileWorkoutQueryAnchorStore`) — a separate,
    ///   non-SwiftData file store, untouched by this configuration. See R12 in
    ///   `PROJECT_TRACKER.md`: an anchor that synced would let a second device resume
    ///   past workouts it never ingested, and skip them silently and permanently.
    /// - The Anthropic API key (`KeychainAnthropicAPIKeyStore`) — Keychain, not
    ///   SwiftData, and explicitly written with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
    ///   plus `kSecAttrSynchronizable = false` (A5). Unaffected by and unrelated to this
    ///   change; noted here only to be complete about what does and doesn't sync.
    ///
    /// **A known gap this ticket found but did not fix:** `AppSettingsRecord` bundles
    /// genuine user preferences (`restDayBudgetDaysPerWeek`, `distanceUnitRawValue`,
    /// `appearanceRawValue` — reasonable to sync) together with three fields that
    /// mirror *this device's* OS accessibility settings (`reducesTransparency`,
    /// `increasesContrast`, `reducesMotion`). Those three are device-scoped, not
    /// user-scoped: syncing them means device A's Reduce Transparency setting can
    /// overwrite device B's. Today this is inert — nothing yet reads
    /// `UIAccessibility` to seed these fields (`AppSettings`'s own doc comment: "the
    /// app layer is responsible for seeding them from the system values", and no call
    /// site does that yet). It stops being inert the moment MAX-064 wires that up.
    /// Two fixes are available then, neither needed now: split these three fields into
    /// a second, non-CloudKit local store (the same shape as the anchor split), or —
    /// simpler — have whichever code seeds them from `UIAccessibility` re-run on every
    /// foreground activation, so a synced-in stale value from another device is
    /// overwritten by this device's real state before it is ever read. Left for
    /// MAX-064 to decide, since that ticket is the one that actually populates these
    /// fields; recorded here rather than silently redesigning `AppSettingsRecord` on a
    /// ticket that owns sync configuration, not the settings schema.
    /// - Parameter cloudKitDatabase: `.none` by default — see **A8** in
    ///   `docs/PRD-AMENDMENTS.md`. The iCloud entitlements were removed from
    ///   `project.yml` because free Apple Developer provisioning does not grant them,
    ///   and `.automatic` against a build with no iCloud entitlement is not a no-op:
    ///   container creation fails, `PersistenceComposition.store` becomes nil, and the
    ///   app runs with no storage at all — capturing nothing, while looking like it
    ///   works. Mirroring is one argument away when the entitlement comes back.
    static func makeOnDisk(
        cloudKitDatabase: ModelConfiguration.CloudKitDatabase = .none
    ) throws -> ModelContainer {
        let url = try prepareStoreURL()
        let configuration = ModelConfiguration(
            schema: Schema(versionedSchema: MaximizeSchemaV1.self),
            url: url,
            cloudKitDatabase: cloudKitDatabase
        )
        let container = try ModelContainer(
            for: Schema(versionedSchema: MaximizeSchemaV1.self),
            migrationPlan: MaximizeMigrationPlan.self,
            configurations: configuration
        )
        // Applied after creation as well as before: SQLite's write-ahead log and shared
        // memory files are created by the store, not by us, and they hold the same data
        // as the store itself. Protecting only the main file would leave recent writes —
        // the most recent run — in a less protected sidecar.
        applyFileProtection(around: url)
        return container
    }

    /// An in-memory container, for previews and for anything that wants a store without
    /// touching the athlete's real history.
    ///
    /// `cloudKitDatabase: .none` is passed explicitly, not left to whatever default the
    /// SDK's in-memory initializer happens to have. Previews and tests are exactly the
    /// callers that must never mirror to the real athlete's iCloud container, whatever
    /// `makeOnDisk` currently defaults to — making the choice explicit here means this
    /// store's CloudKit behavior does not depend on staying in sync with a decision made
    /// in a different function. That independence is why this line did not have to
    /// change when A8 flipped the on-disk default.
    static func makeInMemory() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(versionedSchema: MaximizeSchemaV1.self),
            migrationPlan: MaximizeMigrationPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
    }

    private static func prepareStoreURL() throws -> URL {
        let fileManager = FileManager.default
        let directory = try fileManager
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent(storeDirectoryName, isDirectory: true)

        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: fileProtection]
        )
        return directory.appendingPathComponent(storeFileName, isDirectory: false)
    }

    /// Sets the protection class on the store and the two sidecar files SQLite keeps
    /// beside it.
    ///
    /// Failures are swallowed on purpose. A file that does not exist yet is the normal
    /// case on first launch, and refusing to start the app because a protection
    /// attribute could not be set on a not-yet-created write-ahead log would trade a
    /// working app for no app. The directory attribute set in `prepareStoreURL` is the
    /// belt to this pair of braces.
    private static func applyFileProtection(around storeURL: URL) {
        let fileManager = FileManager.default
        let paths = [
            storeURL.path,
            storeURL.path + "-wal",
            storeURL.path + "-shm",
        ]
        for path in paths where fileManager.fileExists(atPath: path) {
            try? fileManager.setAttributes([.protectionKey: fileProtection], ofItemAtPath: path)
        }
    }
}

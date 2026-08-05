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
/// **MAX-069.** `applyFileProtection` used to name three files — the store and its two
/// SQLite sidecars — as if that were the complete list. It is not: three models use
/// `@Attribute(.externalStorage)`, and Core Data writes those bytes into its own
/// support directory, not into those three files. They were protected anyway, purely
/// by inheriting `prepareStoreURL`'s directory attribute; `applyFileProtection` now
/// also walks that directory and sets the class on every file it actually finds there,
/// so the protection no longer rests entirely on one attribute nobody is checking is
/// still set. See `applyFileProtection`'s own doc comment for the reasoning and its
/// limits.
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
    /// ## CloudKit mirroring (MAX-021, D6) — **currently off**
    ///
    /// **Read the parameter documentation below first: `cloudKitDatabase` defaults to
    /// `.none`, so nothing in this store leaves the device.** A8 deferred mirroring
    /// after the iCloud entitlements were removed from `project.yml`. The rest of this
    /// section describes what mirroring *would* do, and is kept because re-enabling it
    /// is a two-line change whose consequences should not have to be re-derived — but
    /// none of it is true of the app as it ships today. Corrected at MAX-072, where the
    /// prose still read as though `.automatic` were the default; a reader auditing
    /// "does health data leave the device" got the wrong answer from it.
    ///
    /// The argument to pass is `.automatic` — mirror to the private database of
    /// whichever iCloud container `project.yml`'s entitlement names — rather than a
    /// literal container identifier. `.automatic` reads that container out of the app's
    /// own entitlements at runtime, so this file never duplicates the container ID
    /// string that `project.yml` already owns; the two cannot drift apart because there
    /// is only one copy. The schema was already built to CloudKit's restrictions by
    /// MAX-020 — no unique constraints, no relationships, defaults on every non-optional
    /// property — so turning it back on is configuration, not a redesign.
    ///
    /// **What mirroring would put in the user's private CloudKit database:** every record in
    /// `MaximizeSchemaV1.models` — workouts, HR curves, routes, derived metrics, scores,
    /// annotations, chat threads, the plan, rest-day overrides, and settings. That would
    /// be health data leaving the device. It is *not* the same exposure as a third-party
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

        // MAX-069: do not remove `attributes:` here as "redundant" with the explicit
        // sweep below. This is the *primary* protection for the three
        // `@Attribute(.externalStorage)` blobs (see `applyFileProtection`'s doc
        // comment) — it is what protects them from the instant Core Data creates
        // them, which is before this process gets a chance to run anything against
        // them. The sweep is a second, independent check; it is not a replacement for
        // this line, and removing this line would not be caught by any test in this
        // repo (tracker R2).
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: fileProtection]
        )
        return directory.appendingPathComponent(storeFileName, isDirectory: false)
    }

    /// Sets the protection class on the store, the two sidecar files SQLite keeps
    /// beside it, and — via `sweepExternalStorageFiles` — everything else Core Data
    /// has written into the `Store` directory.
    ///
    /// ## Why this function used to protect less than it looked like it did (MAX-072 L3)
    ///
    /// Three models carry `@Attribute(.externalStorage)` —
    /// `HeartRateSeriesRecord.samplesJSON`, `RouteRecord.pointsJSON`,
    /// `ChatThreadRecord.messagesJSON` — and Core Data writes those bytes into its own
    /// support directory beside the store rather than into the SQLite row. Between
    /// them that is the HR curve, the GPS track and the chat transcript: the most
    /// sensitive content in the store. The three paths named below never covered them;
    /// what covered them was the *directory* attribute `prepareStoreURL` sets, which
    /// iOS applies as the default class for every file created underneath it,
    /// including whatever Core Data names its support directory. The bytes were
    /// protected; the code just didn't say so, and read as though the list below were
    /// exhaustive.
    ///
    /// ## What MAX-069 adds, and what it deliberately does not do
    ///
    /// `sweepExternalStorageFiles` walks the `Store` directory and re-asserts the
    /// protection class directly on every regular file it finds, at any depth — not
    /// just the three named here. It does **not** hardcode Core Data's support
    /// directory name to go find it specifically. That name is a Core Data
    /// implementation detail no Apple document contracts, and a wrong guess would
    /// compile, run, and silently protect nothing while reading as though it did —
    /// strictly worse than the inheritance this file already relies on. A plain walk
    /// needs no name: it protects whatever is actually there.
    ///
    /// This is additive, not load-bearing. `prepareStoreURL`'s directory attribute
    /// remains the thing that actually protects a file at the moment Core Data creates
    /// it — the walk only runs when `makeOnDisk` is called, so a file created and then
    /// never opened again before that walk still depended on inheritance for the gap
    /// in between. Keeping both means the directory attribute is no longer the *only*
    /// thing standing between "protected" and "silently not," which was L3's actual
    /// complaint.
    ///
    /// Failures — of any file in the list below, and of the sweep — are swallowed on
    /// purpose. A file that does not exist yet is the normal case on first launch, and
    /// refusing to start the app because a protection attribute could not be set on a
    /// not-yet-created write-ahead log would trade a working app for no app.
    ///
    /// **Not verified by CI.** No line here has ever executed — see this file's
    /// top-level doc comment and tracker R2. Whether `FileManager`'s enumerator
    /// actually walks into Core Data's real support directory on a real device, and
    /// what protection class the files inside it show under `ls -l@` before and after
    /// this runs, is unverified until a human checks it there. See the PR.
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
        sweepExternalStorageFiles(in: storeURL.deletingLastPathComponent())
    }

    /// Walks every file under `directory` (the `Store` directory) and re-asserts
    /// `fileProtection` on each regular file found, regardless of name or nesting —
    /// see `applyFileProtection`'s doc comment for why this does not target Core
    /// Data's external-storage directory by name.
    ///
    /// Deliberately **not** `.skipsHiddenFiles`: Core Data's own support directories
    /// are conventionally dot-prefixed, which is exactly the kind of entry that option
    /// would skip.
    ///
    /// An `errorHandler` that returns `true` is required to keep a single unreadable
    /// or mid-write entry from aborting the whole walk — the default behavior of
    /// `FileManager.enumerator` is to stop enumeration on the first error, which is
    /// the wrong failure mode here for the same reason the per-file `try?` above is:
    /// one file in a transient state should not cost every other file its protection.
    ///
    /// **Cost, stated plainly:** this runs on every `makeOnDisk` call — every cold
    /// launch — and its cost scales with the total number of external-storage blob
    /// files the athlete has ever accumulated (every HR curve, route and chat
    /// transcript, not just recent ones), because `setAttributes` is idempotent and
    /// this does not try to skip files already carrying the right class. For the
    /// workout volumes this app is built for that is at most a few thousand small
    /// files, which is not expected to be perceptible — but it was not measured on a
    /// device, and a human verifying this ticket should watch launch time on a store
    /// with real history, not an empty one.
    private static func sweepExternalStorageFiles(in directory: URL) {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return
        }
        for case let fileURL as URL in enumerator {
            let isRegularFile = (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
            guard isRegularFile else { continue }
            try? fileManager.setAttributes([.protectionKey: fileProtection], ofItemAtPath: fileURL.path)
        }
    }
}

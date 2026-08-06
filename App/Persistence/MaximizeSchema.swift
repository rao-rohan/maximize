import Foundation
import MaximizeCore
import SwiftData

// MARK: - The CloudKit constraints this schema is built around
//
// A1 makes SwiftData the store and CloudKit the backup, and MAX-021 turns mirroring
// on. CloudKit does not accept every schema SwiftData can express, and the mismatches
// are not detected at compile time — an incompatible model container simply fails to
// load once sync is enabled. So the restrictions are designed for here, while there is
// no data, rather than discovered later. Verified against Apple's documentation:
//
//   *Syncing model data across a person's devices* (SwiftData) — "the SwiftData
//   framework does include a small number of features that CloudKit doesn't support
//   natively, such as unique constraints and nonoptional relationships." On
//   `@Attribute`: "The framework synchronizes changes concurrently and at opportune
//   times, which means CloudKit is unable to enforce the unique property option." On
//   `@Relationship`: "The iCloud servers don't guarantee atomic processing of
//   relationship changes, so CloudKit requires all relationships to be optional […]
//   CloudKit is unable to support the deny delete rule."
//
//   *Creating a Core Data model for CloudKit* — "Unique constraints aren't supported."
//   "All relationships must be optional […] All relationships must have an inverse."
//
// Three consequences, each visible in the code below:
//
// 1. **No `@Attribute(.unique)`, anywhere.** FR-0.5's dedupe on `workoutUUID` cannot be
//    a schema constraint. It is a write-path invariant instead — a single
//    fetch-then-insert chokepoint in `MaximizeStore` — and reads resolve a duplicate
//    deterministically rather than assuming one is impossible. See `WorkoutRepository`.
//
// 2. **No relationships at all.** Records reference their workout by `workoutUUID`.
//    Since CloudKit forces every relationship to be optional, a relationship could not
//    have enforced the link anyway; what it would have bought is cascade delete, and
//    that is paid for explicitly by `WorkoutAttachedRecord` — an enum the deletion path
//    switches over exhaustively, so a later ticket adding a per-workout record type
//    cannot compile without deciding what deletion does to it. The domain already keys
//    every attachment by `workoutID`, so this also stops the schema inventing a second
//    way to say the same thing.
//
// 3. **Every property has a default value.** `NSPersistentCloudKitContainer` validates
//    at store load that no attribute is both non-optional and default-less, and it
//    refuses to load the store when one is. Optionality here therefore means what the
//    domain means by it, never "optional because CloudKit insisted".
//
// One more property of CloudKit worth stating where the schema is defined, because it
// constrains every future ticket: **a promoted CloudKit schema is additive only.**
// Apple: "After you promote your schema to production, the record types and their
// fields are immutable and exist for all time. You can add new record types, and
// additional fields to existing record types, but you can't modify or delete existing
// record types." A SwiftData migration can therefore add, but never rename or retype,
// once MAX-021 has promoted a schema.

// MARK: - Schema versioning
//
// Versioned from the first record, because retrofitting it is the expensive version of
// this work. `VersionedSchema` is what gives a future migration something to migrate
// *from*: the models are nested inside `MaximizeSchemaV1` so that a V2 can hold a
// differently-shaped `WorkoutRecord` alongside this one and a `MigrationStage` can map
// between them. Declaring the models at file scope instead would make V2's first act a
// rewrite of V1's definitions, which is precisely the position that makes a migration
// unwritable.

/// The first schema version. Nothing in here has ever been migrated from anything.
enum MaximizeSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            WorkoutRecord.self,
            HeartRateSeriesRecord.self,
            RouteRecord.self,
            DerivedMetricsRecord.self,
            ScoreRecord.self,
            ScoreAnnotationRecord.self,
            MiscategorisedScoreLabelRecord.self,
            MuscleGroupEntryRecord.self,
            ChatThreadRecord.self,
            PlanRecord.self,
            RestDayOverrideRecord.self,
            AppSettingsRecord.self,
        ]
    }

    // MARK: Records
    //
    // Each class below mirrors one `Stored*` struct from `MaximizeCore` property for
    // property. That is the entire content of these types: no computed state, no
    // validation, no branches. Everything with a decision in it lives in the core, where
    // `StoredRecordRoundTripTests` runs against it on every commit — CI has no simulator
    // and never executes SwiftData, so a decision made here would be a decision nothing
    // checks.

    @Model
    final class WorkoutRecord {
        /// The HealthKit workout UUID — the dedupe key of FR-0.5.
        ///
        /// Not `@Attribute(.unique)`: CloudKit cannot enforce uniqueness (see the note at
        /// the top of this file). `MaximizeStore` upserts on this value instead.
        var workoutUUID: UUID = UUID()
        var activityTypeRawValue: String = ""
        var start: Date = Date.distantPast
        var end: Date = Date.distantPast
        var durationSeconds: Double = 0
        var distanceMeters: Double?
        var activeEnergyKilocalories: Double?
        var hasRoute: Bool = false
        var sourceRawValue: String = ""
        var ingestedAt: Date = Date.distantPast

        init(_ stored: StoredWorkout) {
            workoutUUID = stored.workoutUUID
            activityTypeRawValue = stored.activityTypeRawValue
            start = stored.start
            end = stored.end
            durationSeconds = stored.durationSeconds
            distanceMeters = stored.distanceMeters
            activeEnergyKilocalories = stored.activeEnergyKilocalories
            hasRoute = stored.hasRoute
            sourceRawValue = stored.sourceRawValue
            ingestedAt = stored.ingestedAt
        }

        var stored: StoredWorkout {
            get {
                StoredWorkout(
                    workoutUUID: workoutUUID,
                    activityTypeRawValue: activityTypeRawValue,
                    start: start,
                    end: end,
                    durationSeconds: durationSeconds,
                    distanceMeters: distanceMeters,
                    activeEnergyKilocalories: activeEnergyKilocalories,
                    hasRoute: hasRoute,
                    sourceRawValue: sourceRawValue,
                    ingestedAt: ingestedAt
                )
            }
            set {
                workoutUUID = newValue.workoutUUID
                activityTypeRawValue = newValue.activityTypeRawValue
                start = newValue.start
                end = newValue.end
                durationSeconds = newValue.durationSeconds
                distanceMeters = newValue.distanceMeters
                activeEnergyKilocalories = newValue.activeEnergyKilocalories
                hasRoute = newValue.hasRoute
                sourceRawValue = newValue.sourceRawValue
                ingestedAt = newValue.ingestedAt
            }
        }
    }

    /// D7's whole-curve blob.
    ///
    /// `.externalStorage` moves the bytes out of the SQLite row into a file the store
    /// manages, and it is chosen here for a CloudKit reason as much as a local one: a
    /// `CKRecord`'s fields are limited to roughly 1 MB in total, while an asset is not.
    /// A JSON heart-rate curve is tens of kilobytes for a typical run, but a long
    /// ultra-distance effort sampled every second would approach and could exceed that
    /// limit — and the failure would arrive as a sync error on the athlete's biggest run
    /// of the year. Core Data mirrors external binary data as a `CKAsset`, so this keeps
    /// the record small whatever the curve's length.
    @Model
    final class HeartRateSeriesRecord {
        var workoutUUID: UUID = UUID()

        @Attribute(.externalStorage) var samplesJSON: Data = Data()

        init(_ stored: StoredHeartRateSeries) {
            workoutUUID = stored.workoutUUID
            samplesJSON = stored.samplesJSON
        }

        var stored: StoredHeartRateSeries {
            get { StoredHeartRateSeries(workoutUUID: workoutUUID, samplesJSON: samplesJSON) }
            set {
                workoutUUID = newValue.workoutUUID
                samplesJSON = newValue.samplesJSON
            }
        }
    }

    /// Absent, not empty, for an indoor run (FR-0.6). External storage for the same
    /// reason as the heart-rate curve — a marathon's GPS track is the larger of the two.
    @Model
    final class RouteRecord {
        var workoutUUID: UUID = UUID()

        @Attribute(.externalStorage) var pointsJSON: Data = Data()

        init(_ stored: StoredRoute) {
            workoutUUID = stored.workoutUUID
            pointsJSON = stored.pointsJSON
        }

        var stored: StoredRoute {
            get { StoredRoute(workoutUUID: workoutUUID, pointsJSON: pointsJSON) }
            set {
                workoutUUID = newValue.workoutUUID
                pointsJSON = newValue.pointsJSON
            }
        }
    }

    @Model
    final class DerivedMetricsRecord {
        var workoutUUID: UUID = UUID()
        var averageHeartRateBPM: Double?
        var maximumHeartRateBPM: Double?
        var timeAboveCapSeconds: Double?
        var heartRateDriftFraction: Double?
        var averageCadenceStepsPerMinute: Double?
        var gradeAdjustedPaceSecondsPerKilometer: Double?
        var zoneSplitsJSON: Data = Data()

        /// MAX-046's pace breakdown. Optional and default-less on purpose — see
        /// `StoredDerivedMetrics.distanceSplitsJSON` for the domain half of that choice.
        ///
        /// **What this does to a store that already has rows.** Adding a nullable
        /// attribute is Core Data's canonical lightweight-migration case: existing
        /// `DerivedMetricsRecord` rows gain the column as NULL, so every run ingested
        /// before this build reads back with `DerivedMetrics.distanceSplits == nil` and
        /// says so on screen rather than showing a fabricated breakdown. Nothing is
        /// rewritten and no value has to be invented for the old rows, which is exactly
        /// why the attribute is optional rather than a defaulted `Data()`: an empty blob
        /// would decode to a `DistanceSplits` with no series, a value the domain forbids.
        ///
        /// **Why the schema version is unchanged.** `MaximizeSchemaV1` has never been
        /// promoted to a CloudKit production schema — mirroring is off entirely (A8) —
        /// so the additive-only immutability rule quoted at the top of this file has not
        /// started applying. A V2 would mean a second copy of all ten model classes and
        /// a `MigrationStage` to carry a change SwiftData infers on its own. The version
        /// bump is what the *first* shape change after promotion has to buy; this one
        /// does not.
        var distanceSplitsJSON: Data?

        /// MAX-067's backfill marker. Defaulted `false` — unlike every other Bool in this
        /// file, deliberately not `true` — because that default is the entire migration:
        /// existing rows gain this column as `false`, which is exactly the honest answer
        /// for a row written before the split calculator existed. A row written by this
        /// build always sets it explicitly through `StoredDerivedMetrics`, so the default
        /// is only ever actually read on a pre-MAX-067 row. See
        /// `DerivedMetrics.distanceSplitsComputed` for the full reasoning, and the note on
        /// `distanceSplitsJSON` above for why a nullable/defaulted column is Core Data's
        /// lightweight-migration case and does not need a schema version bump under A8.
        var distanceSplitsComputed: Bool = false
        var planVersionNumber: Int = 1

        init(_ stored: StoredDerivedMetrics) {
            workoutUUID = stored.workoutUUID
            averageHeartRateBPM = stored.averageHeartRateBPM
            maximumHeartRateBPM = stored.maximumHeartRateBPM
            timeAboveCapSeconds = stored.timeAboveCapSeconds
            heartRateDriftFraction = stored.heartRateDriftFraction
            averageCadenceStepsPerMinute = stored.averageCadenceStepsPerMinute
            gradeAdjustedPaceSecondsPerKilometer = stored.gradeAdjustedPaceSecondsPerKilometer
            zoneSplitsJSON = stored.zoneSplitsJSON
            distanceSplitsJSON = stored.distanceSplitsJSON
            distanceSplitsComputed = stored.distanceSplitsComputed
            planVersionNumber = stored.planVersionNumber
        }

        var stored: StoredDerivedMetrics {
            get {
                StoredDerivedMetrics(
                    workoutUUID: workoutUUID,
                    averageHeartRateBPM: averageHeartRateBPM,
                    maximumHeartRateBPM: maximumHeartRateBPM,
                    timeAboveCapSeconds: timeAboveCapSeconds,
                    heartRateDriftFraction: heartRateDriftFraction,
                    averageCadenceStepsPerMinute: averageCadenceStepsPerMinute,
                    gradeAdjustedPaceSecondsPerKilometer: gradeAdjustedPaceSecondsPerKilometer,
                    zoneSplitsJSON: zoneSplitsJSON,
                    distanceSplitsJSON: distanceSplitsJSON,
                    distanceSplitsComputed: distanceSplitsComputed,
                    planVersionNumber: planVersionNumber
                )
            }
            set {
                workoutUUID = newValue.workoutUUID
                averageHeartRateBPM = newValue.averageHeartRateBPM
                maximumHeartRateBPM = newValue.maximumHeartRateBPM
                timeAboveCapSeconds = newValue.timeAboveCapSeconds
                heartRateDriftFraction = newValue.heartRateDriftFraction
                averageCadenceStepsPerMinute = newValue.averageCadenceStepsPerMinute
                gradeAdjustedPaceSecondsPerKilometer = newValue.gradeAdjustedPaceSecondsPerKilometer
                zoneSplitsJSON = newValue.zoneSplitsJSON
                distanceSplitsJSON = newValue.distanceSplitsJSON
                distanceSplitsComputed = newValue.distanceSplitsComputed
                planVersionNumber = newValue.planVersionNumber
            }
        }
    }

    /// The immutable auto-score (D8).
    ///
    /// Nothing about a SwiftData property can be immutable, so D8 is enforced by the
    /// only door into this record: `MaximizeStore.recordAutomaticScore` refuses to
    /// replace one that already exists.
    @Model
    final class ScoreRecord {
        var workoutUUID: UUID = UUID()
        var planVersionNumber: Int = 1
        var scheduledSessionJSON: Data = Data()
        var actualClassificationRawValue: String = ""
        var points: Int = 0
        var effectiveThresholdPoints: Int = 0
        var bandRawValue: String = ""
        var rubricBandIdentifier: String?
        var rationale: String = ""
        var scoredAt: Date = Date.distantPast

        init(_ stored: StoredScore) {
            workoutUUID = stored.workoutUUID
            planVersionNumber = stored.planVersionNumber
            scheduledSessionJSON = stored.scheduledSessionJSON
            actualClassificationRawValue = stored.actualClassificationRawValue
            points = stored.points
            effectiveThresholdPoints = stored.effectiveThresholdPoints
            bandRawValue = stored.bandRawValue
            rubricBandIdentifier = stored.rubricBandIdentifier
            rationale = stored.rationale
            scoredAt = stored.scoredAt
        }

        var stored: StoredScore {
            StoredScore(
                workoutUUID: workoutUUID,
                planVersionNumber: planVersionNumber,
                scheduledSessionJSON: scheduledSessionJSON,
                actualClassificationRawValue: actualClassificationRawValue,
                points: points,
                effectiveThresholdPoints: effectiveThresholdPoints,
                bandRawValue: bandRawValue,
                rubricBandIdentifier: rubricBandIdentifier,
                rationale: rationale,
                scoredAt: scoredAt
            )
        }
    }

    /// A correction layered on the auto-score, never replacing it (D8).
    @Model
    final class ScoreAnnotationRecord {
        var annotationUUID: UUID = UUID()
        var workoutUUID: UUID = UUID()
        var manualScorePoints: Int = 0
        var note: String?
        var createdAt: Date = Date.distantPast

        init(_ stored: StoredScoreAnnotation) {
            annotationUUID = stored.annotationUUID
            workoutUUID = stored.workoutUUID
            manualScorePoints = stored.manualScorePoints
            note = stored.note
            createdAt = stored.createdAt
        }

        var stored: StoredScoreAnnotation {
            StoredScoreAnnotation(
                annotationUUID: annotationUUID,
                workoutUUID: workoutUUID,
                manualScorePoints: manualScorePoints,
                note: note,
                createdAt: createdAt
            )
        }
    }

    /// A mark saying an auto-score was judged against the wrong discipline's ask (A21,
    /// MAX-143).
    ///
    /// **Deliberately not a column on `ScoreRecord`.** A flag there would be a settable
    /// property on the record D8 makes immutable, and the only thing keeping that record
    /// immutable is that no door in this file writes to it. A separate table keeps that
    /// true by construction: nothing here can reach a score.
    ///
    /// Its own identifier rather than the workout's, so two devices labelling the same
    /// score before either has synced produce two rows rather than a conflict —
    /// `ScoreLedger` reads labelling as a property of the set, so the duplicate costs
    /// nothing.
    ///
    /// **Why this needs no migration**, in `MuscleGroupEntryRecord`'s words: it is a new
    /// record type, so SwiftData creates its table on first load and no row of any other
    /// model is read, rewritten or re-typed. Every property is non-optional with a
    /// default, there is no `@Attribute(.unique)` and no relationship, per this file's
    /// CloudKit rules — and adding a record type is the one shape change those rules
    /// permit even after a schema has been promoted.
    @Model
    final class MiscategorisedScoreLabelRecord {
        var labelUUID: UUID = UUID()
        var workoutUUID: UUID = UUID()

        /// `ScheduledSessionKind.rawValue` — the ask the score was actually judged
        /// against, copied from the score so the label carries its own grounds.
        var judgedAgainstRawValue: String = ""

        /// `Discipline.rawValue` — what the workout actually was.
        var actualDisciplineRawValue: String = ""

        var recordedAt: Date = Date.distantPast

        init(_ stored: StoredMiscategorisedScoreLabel) {
            labelUUID = stored.labelUUID
            workoutUUID = stored.workoutUUID
            judgedAgainstRawValue = stored.judgedAgainstRawValue
            actualDisciplineRawValue = stored.actualDisciplineRawValue
            recordedAt = stored.recordedAt
        }

        var stored: StoredMiscategorisedScoreLabel {
            StoredMiscategorisedScoreLabel(
                labelUUID: labelUUID,
                workoutUUID: workoutUUID,
                judgedAgainstRawValue: judgedAgainstRawValue,
                actualDisciplineRawValue: actualDisciplineRawValue,
                recordedAt: recordedAt
            )
        }
    }

    /// What the athlete said a strength session worked (A22).
    ///
    /// A sibling of `ScoreAnnotationRecord` in every respect that matters here: its own
    /// identifier rather than the workout's, because a workout accumulates entries; no
    /// update path in the store, because entries are additive; and `recordedAt` is what
    /// "the answer in force" resolves by.
    ///
    /// **Why this needs no migration.** It is a *new record type*, not a change to an
    /// existing one — SwiftData creates its table on first load and no row of any other
    /// model is read, rewritten or re-typed. Every property is non-optional with a
    /// default, per this file's CloudKit rule; there is no `@Attribute(.unique)` and no
    /// relationship, for the reasons at the top of this file. `MaximizeSchemaV1`'s
    /// version number does not move, on the same grounds as
    /// `DerivedMetricsRecord.distanceSplitsJSON`: mirroring is off (A8), this schema has
    /// never been promoted to a CloudKit production schema, so the additive-only
    /// immutability rule quoted above has not started applying — and adding a record
    /// type is the one shape change that rule permits even after it has.
    @Model
    final class MuscleGroupEntryRecord {
        var entryUUID: UUID = UUID()
        var workoutUUID: UUID = UUID()

        /// A JSON array of `MuscleGroup` raw values, canonically ordered — see
        /// `StoredMuscleGroupEntry` for why the set is a blob rather than six columns.
        var groupsJSON: Data = Data()

        var recordedAt: Date = Date.distantPast

        init(_ stored: StoredMuscleGroupEntry) {
            entryUUID = stored.entryUUID
            workoutUUID = stored.workoutUUID
            groupsJSON = stored.groupsJSON
            recordedAt = stored.recordedAt
        }

        var stored: StoredMuscleGroupEntry {
            StoredMuscleGroupEntry(
                entryUUID: entryUUID,
                workoutUUID: workoutUUID,
                groupsJSON: groupsJSON,
                recordedAt: recordedAt
            )
        }
    }

    /// See `StoredChatThread`'s doc comment for why `createdAt` exists and what it is
    /// not: a duplicate-resolution tiebreak (MAX-048), not domain data.
    ///
    /// ## MAX-093's additive columns, and why they need no migration
    ///
    /// `subjectKindRawValue`, `scopeFromISO8601`, `scopeThroughISO8601` and
    /// `lastActivityAt` are new. Every one of them is either non-optional with a default
    /// or optional with none — the two shapes `DerivedMetricsRecord.distanceSplitsComputed`
    /// and `.distanceSplitsJSON` already established for "a column some rows will not
    /// have written." That is what makes this additive: SwiftData's lightweight
    /// migration adds a column to an existing table without touching a row's existing
    /// data, so a `ChatThreadRecord` written before this build reads back with
    /// `subjectKindRawValue == "workout"` (A11: every existing thread has a workout
    /// subject) and both scope columns `nil`. Nothing is rewritten, and
    /// `MaximizeSchemaV1`'s version number does not move — see
    /// `distanceSplitsJSON`'s doc comment above for why a version bump is not owed until
    /// this schema is actually promoted to CloudKit production, which A8 keeps off.
    @Model
    final class ChatThreadRecord {
        var threadUUID: UUID = UUID()

        /// `ChatSubjectKind.rawValue`. Defaults to `"workout"`, matching what every row
        /// written before this column existed actually is (A11's "no migration").
        var subjectKindRawValue: String = ChatSubjectKind.workout.rawValue

        /// Meaningful only when `subjectKindRawValue == "workout"`. Carries
        /// `StoredChatThread.noWorkoutSentinel` for a training thread — see that type's
        /// doc comment for why this stays non-optional rather than becoming one more
        /// thing every reader has to unwrap.
        var workoutUUID: UUID = UUID()

        /// `CalendarDay`'s `YYYY-MM-DD` form. `nil` for a workout subject, including
        /// every row written before this column existed — there is nothing to backfill
        /// it with, and there does not need to be (A11).
        var scopeFromISO8601: String?

        /// See `scopeFromISO8601`.
        var scopeThroughISO8601: String?

        @Attribute(.externalStorage) var messagesJSON: Data = Data()

        /// Default `.distantPast` per this file's "every property has a default"
        /// rule. A record written before this field existed loads with that default,
        /// which is deliberate rather than a gap: `MaximizeStore.workoutThreadRecords(for:)`
        /// breaks a tie on `threadUUID`, so two such pre-migration duplicates still
        /// resolve deterministically even though they collapse onto the same
        /// `createdAt`.
        var createdAt: Date = Date.distantPast

        /// What the thread list sorts on and "which thread opens" resolves by (§2.2,
        /// §2.3). Defaults to `StoredChatThread.unsetLastActivityAt`
        /// (`Date.distantPast`) — a pre-MAX-093 row loads with that sentinel, and
        /// `StoredChatThread.toDomain()` derives the real value from `messagesJSON` and
        /// `createdAt` exactly as MAX-092 did before this column existed. A record
        /// written by this build always sets it explicitly.
        var lastActivityAt: Date = StoredChatThread.unsetLastActivityAt

        init(_ stored: StoredChatThread) {
            threadUUID = stored.threadUUID
            subjectKindRawValue = stored.subjectKindRawValue
            workoutUUID = stored.workoutUUID
            scopeFromISO8601 = stored.scopeFromISO8601
            scopeThroughISO8601 = stored.scopeThroughISO8601
            messagesJSON = stored.messagesJSON
            createdAt = stored.createdAt
            lastActivityAt = stored.lastActivityAt
        }

        var stored: StoredChatThread {
            get {
                StoredChatThread(
                    threadUUID: threadUUID,
                    subjectKindRawValue: subjectKindRawValue,
                    workoutUUID: workoutUUID,
                    scopeFromISO8601: scopeFromISO8601,
                    scopeThroughISO8601: scopeThroughISO8601,
                    messagesJSON: messagesJSON,
                    createdAt: createdAt,
                    lastActivityAt: lastActivityAt
                )
            }
            set {
                threadUUID = newValue.threadUUID
                subjectKindRawValue = newValue.subjectKindRawValue
                workoutUUID = newValue.workoutUUID
                scopeFromISO8601 = newValue.scopeFromISO8601
                scopeThroughISO8601 = newValue.scopeThroughISO8601
                messagesJSON = newValue.messagesJSON
                createdAt = newValue.createdAt
                lastActivityAt = newValue.lastActivityAt
            }
        }
    }

    /// A plan version (D1). `effectiveFromISO8601` is `CalendarDay`'s own `YYYY-MM-DD`
    /// form, which sorts lexicographically in chronological order — so ordering plan
    /// versions needs no date parsing and no time zone.
    @Model
    final class PlanRecord {
        var versionNumber: Int = 1
        var effectiveFromISO8601: String = ""
        var payloadJSON: Data = Data()

        init(_ stored: StoredPlan) {
            versionNumber = stored.versionNumber
            effectiveFromISO8601 = stored.effectiveFromISO8601
            payloadJSON = stored.payloadJSON
        }

        var stored: StoredPlan {
            get {
                StoredPlan(
                    versionNumber: versionNumber,
                    effectiveFromISO8601: effectiveFromISO8601,
                    payloadJSON: payloadJSON
                )
            }
            set {
                versionNumber = newValue.versionNumber
                effectiveFromISO8601 = newValue.effectiveFromISO8601
                payloadJSON = newValue.payloadJSON
            }
        }
    }

    @Model
    final class RestDayOverrideRecord {
        var dayISO8601: String = ""
        var convertedFromMissed: Bool = false
        var createdAt: Date = Date.distantPast

        init(_ stored: StoredRestDayOverride) {
            dayISO8601 = stored.dayISO8601
            convertedFromMissed = stored.convertedFromMissed
            createdAt = stored.createdAt
        }

        var stored: StoredRestDayOverride {
            get {
                StoredRestDayOverride(
                    dayISO8601: dayISO8601,
                    convertedFromMissed: convertedFromMissed,
                    createdAt: createdAt
                )
            }
            set {
                dayISO8601 = newValue.dayISO8601
                convertedFromMissed = newValue.convertedFromMissed
                createdAt = newValue.createdAt
            }
        }
    }

    /// The single settings row. `SettingsRepository` owns the "there is only one" rule —
    /// SwiftData has no way to express a singleton, and CloudKit could not enforce it if
    /// it did.
    @Model
    final class AppSettingsRecord {
        var restDayBudgetDaysPerWeek: Int = 1
        var distanceUnitRawValue: String = "miles"
        var appearanceRawValue: String = "dark"
        var reducesTransparency: Bool = false
        var increasesContrast: Bool = false
        var reducesMotion: Bool = false

        init(_ stored: StoredAppSettings) {
            restDayBudgetDaysPerWeek = stored.restDayBudgetDaysPerWeek
            distanceUnitRawValue = stored.distanceUnitRawValue
            appearanceRawValue = stored.appearanceRawValue
            reducesTransparency = stored.reducesTransparency
            increasesContrast = stored.increasesContrast
            reducesMotion = stored.reducesMotion
        }

        var stored: StoredAppSettings {
            get {
                StoredAppSettings(
                    restDayBudgetDaysPerWeek: restDayBudgetDaysPerWeek,
                    distanceUnitRawValue: distanceUnitRawValue,
                    appearanceRawValue: appearanceRawValue,
                    reducesTransparency: reducesTransparency,
                    increasesContrast: increasesContrast,
                    reducesMotion: reducesMotion
                )
            }
            set {
                restDayBudgetDaysPerWeek = newValue.restDayBudgetDaysPerWeek
                distanceUnitRawValue = newValue.distanceUnitRawValue
                appearanceRawValue = newValue.appearanceRawValue
                reducesTransparency = newValue.reducesTransparency
                increasesContrast = newValue.increasesContrast
                reducesMotion = newValue.reducesMotion
            }
        }
    }
}

/// The migration path across schema versions.
///
/// Empty of stages because there is only one version, and that is the point of writing
/// it now: the container is built through a migration plan from the first launch, so
/// adding V2 is adding a stage rather than introducing the whole mechanism at the moment
/// there is finally data that would be lost by getting it wrong.
///
/// A note for whoever writes the first stage: once MAX-021 has promoted a CloudKit
/// schema to production, a migration may **add** record types and fields but may never
/// rename, retype or remove them. A `.custom` stage that would be routine on a local-only
/// store is not available once the data is mirrored.
///
/// ## MAX-169: why the two record types added at MAX-143 and A22 still need no stage
///
/// The question that ticket was asked to settle, because `MiscategorisedScoreLabelRecord`
/// and `MuscleGroupEntryRecord` are the first shape change to land on a schema that may
/// already have a store on a phone behind it. The conclusion is **no stage**, and the
/// argument is four steps:
///
/// 1. **Both are new entities, not changes to existing ones.** Core Data's lightweight
///    migration lists adding an entity among the changes it can infer, and the inference
///    here has nothing to infer *between*: the two tables are created, and no row of any
///    other model is read, rewritten or re-typed. The two harder cases — a new nullable
///    column and a new defaulted column — were already taken by
///    `DerivedMetricsRecord.distanceSplitsJSON` and `.distanceSplitsComputed`, and neither
///    got a stage either.
/// 2. **A stage could not carry this change anyway.** `MigrationStage` maps between two
///    `VersionedSchema`s with *different* version identifiers, so writing one means a V2
///    holding a second copy of all twelve model classes. The stage over it would be
///    `.lightweight`, which asks SwiftData for exactly the inference it already performs.
///    The duplicate schema would buy nothing and would have to be maintained in step.
/// 3. **A `.custom` stage has no work to do.** Custom stages exist to invent a value an
///    old row cannot supply. There is no such row here: the new tables start empty, and
///    every property on both types is non-optional with a default, per this file's
///    CloudKit rules.
/// 4. **Adding a record type is the one shape change that stays legal after promotion**
///    (Apple, quoted at the top of this file), so this reasoning does not expire when A8
///    is lifted and MAX-021 promotes a schema.
///
/// **What that conclusion rests on, stated plainly: an argument, not an observation.** No
/// test and no device in this project has ever opened a pre-existing store with the new
/// shape — the core cannot import SwiftData, CI has no simulator (tracker R2), and
/// `MaximizeModelContainer.makeOnDisk()` has never executed in this pipeline. If the
/// inference does not go the way this comment expects, Core Data reports it as
/// `NSPersistentStoreIncompatibleVersionHashError`, `NSMigrationError` or
/// `NSInferredMappingModelError`; MAX-169 classifies exactly those codes as
/// `StoreOpenFailureReason.shapeThisBuildCannotOpen`, which is the one failure state that
/// offers no retry, says the history is still on the device, and offers nothing that would
/// delete it. That is the designed landing place for this argument being wrong.
///
/// **One cost of holding the version identifier still, which nobody had written down.**
/// Several genuinely different on-disk shapes now all report themselves as version 1.0.0:
/// pre-MAX-046, pre-MAX-093, pre-MAX-143, and this one. That is free while every step
/// between them is additive and inferable — but it means a future `.custom` stage keyed
/// `1.0.0 → 2.0.0` cannot tell which of those shapes it has been handed. The first change
/// that is *not* inferable is therefore also the last moment at which versioning is cheap,
/// and whoever hits it should bump the identifier before writing anything else.
enum MaximizeMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [MaximizeSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

// The current version, named without its version number so call sites do not have to be
// rewritten when V2 arrives. Only these aliases move.
typealias WorkoutRecord = MaximizeSchemaV1.WorkoutRecord
typealias HeartRateSeriesRecord = MaximizeSchemaV1.HeartRateSeriesRecord
typealias RouteRecord = MaximizeSchemaV1.RouteRecord
typealias DerivedMetricsRecord = MaximizeSchemaV1.DerivedMetricsRecord
typealias ScoreRecord = MaximizeSchemaV1.ScoreRecord
typealias ScoreAnnotationRecord = MaximizeSchemaV1.ScoreAnnotationRecord
typealias MiscategorisedScoreLabelRecord = MaximizeSchemaV1.MiscategorisedScoreLabelRecord
typealias MuscleGroupEntryRecord = MaximizeSchemaV1.MuscleGroupEntryRecord
typealias ChatThreadRecord = MaximizeSchemaV1.ChatThreadRecord
typealias PlanRecord = MaximizeSchemaV1.PlanRecord
typealias RestDayOverrideRecord = MaximizeSchemaV1.RestDayOverrideRecord
typealias AppSettingsRecord = MaximizeSchemaV1.AppSettingsRecord

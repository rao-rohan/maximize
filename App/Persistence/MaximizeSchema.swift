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

    /// See `StoredChatThread`'s doc comment for why `createdAt` exists and what it is
    /// not: a duplicate-resolution tiebreak (MAX-048), not domain data.
    @Model
    final class ChatThreadRecord {
        var threadUUID: UUID = UUID()
        var workoutUUID: UUID = UUID()

        @Attribute(.externalStorage) var messagesJSON: Data = Data()

        /// Default `.distantPast` per this file's "every property has a default"
        /// rule. A record written before this field existed loads with that default,
        /// which is deliberate rather than a gap: `MaximizeStore.threadRecords(for:)`
        /// breaks a tie on `threadUUID`, so two such pre-migration duplicates still
        /// resolve deterministically even though they collapse onto the same
        /// `createdAt`.
        var createdAt: Date = Date.distantPast

        init(_ stored: StoredChatThread) {
            threadUUID = stored.threadUUID
            workoutUUID = stored.workoutUUID
            messagesJSON = stored.messagesJSON
            createdAt = stored.createdAt
        }

        var stored: StoredChatThread {
            get {
                StoredChatThread(
                    threadUUID: threadUUID,
                    workoutUUID: workoutUUID,
                    messagesJSON: messagesJSON,
                    createdAt: createdAt
                )
            }
            set {
                threadUUID = newValue.threadUUID
                workoutUUID = newValue.workoutUUID
                messagesJSON = newValue.messagesJSON
                createdAt = newValue.createdAt
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
typealias ChatThreadRecord = MaximizeSchemaV1.ChatThreadRecord
typealias PlanRecord = MaximizeSchemaV1.PlanRecord
typealias RestDayOverrideRecord = MaximizeSchemaV1.RestDayOverrideRecord
typealias AppSettingsRecord = MaximizeSchemaV1.AppSettingsRecord

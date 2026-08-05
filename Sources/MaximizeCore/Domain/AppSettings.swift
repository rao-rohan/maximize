import Foundation

/// A record that a day was spent as rest rather than counted as a miss (PRD §8
/// `rest_day_override`, D9).
///
/// Per A6 the conversion is automatic — the system spends the weekly budget on the
/// least-costly missed days — so `convertedFromMissed` is nearly always true today.
/// The flag is kept because a *planned* rest day marked explicitly by the user and an
/// *automatic* conversion of a missed day are different facts, and A6 warns the
/// heuristic may need revisiting if the calendar starts reading as too generous.
public struct RestDayOverride: Hashable, Sendable, Codable, Identifiable {
    public var id: CalendarDay { date }

    public let date: CalendarDay
    /// True when this day had a scheduled session that was missed and the weekly
    /// budget was spent on it; false when the day was simply recorded as rest.
    public let convertedFromMissed: Bool
    public let createdAt: Date

    public init(date: CalendarDay, convertedFromMissed: Bool, createdAt: Date) {
        self.date = date
        self.convertedFromMissed = convertedFromMissed
        self.createdAt = createdAt
    }
}

/// Discretionary rest days per week (D9's *N*).
///
/// A wrapper rather than a bare `Int` because "8 rest days a week" is nonsense and
/// this is a user-editable setting, i.e. exactly the value most likely to arrive
/// out of range.
public struct RestDayBudget: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    public static let permittedRange: ClosedRange<Int> = 0...7

    public let daysPerWeek: Int

    public init(daysPerWeek: Int) throws {
        guard RestDayBudget.permittedRange.contains(daysPerWeek) else {
            throw DomainError.outOfRange(
                field: "RestDayBudget.daysPerWeek",
                value: Double(daysPerWeek),
                lowerBound: Double(RestDayBudget.permittedRange.lowerBound),
                upperBound: Double(RestDayBudget.permittedRange.upperBound)
            )
        }
        self.daysPerWeek = daysPerWeek
    }

    private init(unchecked daysPerWeek: Int) {
        self.daysPerWeek = daysPerWeek
    }

    /// One discretionary rest day a week: generous enough to absorb a genuine
    /// off-day, tight enough that the calendar keeps meaning something (D9).
    public static let standard = RestDayBudget(unchecked: 1)

    public static func < (lhs: RestDayBudget, rhs: RestDayBudget) -> Bool {
        lhs.daysPerWeek < rhs.daysPerWeek
    }

    public var description: String { "\(daysPerWeek)/week" }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(daysPerWeek: container.decode(Int.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(daysPerWeek)
    }
}

/// Unit used when *showing* a distance. Storage is always metres (`Workout`,
/// `ScheduledSession`, `LongRunArc`); this only decides what the user reads.
public enum DistanceUnit: String, Hashable, Sendable, Codable, CaseIterable {
    case kilometers
    case miles

    public var metersPerUnit: Double {
        switch self {
        case .kilometers: return 1_000
        case .miles: return 1_609.344
        }
    }

    public func converted(fromMeters meters: Double) -> Double {
        meters / metersPerUnit
    }

    /// The inverse: metres for a figure already in this unit.
    ///
    /// Storage is always metres, so this exists for the one direction that runs the
    /// other way — a control the athlete drives in their own unit whose value has to be
    /// stored (MAX-080's plan editor, where a long run is stepped in whole miles or
    /// kilometres). Written here rather than as `value * unit.metersPerUnit` at the
    /// call site so the round trip through `converted(fromMeters:)` is one type's
    /// responsibility and cannot drift.
    public func meters(fromConverted value: Double) -> Double {
        value * metersPerUnit
    }

    /// The short label a tile or row prints next to a converted figure — "km" or "mi".
    /// Centralized here so every display site that shows a distance or a pace uses the
    /// same word for the same unit (`SummaryTileData`, `TrendTileData`,
    /// `WorkoutDisplayFormatting`); a caption spelled out independently in each of
    /// those would be exactly the kind of drift D2 exists to prevent, just for a label
    /// instead of a number.
    public var abbreviation: String {
        switch self {
        case .kilometers: return "km"
        case .miles: return "mi"
        }
    }
}

/// App appearance preference. The plan is dark-first (FR-4.3), so `.system` is not
/// the default.
public enum AppearancePreference: String, Hashable, Sendable, Codable, CaseIterable {
    case system
    case light
    case dark

    /// What this preference imposes on the app's color scheme, or `nil` to impose
    /// nothing (MAX-086).
    ///
    /// `MaximizeCore` cannot import SwiftUI (see CLAUDE.md, "thin shell, fat core"),
    /// so `ResolvedColorScheme?` is as far as the core goes; the app layer's one
    /// `.preferredColorScheme` call site does the last step of turning this into
    /// SwiftUI's `ColorScheme?`.
    ///
    /// `.system` deliberately maps to `nil`, not to a resolved case. `nil` is what
    /// tells SwiftUI "impose nothing, let the OS decide" — a different thing from
    /// picking a scheme. Mapping `.system` to `.dark` (the app's own default
    /// appearance, per `AppSettings.standard`) would silently override the OS for
    /// someone who deliberately asked to follow it.
    public var resolvedColorScheme: ResolvedColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// A platform-neutral stand-in for SwiftUI's `ColorScheme` (MAX-086). Exists only so
/// `AppearancePreference.resolvedColorScheme` can express "impose light" or "impose
/// dark" from within `MaximizeCore`, which may not import SwiftUI. The app layer maps
/// this one-to-one onto `ColorScheme` in the single place it calls
/// `.preferredColorScheme`.
public enum ResolvedColorScheme: Hashable, Sendable, Codable {
    case light
    case dark
}

/// User settings (PRD §8 `settings`).
///
/// The accessibility flags mirror OS settings the app must honour (FR-4.5, and
/// `reducesMotion` for FR-4.4's motion work). They live here as *app-level* overrides
/// so the core can reason about them in tests; the app layer is responsible for
/// seeding them from the system values, since reading those requires UIKit and the
/// core does not import it.
public struct AppSettings: Hashable, Sendable, Codable {
    public let restDayBudget: RestDayBudget
    public let distanceUnit: DistanceUnit
    public let appearance: AppearancePreference
    /// Forces solid chrome instead of Liquid Glass (FR-4.5).
    public let reducesTransparency: Bool
    public let increasesContrast: Bool
    /// Mirrors `UIAccessibility.isReduceMotionEnabled` (FR-4.4/4.5). No motion exists
    /// yet for this to gate (MAX-070 is a design-system completion pass, not a motion
    /// ticket) — it is here so whichever ticket adds the first animation has
    /// somewhere to read the preference from without importing UIKit into the core.
    public let reducesMotion: Bool

    public init(
        restDayBudget: RestDayBudget = .standard,
        distanceUnit: DistanceUnit = .miles,
        appearance: AppearancePreference = .dark,
        reducesTransparency: Bool = false,
        increasesContrast: Bool = false,
        reducesMotion: Bool = false
    ) {
        self.restDayBudget = restDayBudget
        self.distanceUnit = distanceUnit
        self.appearance = appearance
        self.reducesTransparency = reducesTransparency
        self.increasesContrast = increasesContrast
        self.reducesMotion = reducesMotion
    }

    public static let standard = AppSettings()
}

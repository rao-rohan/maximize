import SwiftUI
import MaximizeCore

/// A single row in the workout list — the minimum needed to reach FR-1.1's detail
/// view.
///
/// Deliberately plain: no score-band color here. FR-4.3 confines the three saturated
/// score-band colors to the calendar (D4/FR-3.2) and the verdict header (FR-1.1); this
/// list is neither, and giving it a fourth place to show green/amber/red would dilute
/// the one signal those colors are supposed to carry. Splits, tiles, and any richer
/// per-row summary are FR-1.5 / MAX-045's job, not this one.
struct WorkoutRow: View {
    let workout: Workout

    var body: some View {
        HStack(spacing: Spacing.compact) {
            VStack(alignment: .leading, spacing: Spacing.tight) {
                Text(WorkoutDisplayFormatting.dateAndTime.string(from: workout.start))
                    .font(.bodyCopy)
                    .foregroundStyle(Color.textPrimary)
                Text(WorkoutDisplayFormatting.describe(workout.activityType))
                    .font(.metricLabel)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer(minLength: Spacing.compact)
            if let distanceMeters = workout.distanceMeters {
                Text(WorkoutDisplayFormatting.distance(meters: distanceMeters))
                    .font(.metricLabel)
                    .foregroundStyle(Color.textSecondary)
            }
            // Outside a `List`, there is no built-in disclosure chevron — this row
            // sits in a plain `ScrollView` (see `WorkoutsView`) to stay on the design
            // system's flat content surfaces rather than `List`'s own chrome.
            Image(systemName: "chevron.right")
                .font(.metricLabel)
                .foregroundStyle(Color.textTertiary)
        }
        .contentSurface(.tile)
    }
}

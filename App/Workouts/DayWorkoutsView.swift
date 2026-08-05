import SwiftUI
import MaximizeCore

/// The door a day with **two or more** workouts opens onto (MAX-108).
///
/// A day the calendar shows as one cell can hold more than one recorded workout —
/// `ScoreCalendarDay.destination` is the core's answer for exactly this — and a day
/// with two runs is precisely the day an athlete most wants to compare. Backing out to
/// `WorkoutsView`'s date-sorted list and re-entering the second one is the interaction
/// that makes comparing not worth doing, so this view pages between them in place.
///
/// **Pushed, not sheeted.** The calendar lives inside `DashboardView`'s
/// `NavigationStack` already, the same stack a single-workout day pushes
/// `WorkoutDetailView` onto directly (see `ScoreCalendarView`'s
/// `ScoreCalendarDoorRoute`) — a two-workout day reaching a *different kind* of
/// transition than a one-workout day would be the inconsistency worth avoiding. This
/// view exists only because more than one screen needs to be reachable from one door;
/// each page inside it is the ordinary `WorkoutDetailView`, unmodified.
///
/// **A day with exactly one workout never reaches this view.** `ScoreCalendarView`
/// routes a single-element `.workouts` destination straight to `WorkoutDetailView`, so
/// the paging affordance below is never drawn for the common case — a control an
/// athlete cannot use is a bigger tell that something is missing than no control at
/// all.
struct DayWorkoutsView: View {
    /// Ascending by start time — the order `ScoreCalendar.resolve` already sorted
    /// them in, so page one is always the day's earliest workout.
    let workoutIDs: [UUID]

    @State private var selection: UUID

    init(workoutIDs: [UUID]) {
        self.workoutIDs = workoutIDs
        _selection = State(initialValue: workoutIDs.first ?? UUID())
    }

    private var selectedIndex: Int {
        workoutIDs.firstIndex(of: selection) ?? 0
    }

    var body: some View {
        TabView(selection: $selection) {
            ForEach(workoutIDs, id: \.self) { workoutID in
                WorkoutDetailView(workoutID: workoutID)
                    .tag(workoutID)
            }
        }
        // Page dots would repeat what the toolbar's "N of M" already says, and
        // numerals — not dots — are this app's own hierarchy channel (CLAUDE.md's UI
        // standard). `.never` keeps the swipe gesture the style still provides
        // without drawing a second, redundant indicator.
        .tabViewStyle(.page(indexDisplayMode: .never))
        .toolbar {
            // `workoutIDs.count > 1` is always true in practice — `ScoreCalendarView`
            // only ever routes here for two or more — but guarded rather than assumed,
            // the same defensiveness `door`'s empty-`.workouts` branch applies.
            if workoutIDs.count > 1 {
                pagingControls
            }
        }
    }

    /// Previous/next as ordinary buttons, not the page swipe alone — the ticket's own
    /// accessibility constraint: moving between a day's workouts must be reachable
    /// without a swipe gesture. Platform chrome (`.bottomBar`) rather than a
    /// hand-rolled floating control, so it is glassed by the system for free and
    /// degrades under Reduce Transparency the same way every other bar in the app
    /// does, with no bespoke handling here.
    @ToolbarContentBuilder
    private var pagingControls: some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            Button {
                step(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(selectedIndex == 0)
            .accessibilityLabel("Previous workout")

            Spacer()

            Text("\(selectedIndex + 1) of \(workoutIDs.count)")
                .font(.metricLabel)
                .foregroundStyle(Color.textSecondary)
                .monospacedDigit()
                .accessibilityLabel("Workout \(selectedIndex + 1) of \(workoutIDs.count)")

            Spacer()

            Button {
                step(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(selectedIndex == workoutIDs.count - 1)
            .accessibilityLabel("Next workout")
        }
    }

    private func step(by delta: Int) {
        let next = selectedIndex + delta
        guard workoutIDs.indices.contains(next) else { return }
        selection = workoutIDs[next]
    }
}

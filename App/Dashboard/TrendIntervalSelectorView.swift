import SwiftUI
import MaximizeCore

/// FR-3.1: the week / month / year selector for the dashboard.
///
/// Every decision about what interval results from a tap lives in
/// `TrendIntervalSelectionModel` (state, App layer) and `MaximizeCore.TrendInterval`
/// (the type) — this view only renders the current selection and forwards taps. See
/// CLAUDE.md's "a view should read as: observe state, render it, forward user intent."
///
/// MAX-083 removed the fourth segment and the date pickers under it. The visible
/// consequence is that the header is now the same shape in every state: a label with a
/// step-back and step-forward chevron either side, because all three shapes have a
/// previous and a next. Nothing on this control can be in an invalid state, so the error
/// line that used to sit under it is gone too.
///
/// `.contentSurface(.card)`, never glass (FR-4.2) — this is a data control, not chrome,
/// and it sits in the dashboard's content column alongside the calendar and tiles it
/// scopes.
///
/// **`docs/DESIGN-REVIEW.md` §4.2 wants this control out of the content column** and into
/// the navigation bar as a toolbar `Menu`, so the dashboard leads with a fact rather than
/// a control, with the custom-range pickers moved to a sheet. That is not this ticket, but
/// MAX-083 removes the obstacle it named: there are no pickers left to find a sheet for,
/// so what has to move is a three-way `Menu` and a label. MAX-081 has since given this
/// screen the `NavigationStack` that move needs.
struct TrendIntervalSelectorView: View {
    var model: TrendIntervalSelectionModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.compact) {
            kindPicker

            switch model.state {
            case .ready(let interval):
                header(for: interval)
            case .failed:
                // MAX-154: the sentence is `MaximizeCore`'s, so it is pinned by a test
                // and so it cannot drift from the fuller explanation `DashboardView`
                // now draws below this control in the same state.
                Text(FailureCopy.todaysDateUnresolved)
                    .font(.metricLabel)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .contentSurface(.card)
    }

    // MARK: - Shape picker

    /// Driven by `TrendIntervalKind.allCases`, in the core's own declaration order —
    /// ascending span, most detail first. A hand-written list here would be a second
    /// place the set of spans is stated, free to fall out of step with the presentation
    /// table that decides what each one renders.
    private var kindPicker: some View {
        Picker("Interval", selection: kindBinding) {
            ForEach(TrendIntervalKind.allCases, id: \.self) { kind in
                Text(TrendIntervalFormatting.name(for: kind)).tag(kind)
            }
        }
        .pickerStyle(.segmented)
    }

    private var kindBinding: Binding<TrendIntervalKind> {
        Binding(
            get: { model.state.interval?.kind ?? .week },
            set: { model.select($0) }
        )
    }

    // MARK: - Header

    private func header(for interval: TrendInterval) -> some View {
        let noun = TrendIntervalFormatting.name(for: interval.kind).lowercased()
        return HStack {
            Button {
                model.selectPrevious()
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Previous \(noun)")

            Spacer()

            Text(TrendIntervalFormatting.label(for: interval))
                .font(.sectionHeading)
                .foregroundStyle(Color.textPrimary)

            Spacer()

            Button {
                model.selectNext()
            } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel("Next \(noun)")
        }
    }
}

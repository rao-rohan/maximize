import SwiftUI
import MaximizeCore

/// FR-3.1: the week / month / custom selector for the dashboard.
///
/// Every decision about what interval results from a tap lives in
/// `TrendIntervalSelectionModel` (state, App layer) and `MaximizeCore.TrendInterval`
/// (the type, MAX-060) — this view only renders the current selection and forwards
/// taps. See CLAUDE.md's "a view should read as: observe state, render it, forward
/// user intent."
///
/// `.contentSurface(.card)`, never glass (FR-4.2) — this is a data control, not
/// chrome, and it sits in the dashboard's content column alongside the calendar and
/// tiles it scopes.
struct TrendIntervalSelectorView: View {
    var model: TrendIntervalSelectionModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.compact) {
            kindPicker

            switch model.state {
            case .ready(let interval):
                header(for: interval)
                if interval.kind == .custom {
                    customRangeControls
                }
            case .failed:
                Text("Couldn't resolve today's date.")
                    .font(.metricLabel)
                    .foregroundStyle(Color.textSecondary)
            }

            if let error = model.customRangeError {
                // The three score-band colors are reserved for the calendar and the
                // verdict header (FR-4.3, see `ScoreBandColors.swift`) — this app's
                // palette has no general-purpose "error" token, so a status message
                // here reads the same quiet way `SettingsView`'s does.
                Text(error)
                    .font(.metricLabel)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .contentSurface(.card)
    }

    // MARK: - Shape picker

    private var kindPicker: some View {
        Picker("Interval", selection: kindBinding) {
            Text("Week").tag(TrendIntervalKind.week)
            Text("Month").tag(TrendIntervalKind.month)
            Text("Custom").tag(TrendIntervalKind.custom)
        }
        .pickerStyle(.segmented)
    }

    private var kindBinding: Binding<TrendIntervalKind> {
        Binding(
            get: { model.state.interval?.kind ?? .week },
            set: { newKind in
                switch newKind {
                case .week: model.selectWeek()
                case .month: model.selectMonth()
                case .custom: model.selectCustom()
                }
            }
        )
    }

    // MARK: - Header: label, with navigation for week/month

    @ViewBuilder
    private func header(for interval: TrendInterval) -> some View {
        HStack {
            if interval.kind != .custom {
                Button {
                    model.selectPrevious()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("Previous \(interval.kind == .week ? "week" : "month")")
            }

            Spacer()

            Text(TrendIntervalFormatting.label(for: interval))
                .font(.sectionHeading)
                .foregroundStyle(Color.textPrimary)

            Spacer()

            if interval.kind != .custom {
                Button {
                    model.selectNext()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .accessibilityLabel("Next \(interval.kind == .week ? "week" : "month")")
            }
        }
    }

    // MARK: - Custom range controls

    private var customRangeControls: some View {
        VStack(alignment: .leading, spacing: Spacing.snug) {
            DatePicker(
                "Start",
                selection: Binding(
                    get: { model.customStartDate },
                    set: { model.updateCustomStart($0) }
                ),
                displayedComponents: .date
            )
            DatePicker(
                "End",
                selection: Binding(
                    get: { model.customEndDate },
                    set: { model.updateCustomEnd($0) }
                ),
                displayedComponents: .date
            )
        }
        .font(.bodyCopy)
        .foregroundStyle(Color.textPrimary)
    }
}

import SwiftUI
import MaximizeCore

/// §2.2, §6.2: the "Runs in this conversation" strip — a training thread's sheet, below
/// the transcript, naming every session `RunsStripData` says is in this thread's own
/// `TrainingContext`. Tapping a chip forwards `onSelectRun`, which `ChatSheet` turns into
/// a push to that run's own detail screen (§6.2: "no model involvement, nothing to
/// parse").
///
/// Nothing here decides what to show. `RunsStripData` (MaximizeCore) already resolved
/// each chip's label, their order, how many are shown and what the strip says when the
/// context is empty (CLAUDE.md's thin-shell rule) — this view only lays out what it is
/// handed and forwards a tap, the same "observe, render, forward intent" shape every
/// other view in this app follows.
///
/// `data == nil` renders nothing at all: the workout-thread case, where
/// `ChatModel.runsStripData` is nil by construction — there is nothing to strip, because
/// the sheet already sits on top of that run's own screen (§6.1).
///
/// `.contentSurface(.inset)` per chip, never glass: this is a data affordance sitting
/// over the transcript, not chrome (FR-4.2) — the same reasoning the composer's own
/// `TextField` well follows two rows below it.
struct RunsStripView: View {
    let data: RunsStripData?
    let onSelectRun: (UUID) -> Void

    var body: some View {
        if let data {
            VStack(alignment: .leading, spacing: Spacing.tight) {
                // A fixed caption with no data dependency, so it stays here rather than
                // in `MaximizeCore` — see `RunsStripCopy`'s own note on the split.
                Text("Runs in this conversation")
                    .font(.metricLabel)
                    .foregroundStyle(Color.textSecondary)

                content(for: data)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .screenMargins()
            .padding(.top, Spacing.snug)
            .padding(.bottom, Spacing.snug)
        }
    }

    @ViewBuilder
    private func content(for data: RunsStripData) -> some View {
        switch data {
        case let .empty(reason):
            Text(RunsStripCopy.text(for: reason))
                .font(.bodyCopy)
                .foregroundStyle(Color.textSecondary)

        case let .chips(chips, omittedCount):
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.snug) {
                    ForEach(chips) { chip in
                        chipButton(chip)
                    }
                    if omittedCount > 0 {
                        // Not a button: there is nowhere for a tap on "+N more" to go —
                        // §6.2 offers no thread-scoped list of every session, only a tap
                        // through to one at a time. Read, not interactive.
                        Text(RunsStripCopy.omittedCountLabel(omittedCount))
                            .font(.metricLabel)
                            .foregroundStyle(Color.textTertiary)
                            .lineLimit(1)
                            .padding(.horizontal, Spacing.snug)
                            .accessibilityLabel(
                                omittedCount == 1
                                    ? "1 more run in this conversation, not shown"
                                    : "\(omittedCount) more runs in this conversation, not shown"
                            )
                    }
                }
            }
        }
    }

    private func chipButton(_ chip: RunsStripData.Chip) -> some View {
        Button {
            onSelectRun(chip.workoutID)
        } label: {
            Text(chip.label)
                .font(.metricLabel)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .contentSurface(.inset)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens this run")
    }
}

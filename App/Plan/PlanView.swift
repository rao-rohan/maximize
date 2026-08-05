import SwiftUI
import MaximizeCore

/// The plan tab (MAX-102, A15): a read-only view of the plan currently in effect, with
/// version history underneath.
///
/// ## Why a screen, and why read-only
///
/// The plan is the reference every score in this app is measured against, and until
/// now it was legible only while being edited — `PlanAuthoringView` shows a *draft*,
/// never a saved version. Chat (A9) will answer plan questions too, but "what is my
/// plan" is a lookup against the athlete's own stored configuration, not a question
/// worth a model call. This screen answers it directly.
///
/// **This screen writes nothing.** It does not edit a value, does not create a
/// version, does not convert a rest day. The one thing it can do is hand off to the
/// screen that already owns writing: `PlanAuthoringView` (MAX-080). Everything a row
/// says, which version counts as current, and which arc week is "this week" are
/// `PlanDisplayData`'s decisions, made in `MaximizeCore` under test — see that type's
/// own documentation. This view only lays already-decided values out.
///
/// ## Mounting
///
/// This is a tab root, not a screen pushed from another one — it owns its own
/// `NavigationStack`, matching `WorkoutsView` and `DashboardView`. Wiring it into
/// `RootTabView` is a separate ticket's file to touch; a suggested label and SF Symbol
/// are in this ticket's PR description.
struct PlanView: View {
    @State private var model = PlanViewModel()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Plan")
                .contentSurface(.screen)
                .navigationDestination(for: PlanVersion.self) { version in
                    PlanVersionDetailView(version: version)
                }
                .settingsToolbarItem()
        }
        .task { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            Text("Couldn't load the plan.")
                .font(.metricLabel)
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(.notAuthored, _):
            emptyState
        case let .loaded(.authored(authored), distanceUnit):
            ScrollView {
                VStack(alignment: .leading, spacing: LayoutMetrics.sectionSpacing) {
                    PlanDetailSections(detail: authored.viewing, distanceUnit: distanceUnit)
                    reviseSection
                    historySection(authored.history)
                }
                .screenMargins()
                .padding(.vertical, Spacing.roomy)
            }
        }
    }

    // MARK: - No plan authored yet

    /// The tab's first impression on a fresh install — reuses `PlanAuthoringFormatting`'s
    /// own copy for "no plan authored" rather than a second telling of the same fact, so
    /// this screen and the authoring screen never drift on the one sentence that matters
    /// most: nothing is scoring yet.
    private var emptyState: some View {
        VStack(spacing: Spacing.regular) {
            Text(PlanAuthoringFormatting.describe(.firstPlan))
                .font(.bodyCopy)
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.center)

            Text(PlanAuthoringFormatting.explain(.firstPlan))
                .font(.metricLabel)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)

            NavigationLink {
                PlanAuthoringView()
            } label: {
                Text("Author a plan")
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accent)
        }
        .screenMargins()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // MARK: - Revising

    /// The one write this screen ever leads to, and deliberately a full section rather
    /// than a toolbar icon: revising a plan is an infrequent, deliberate act with real
    /// consequences (a new version, D1), not a peripheral utility like Settings — it
    /// earns the room to say, in the athlete's own words, what tapping it actually does.
    /// A toolbar pencil would read as "edit this record"; this reads as what D1 says it
    /// is: authoring the next version, leaving this one exactly as scored.
    @ViewBuilder
    private var reviseSection: some View {
        VStack(alignment: .leading, spacing: Spacing.compact) {
            Text("Revise this plan")
                .font(.sectionHeading)
                .foregroundStyle(Color.textPrimary)

            Text(
                "Changing anything opens a new plan version to author. This one stays exactly "
                    + "as it is — every score already recorded keeps the plan it was scored under."
            )
            .font(.metricLabel)
            .foregroundStyle(Color.textSecondary)

            NavigationLink {
                PlanAuthoringView()
            } label: {
                Text("Author a revision")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentSurface(.card)
    }

    // MARK: - Version history

    private func historySection(_ history: [PlanDisplayData.VersionSummary]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.compact) {
            Text("Version history")
                .font(.sectionHeading)
                .foregroundStyle(Color.textPrimary)

            VStack(alignment: .leading, spacing: Spacing.regular) {
                ForEach(history) { summary in
                    if summary.isViewing {
                        historyRow(summary)
                    } else {
                        NavigationLink(value: summary.version) {
                            historyRow(summary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentSurface(.card)
    }

    private func historyRow(_ summary: PlanDisplayData.VersionSummary) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.tight) {
                Text(PlanFormatting.versionTitle(summary.version))
                    .font(.bodyCopy)
                    .foregroundStyle(Color.textPrimary)
                Text(
                    PlanFormatting.effectiveRangeLine(
                        effectiveFrom: summary.effectiveFrom,
                        effectiveThrough: summary.effectiveThrough
                    )
                )
                .font(.metricLabel)
                .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            if summary.isViewing {
                Text(summary.isCurrent ? "Current" : "Viewing")
                    .font(.metricLabel)
                    .foregroundStyle(Color.textSecondary)
            } else if summary.isCurrent {
                Text("Current")
                    .font(.metricLabel)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .contentShape(Rectangle())
    }
}

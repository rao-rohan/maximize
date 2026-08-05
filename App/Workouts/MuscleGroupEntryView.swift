import SwiftUI
import MaximizeCore

/// The one field the athlete fills in by hand: which muscle groups a strength session
/// worked (A22, MAX-145).
///
/// ## What this view decides: nothing
///
/// Whether the section appears, what it says in each state, whether the Save button does
/// anything, and what the selection becomes are all `MaximizeCore`'s answers —
/// `MuscleGroupEntryData`, `MuscleGroupEntryCopy` and `MuscleGroupSelection`, each unit
/// tested. This file lays them out and forwards the athlete's intent, which is the whole
/// of a view's job under CLAUDE.md's thin-shell rule. In particular it never asks
/// "is this a lift?" for itself: that question is A22's narrowness, and it is answered
/// once, in the core.
///
/// ## Why the picker is a sheet with a Save, and not six inline toggles
///
/// Entries are additive and never overwritten (see `MuscleGroupEntry`), so every write
/// is a permanent record of something the athlete said. Six inline toggles would write
/// six records to express one thought. A sheet collects the whole answer and records it
/// once, on an explicit confirmation — and the confirmation is also what makes
/// `MuscleGroupSelection.canSave`'s two rules ("not empty", "not the same as last time")
/// something the athlete can see rather than something the app enforces silently.
///
/// The sheet takes the system's own chrome and the platform's `List` of `Toggle` rows:
/// each is a switch VoiceOver already names and operates, and each scales with Dynamic
/// Type without this file specifying a single dimension. Nothing here re-glasses a
/// surface the OS already glasses (MAX-040).
struct MuscleGroupEntryView: View {
    let data: MuscleGroupEntryData

    /// Forwarded intent: the athlete confirmed this set. The detail model turns it into
    /// a record; this view does not know what storage is.
    let onSave: (Set<MuscleGroup>) -> Void

    @State private var isPickerPresented = false

    var body: some View {
        if data.isShown {
            VStack(alignment: .leading, spacing: Spacing.compact) {
                Text(MuscleGroupEntryCopy.sectionTitle)
                    .font(.sectionHeading)
                    .foregroundStyle(Color.textPrimary)

                // One accessibility element, so the prompt and the reason for it are
                // read as a single sentence rather than as two unrelated labels — the
                // treatment `VerdictHeaderView` gives its own scoreless copy.
                VStack(alignment: .leading, spacing: Spacing.tight) {
                    Text(data.headline)
                        .font(.metricSecondary)
                        .foregroundStyle(Color.textPrimary)
                    Text(data.detail)
                        .font(.metricLabel)
                        .foregroundStyle(Color.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(data.accessibilityLabel)

                Button(data.actionTitle) { isPickerPresented = true }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
            }
            .contentSurface(.card)
            .sheet(isPresented: $isPickerPresented) {
                MuscleGroupPickerSheet(selection: data.selection, onSave: onSave)
            }
        }
    }
}

/// The picker itself. Presented as a sheet, which is chrome the system supplies.
private struct MuscleGroupPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var selection: MuscleGroupSelection
    private let onSave: (Set<MuscleGroup>) -> Void

    init(selection: MuscleGroupSelection, onSave: @escaping (Set<MuscleGroup>) -> Void) {
        _selection = State(initialValue: selection)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    // `MuscleGroup.allCases` in its declared order — the same order the
                    // summary reads in, so what the athlete ticks and what they are told
                    // they ticked cannot disagree.
                    ForEach(MuscleGroup.allCases, id: \.self) { group in
                        Toggle(
                            group.displayName,
                            isOn: Binding(
                                get: { selection.contains(group) },
                                set: { _ in selection.toggle(group) }
                            )
                        )
                    }
                } header: {
                    // `.textCase(nil)`: this is a sentence about the session, not a
                    // heading, and the platform's default upper-casing would make
                    // "Chest and back" read as shouting.
                    Text(selection.summary).textCase(nil)
                } footer: {
                    Text(MuscleGroupEntryCopy.editorFooter)
                }
            }
            .navigationTitle(MuscleGroupEntryCopy.editorTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(MuscleGroupEntryCopy.editorCancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(MuscleGroupEntryCopy.editorSave) {
                        onSave(selection.groups)
                        dismiss()
                    }
                    // Empty is "I trained nothing", which this record cannot say, and an
                    // unchanged set would append a record that says nothing new. Both
                    // rules live in `MuscleGroupSelection`.
                    .disabled(!selection.canSave)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

//
//  LogSessionView.swift
//  AI-Trainer
//
//  Post-workout logging: done/partial/skipped, optional free text, and
//  -- only when today's session type plausibly matches an exercise
//  with real lift history (server/log_session.py's TYPE_KEYWORDS) --
//  a prompt for that exercise's numbers. A swim or rest day never
//  shows a strength-number prompt; a legs day with squat history
//  does.

import Combine
import SwiftUI

struct LiftInput {
    var weight = ""
    var reps = ""
    var sets = ""
    var note = ""

    var isEmpty: Bool {
        weight.trimmingCharacters(in: .whitespaces).isEmpty
            && reps.trimmingCharacters(in: .whitespaces).isEmpty
            && sets.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

@MainActor
final class LogSessionViewModel: ObservableObject {
    @Published var context: LogContextResponse?
    @Published var isLoadingContext = false
    @Published var loadErrorMessage: String?

    @Published var status = "done"
    @Published var notes = ""
    @Published var liftInputs: [String: LiftInput] = [:]

    @Published var isSubmitting = false
    @Published var submitErrorMessage: String?
    @Published var didSubmit = false
    @Published var recordedLifts: [RecordedLift] = []

    private let client = APIClient()

    /// Recorded lifts that weren't in what the athlete actually typed
    /// into a field -- these came from lift_parser.py reading the
    /// notes instead, so the confirmation screen calls them out
    /// explicitly rather than presenting them as if they'd been typed.
    var autoPickedUpLifts: [RecordedLift] {
        let typedNames = Set(
            liftInputs.compactMap { name, input in input.isEmpty ? nil : name.lowercased() }
        )
        return recordedLifts.filter { !typedNames.contains($0.exerciseName.lowercased()) }
    }

    func loadContext() async {
        isLoadingContext = true
        loadErrorMessage = nil
        do {
            context = try await client.fetchLogContext()
        } catch {
            loadErrorMessage = error.localizedDescription
        }
        isLoadingContext = false
    }

    func input(for exercise: String) -> LiftInput {
        liftInputs[exercise] ?? LiftInput()
    }

    func updateInput(for exercise: String, _ update: (inout LiftInput) -> Void) {
        var current = liftInputs[exercise] ?? LiftInput()
        update(&current)
        liftInputs[exercise] = current
    }

    func submit() async {
        isSubmitting = true
        submitErrorMessage = nil

        let lifts: [LiftEntry] = liftInputs.compactMap { name, input in
            guard !input.isEmpty else { return nil }
            return LiftEntry(
                exerciseName: name,
                weight: Double(input.weight),
                reps: Int(input.reps),
                sets: Int(input.sets),
                note: input.note.isEmpty ? nil : input.note
            )
        }

        do {
            let result = try await client.submitLog(LogSessionRequest(
                date: nil,
                status: status,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil : notes,
                lifts: lifts
            ))
            recordedLifts = result.liftsRecorded
            didSubmit = true
        } catch {
            submitErrorMessage = error.localizedDescription
        }
        isSubmitting = false
    }
}

struct LogSessionView: View {
    @StateObject private var viewModel = LogSessionViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoadingContext {
                    ProgressView("Loading today's session…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.loadErrorMessage {
                    VStack(spacing: 12) {
                        Text(error).foregroundStyle(.secondary)
                        Button("Try again") { Task { await viewModel.loadContext() } }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.didSubmit {
                    confirmation
                } else if let context = viewModel.context {
                    form(for: context)
                } else {
                    Color.clear
                }
            }
            .navigationTitle(viewModel.didSubmit ? "Logged" : "Log Session")
            .toolbar {
                if viewModel.didSubmit {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                } else {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            Task { await viewModel.submit() }
                        }
                        .disabled(viewModel.isSubmitting || viewModel.context == nil)
                    }
                }
            }
            .task { await viewModel.loadContext() }
        }
    }

    // Shown right after a successful save instead of dismissing
    // immediately -- otherwise a lift picked up from voice notes
    // rather than a typed field would vanish into the log silently,
    // which reads as a black box rather than something the athlete
    // can trust and correct if it got something wrong.
    @ViewBuilder
    private var confirmation: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Logged", systemImage: "checkmark.circle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.accent)

            if !viewModel.recordedLifts.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(viewModel.recordedLifts.enumerated()), id: \.offset) { _, lift in
                        liftSummaryRow(lift)
                    }
                }
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.background)
    }

    private func liftSummaryRow(_ lift: RecordedLift) -> some View {
        let isAutoPickedUp = viewModel.autoPickedUpLifts.contains {
            $0.exerciseName.lowercased() == lift.exerciseName.lowercased()
        }
        return VStack(alignment: .leading, spacing: 2) {
            Text(lift.exerciseName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
            Text(liftSummaryText(lift))
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            if isAutoPickedUp {
                Text("picked up from your notes")
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
            }
        }
    }

    private func liftSummaryText(_ lift: RecordedLift) -> String {
        var parts: [String] = []
        if let weight = lift.weight { parts.append("\(weight.formatted())kg") }
        if let sets = lift.sets, let reps = lift.reps {
            parts.append("\(sets) × \(reps)")
        } else if let reps = lift.reps {
            parts.append("\(reps) reps")
        }
        return parts.isEmpty ? "logged" : parts.joined(separator: ", ")
    }

    @ViewBuilder
    private func form(for context: LogContextResponse) -> some View {
        Form {
            Section {
                Text(context.type.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.headline)
                if let summary = context.plannedSummary {
                    Text(summary).foregroundStyle(.secondary)
                }
            }

            Section("How did it go?") {
                Picker("Status", selection: $viewModel.status) {
                    Text("Done").tag("done")
                    Text("Partial").tag("partial")
                    Text("Skipped").tag("skipped")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section("Notes (optional)") {
                // Typing a full summary is friction most people won't
                // bother with -- voice is the realistic way this gets
                // used ("did it, squats felt good, hit 105 for 3x5").
                // Same VoiceInputButton as Today/Coach, no new plumbing.
                HStack(alignment: .top) {
                    TextField(
                        "\"did it\", \"swapped X for Y\", \"skipped, out for drinks\"…",
                        text: $viewModel.notes, axis: .vertical
                    )
                    .lineLimit(2...5)
                    VoiceInputButton(text: $viewModel.notes)
                }
            }

            if !context.relevantExercises.isEmpty {
                ForEach(context.relevantExercises) { exercise in
                    Section(exercise.name) {
                        if let hint = lastTimeHint(exercise) {
                            Text(hint)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        exerciseFields(for: exercise.name)
                    }
                }
            }

            if let error = viewModel.submitErrorMessage {
                Section {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
    }

    @ViewBuilder
    private func exerciseFields(for exercise: String) -> some View {
        let input = viewModel.input(for: exercise)
        HStack {
            TextField("Weight", text: Binding(
                get: { input.weight },
                set: { newValue in
                    viewModel.updateInput(for: exercise) { $0.weight = newValue }
                }
            ))
            .keyboardType(.decimalPad)
            Text("kg")
            Divider()
            TextField("Sets", text: Binding(
                get: { input.sets },
                set: { newValue in
                    viewModel.updateInput(for: exercise) { $0.sets = newValue }
                }
            ))
            .keyboardType(.numberPad)
            Text("×")
            TextField("Reps", text: Binding(
                get: { input.reps },
                set: { newValue in
                    viewModel.updateInput(for: exercise) { $0.reps = newValue }
                }
            ))
            .keyboardType(.numberPad)
        }
    }

    private func lastTimeHint(_ exercise: RelevantExercise) -> String? {
        guard let weight = exercise.lastWeight else { return nil }
        var parts = ["Last time (\(exercise.lastDate ?? "")): \(weight.formatted())kg"]
        if let sets = exercise.lastSets, let reps = exercise.lastReps {
            parts.append("\(sets) × \(reps)")
        }
        return parts.joined(separator: ", ")
    }
}

#Preview {
    LogSessionView()
}

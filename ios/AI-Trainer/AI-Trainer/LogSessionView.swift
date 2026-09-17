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

    private let client = APIClient()

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
            _ = try await client.submitLog(LogSessionRequest(
                date: nil,
                status: status,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil : notes,
                lifts: lifts
            ))
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
                } else if let context = viewModel.context {
                    form(for: context)
                } else {
                    Color.clear
                }
            }
            .navigationTitle("Log Session")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await viewModel.submit()
                            if viewModel.didSubmit { dismiss() }
                        }
                    }
                    .disabled(viewModel.isSubmitting || viewModel.context == nil)
                }
            }
            .task { await viewModel.loadContext() }
        }
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

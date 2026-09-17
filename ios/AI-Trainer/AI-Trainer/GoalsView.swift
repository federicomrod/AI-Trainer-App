//
//  GoalsView.swift
//  AI-Trainer
//
//  View and edit the profile's goals and their priority order. A
//  simple reorderable list, not a dashboard -- list order IS priority
//  order (CLAUDE.md's profile table has no separate priority field),
//  so dragging a goal to the top is the entire "set priority" UI.

import Combine
import SwiftUI

@MainActor
final class GoalsViewModel: ObservableObject {
    @Published var goals: [String] = []
    @Published var isLoading = false
    @Published var loadErrorMessage: String?

    @Published var isSaving = false
    @Published var saveErrorMessage: String?
    @Published var didSave = false

    private let client = APIClient()

    func load() async {
        isLoading = true
        loadErrorMessage = nil
        do {
            goals = try await client.fetchGoals().goals
        } catch {
            loadErrorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func save() async {
        isSaving = true
        saveErrorMessage = nil
        do {
            goals = try await client.saveGoals(goals).goals
            didSave = true
        } catch {
            saveErrorMessage = error.localizedDescription
        }
        isSaving = false
    }
}

struct GoalsView: View {
    @StateObject private var viewModel = GoalsViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var newGoal = ""

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading goals…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.loadErrorMessage {
                    VStack(spacing: 12) {
                        Text(error).foregroundStyle(.secondary)
                        Button("Try again") { Task { await viewModel.load() } }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    list
                }
            }
            .navigationTitle("Goals")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await viewModel.save()
                            if viewModel.didSave { dismiss() }
                        }
                    }
                    .disabled(viewModel.isSaving)
                }
            }
            .task { await viewModel.load() }
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            List {
                Section("In priority order — first matters most") {
                    ForEach(viewModel.goals, id: \.self) { goal in
                        Text(goal)
                    }
                    .onMove { viewModel.goals.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { viewModel.goals.remove(atOffsets: $0) }
                }
                if let error = viewModel.saveErrorMessage {
                    Text(error).foregroundStyle(.red)
                }
            }
            #if os(iOS)
            // EditMode is iOS-only (this project's scheme can offer
            // "My Mac" as a destination automatically on Apple
            // Silicon); always-active edit mode is what makes the
            // drag handles and delete controls show without a
            // separate Edit button, since this whole screen's purpose
            // is editing.
            .environment(\.editMode, .constant(.active))
            #endif

            HStack {
                TextField("Add a goal…", text: $newGoal)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    let trimmed = newGoal.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    viewModel.goals.append(trimmed)
                    newGoal = ""
                }
                .disabled(newGoal.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
    }
}

#Preview {
    GoalsView()
}

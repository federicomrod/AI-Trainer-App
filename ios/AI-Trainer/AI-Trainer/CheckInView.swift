//
//  CheckInView.swift
//  AI-Trainer
//
//  Sleep, energy, soreness by region, an optional note -- exactly what
//  server/checkin.py stores, nothing more. Presented as a sheet from
//  Today rather than a permanent tab, since a check-in is a once-a-day
//  action, not a screen to browse.

import Combine
import SwiftUI

private let soreRegions = ["Legs", "Shoulders", "Back", "Arms"]
private let sorenessLevels = ["None", "Low", "Moderate", "High"]

@MainActor
final class CheckInViewModel: ObservableObject {
    @Published var sleep = "normal"
    @Published var energy = 3
    @Published var soreness: [String: String] = [:]  // region -> level, "None" omitted
    @Published var note = ""

    @Published var isSubmitting = false
    @Published var errorMessage: String?
    @Published var didSubmit = false

    private let client = APIClient()

    func level(for region: String) -> String {
        let saved = soreness[region.lowercased()]
        return saved.map { $0.capitalized } ?? "None"
    }

    func setLevel(_ level: String, for region: String) {
        let key = region.lowercased()
        if level == "None" {
            soreness.removeValue(forKey: key)
        } else {
            soreness[key] = level.lowercased()
        }
    }

    func submit() async {
        isSubmitting = true
        errorMessage = nil
        do {
            _ = try await client.submitCheckIn(CheckInRequest(
                sleep: sleep,
                energy: energy,
                soreness: soreness,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil : note
            ))
            didSubmit = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isSubmitting = false
    }
}

struct CheckInView: View {
    @StateObject private var viewModel = CheckInViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Sleep") {
                    Picker("Sleep", selection: $viewModel.sleep) {
                        Text("Poor").tag("poor")
                        Text("Normal").tag("normal")
                        Text("Good").tag("good")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Section("Energy: \(viewModel.energy)/5") {
                    Slider(
                        value: Binding(
                            get: { Double(viewModel.energy) },
                            set: { viewModel.energy = Int($0.rounded()) }
                        ),
                        in: 1...5, step: 1
                    )
                }

                Section("Soreness") {
                    ForEach(soreRegions, id: \.self) { region in
                        Picker(region, selection: Binding(
                            get: { viewModel.level(for: region) },
                            set: { viewModel.setLevel($0, for: region) }
                        )) {
                            ForEach(sorenessLevels, id: \.self) { level in
                                Text(level).tag(level)
                            }
                        }
                    }
                }

                Section("Note (optional)") {
                    TextField("Anything else worth mentioning…", text: $viewModel.note, axis: .vertical)
                        .lineLimit(2...5)
                }

                if let error = viewModel.errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Check In")
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
                    .disabled(viewModel.isSubmitting)
                }
            }
        }
    }
}

#Preview {
    CheckInView()
}

//
//  OnboardingView.swift
//  AI-Trainer
//
//  First run: the handful of things the coach can't work without.
//  Per CLAUDE.md the briefing is where quality lives, and the PROFILE
//  section of it comes from here -- goals in priority order,
//  availability, equipment, and what a normal week looks like.
//
//  Deliberately short. This is for someone who already trains and
//  knows what an RDL is; it asks what it actually needs and gets out
//  of the way. Everything here can be changed later (Goals, Settings),
//  and the coach learns the rest by being told, so nothing on this
//  screen is a commitment.

import Combine
import SwiftUI

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published var goalsText = ""
    @Published var availability = ""
    @Published var sessionLength = "60"
    @Published var equipment = ""
    @Published var injuries = ""
    @Published var experience = "Intermediate"
    /// weekday -> session type, only for days that train.
    @Published var routine: [String: String] = [:]

    @Published var isSaving = false
    @Published var errorMessage: String?

    private let client = APIClient()

    /// One goal per line, in priority order -- list order is the
    /// priority, exactly as CLAUDE.md's profile table stores it.
    var goals: [String] {
        goalsText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var canSave: Bool { !goals.isEmpty && !isSaving }

    func save() async -> Bool {
        guard canSave else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let profile = ProfilePayload(
            goals: goals,
            weeklyAvailability: availability.isEmpty ? nil : availability,
            typicalSessionLengthMin: Int(sessionLength),
            equipment: equipment.isEmpty ? nil : equipment,
            preferredExercises: [],
            dislikedExercises: [],
            injuries: injuries.isEmpty ? nil : injuries,
            experienceLevel: experience
        )
        do {
            _ = try await client.submitOnboarding(
                OnboardingRequest(profile: profile, routine: routine)
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

struct OnboardingView: View {
    /// Called once setup has actually been stored, so the app can move
    /// on to the real screens.
    let onComplete: () -> Void

    @StateObject private var viewModel = OnboardingViewModel()

    private let weekdays = [
        "monday", "tuesday", "wednesday", "thursday", "friday",
        "saturday", "sunday",
    ]
    // Matches the sessions.type CHECK constraint in server/db.py.
    private let sessionTypes = [
        "push", "pull", "legs", "ride", "run", "swim", "intervals", "rest",
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    goalsSection
                    practicalSection
                    routineSection
                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    saveButton
                }
                .padding()
            }
            .appBackground()
            .scrollContentBackground(.hidden)
            .navigationTitle("Set up")
        }
    }

    private var header: some View {
        Text("A few things the coach weighs every decision against. All of it can change later.")
            .font(.callout)
            .foregroundStyle(Theme.textSecondary)
    }

    private var goalsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Goals")
                .font(Theme.rounded(.headline, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text("One per line, most important first.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            TextField(
                "Keep getting stronger\nBuild cycling endurance",
                text: $viewModel.goalsText,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .lineLimit(3...6)
            .padding()
            .flatCard()
            .foregroundStyle(Theme.textPrimary)
        }
    }

    private var practicalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Practicalities")
                .font(Theme.rounded(.headline, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            field("Availability", "5-6 days/week, mornings", $viewModel.availability)
            field("Typical session length (min)", "60", $viewModel.sessionLength)
            field("Equipment / gym", "Full gym, road bike, pool 2x/week", $viewModel.equipment)
            field("Injuries or limitations", "Leave blank if none", $viewModel.injuries)
            field("Experience level", "Intermediate", $viewModel.experience)
        }
    }

    private func field(_ label: String, _ placeholder: String, _ binding: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            TextField(placeholder, text: binding)
                .textFieldStyle(.plain)
                .padding(10)
                .flatCard(radius: Theme.controlRadius)
                .foregroundStyle(Theme.textPrimary)
        }
    }

    // Only the remaining days of this week get planned from this (see
    // server/onboarding.py) -- the days already gone aren't back-filled
    // with sessions that never happened.
    private var routineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your usual week")
                .font(Theme.rounded(.headline, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text("Optional. Only the rest of this week gets planned from it — past days stay empty until you log them.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            ForEach(weekdays, id: \.self) { day in
                HStack {
                    Text(day.capitalized)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Picker(day, selection: binding(for: day)) {
                        Text("—").tag("")
                        ForEach(sessionTypes, id: \.self) { type in
                            Text(type.capitalized).tag(type)
                        }
                    }
                    .labelsHidden()
                    .tint(Theme.accent)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .flatCard(radius: Theme.controlRadius)
            }
        }
    }

    private func binding(for day: String) -> Binding<String> {
        Binding(
            get: { viewModel.routine[day] ?? "" },
            set: { newValue in
                if newValue.isEmpty {
                    viewModel.routine.removeValue(forKey: day)
                } else {
                    viewModel.routine[day] = newValue
                }
            }
        )
    }

    private var saveButton: some View {
        Button {
            Task {
                if await viewModel.save() { onComplete() }
            }
        } label: {
            HStack {
                Spacer()
                if viewModel.isSaving {
                    ProgressView().tint(Theme.background)
                } else {
                    Text("Start training")
                        .font(Theme.rounded(.headline, weight: .bold))
                }
                Spacer()
            }
            .padding()
            .background(
                viewModel.canSave ? Theme.accent : Theme.cardElevated,
                in: RoundedRectangle(cornerRadius: Theme.controlRadius)
            )
            .foregroundStyle(viewModel.canSave ? Theme.background : Theme.textSecondary)
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canSave)
    }
}

#Preview {
    OnboardingView(onComplete: {})
}

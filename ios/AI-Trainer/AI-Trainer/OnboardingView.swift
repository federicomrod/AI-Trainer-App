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
    @Published var sessionLength = 60
    /// Picked from `OnboardingView.equipmentOptions`.
    @Published var equipment: Set<String> = []
    /// Anything the chips don't cover.
    @Published var otherEquipment = ""
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

    /// Stored as one readable line -- the profile's `equipment` column is
    /// plain text, and it reads straight into the coach's briefing, so
    /// "Full gym, Road bike, Pool" is exactly the right shape. Kept in the
    /// options' display order rather than tap order.
    var equipmentSummary: String? {
        var parts = OnboardingView.equipmentOptions.filter(equipment.contains)
        let other = otherEquipment.trimmingCharacters(in: .whitespacesAndNewlines)
        if !other.isEmpty { parts.append(other) }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    func save() async -> Bool {
        guard canSave else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let profile = ProfilePayload(
            goals: goals,
            weeklyAvailability: availability.isEmpty ? nil : availability,
            typicalSessionLengthMin: sessionLength,
            equipment: equipmentSummary,
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
            sessionLengthStepper
            equipmentChips
            field("Injuries or limitations", "Leave blank if none", $viewModel.injuries)
            experiencePicker
        }
    }

    static let experienceLevels = ["Beginner", "Intermediate", "Advanced"]

    /// What the plan can actually be built around. "Other" covers the
    /// rest in free text.
    static let equipmentOptions = [
        "Full gym", "Home dumbbells", "Road bike", "Indoor bike trainer",
        "Pool", "Open water", "Running track",
    ]

    private var experiencePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Experience level")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            Picker("Experience level", selection: $viewModel.experience) {
                ForEach(Self.experienceLevels, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    // A stepper, not a keyboard: minutes only ever move in sensible
    // steps, and there's no way to type something the coach can't use.
    private var sessionLengthStepper: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Typical session length")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            Stepper(value: $viewModel.sessionLength, in: 20...180, step: 5) {
                Text("\(viewModel.sessionLength) min")
                    .font(Theme.rounded(.body, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .flatCard(radius: Theme.controlRadius)
        }
    }

    private var equipmentChips: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Equipment you can use")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(Self.equipmentOptions, id: \.self) { option in
                    chip(option)
                }
            }
            TextField("Other (optional)", text: $viewModel.otherEquipment)
                .textFieldStyle(.plain)
                .padding(10)
                .flatCard(radius: Theme.controlRadius)
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private func chip(_ option: String) -> some View {
        let selected = viewModel.equipment.contains(option)
        return Button {
            if selected { viewModel.equipment.remove(option) } else { viewModel.equipment.insert(option) }
        } label: {
            HStack(spacing: 4) {
                if selected { Image(systemName: "checkmark").font(.caption.weight(.bold)) }
                Text(option).font(.subheadline).lineLimit(1).minimumScaleFactor(0.85)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(selected ? Theme.accent : Theme.card, in: Capsule())
            .foregroundStyle(selected ? Theme.background : Theme.textPrimary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
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

//
//  TodayView.swift
//  AI-Trainer
//
//  M1's first screen: open the app, see today's session and why, and
//  optionally tell the coach something that might change it. The
//  `reply` text from the backend is already fully written in the
//  coach's voice (render.py did that) -- this view just displays it,
//  the same way the CLI prints it to a terminal. It does not
//  re-implement any formatting/voice logic of its own.

import Combine
import SwiftUI

@MainActor
final class TodayViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var response: TurnResponse?
    @Published var errorMessage: String?
    @Published var messageDraft = ""

    private let client = APIClient()

    func loadToday() async {
        await send(message: "")
    }

    func sendDraft() async {
        let text = messageDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messageDraft = ""
        await send(message: text)
    }

    private func send(message: String) async {
        isLoading = true
        errorMessage = nil
        do {
            let result = try await client.turn(message: message)
            response = result
            // The backend can succeed at the HTTP level but still
            // report a failure inside the JSON (planner_error when the
            // model call itself failed, validation_error when the
            // decision was rejected) -- surface that the same way as a
            // network failure, since neither case has anything safe to
            // show as "today's plan".
            if let backendError = result.error {
                errorMessage = result.errorDetail ?? backendError
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct TodayView: View {
    @StateObject private var viewModel = TodayViewModel()
    @State private var showingCheckIn = false
    @State private var showingLogSession = false
    @State private var showingGoals = false
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    content
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.background)
            .scrollContentBackground(.hidden)
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingLogSession = true
                    } label: {
                        Label("Log Session", systemImage: "square.and.pencil")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingCheckIn = true
                    } label: {
                        Label("Check In", systemImage: "checkmark.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingGoals = true
                    } label: {
                        Label("Goals", systemImage: "target")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showingCheckIn) {
                CheckInView()
            }
            .sheet(isPresented: $showingLogSession) {
                LogSessionView()
            }
            .sheet(isPresented: $showingGoals) {
                GoalsView()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .safeAreaInset(edge: .bottom) { messageBar }
            .task {
                if viewModel.response == nil {
                    await viewModel.loadToday()
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.response == nil {
            ProgressView("Checking in with your coach…")
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
        } else if let response = viewModel.response, response.error == nil {
            decisionContent(response)
        } else if let message = viewModel.errorMessage {
            errorContent(message)
        }
    }

    @ViewBuilder
    private func errorContent(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Couldn't reach the coach", systemImage: "wifi.exclamationmark")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text(message)
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
            Button("Try again") {
                Task { await viewModel.loadToday() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.top, 40)
    }

    @ViewBuilder
    private func decisionContent(_ response: TurnResponse) -> some View {
        // The decision itself is the hero of this screen -- the one
        // thing the accent color gets spent on here. Every decision
        // gets the same treatment regardless of KEEP/MODIFY/REST:
        // color-coding "which decision" would read as a status score,
        // which this app deliberately doesn't do anywhere.
        if let decision = response.decision {
            HStack {
                Text(decision.decision)
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Theme.accent.opacity(0.18))
                    .foregroundStyle(Theme.accent)
                    .clipShape(Capsule())
                Spacer()
            }
        }

        if let reply = response.reply {
            // Bold, confident type for the one thing that matters on
            // this screen -- the coach's actual call for today.
            Text(reply)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }

        if let decision = response.decision,
           decision.decision != "REST",
           !decision.today.exercises.isEmpty {
            sessionCard(decision.today)
        }
    }

    @ViewBuilder
    private func sessionCard(_ session: TodaySession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(session.type.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(session.durationMin) min")
                    .foregroundStyle(Theme.textSecondary)
            }
            if !session.intensityNote.isEmpty {
                Text(session.intensityNote)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            Divider().overlay(Theme.textSecondary.opacity(0.2))
            ForEach(session.exercises) { exercise in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(exercise.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text("\(exercise.sets) x \(exercise.reps)")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    if let note = exercise.note, !note.isEmpty {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }

    private var messageBar: some View {
        HStack(spacing: 8) {
            // Open-ended on purpose -- a bad night's sleep, a stressful
            // week, travel, none of it is "fitness," but all of it
            // changes what today should look like. Narrower copy here
            // implicitly tells people not to bother mentioning it.
            TextField("What's going on?", text: $viewModel.messageDraft, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(10)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1...4)
            VoiceInputButton(text: $viewModel.messageDraft)
            Button {
                Task { await viewModel.sendDraft() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .disabled(
                viewModel.messageDraft.trimmingCharacters(in: .whitespaces).isEmpty
                || viewModel.isLoading
            )
        }
        .padding()
        .background(Theme.background)
    }
}

#Preview {
    TodayView()
}

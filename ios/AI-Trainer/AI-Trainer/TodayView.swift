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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    content
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
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
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Try again") {
                Task { await viewModel.loadToday() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.top, 40)
    }

    @ViewBuilder
    private func decisionContent(_ response: TurnResponse) -> some View {
        if let decision = response.decision {
            HStack {
                Text(decision.decision)
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(badgeColor(decision.decision).opacity(0.15))
                    .foregroundStyle(badgeColor(decision.decision))
                    .clipShape(Capsule())
                Spacer()
            }
        }

        if let reply = response.reply {
            Text(reply)
                .font(.body)
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
                Spacer()
                Text("\(session.durationMin) min")
                    .foregroundStyle(.secondary)
            }
            if !session.intensityNote.isEmpty {
                Text(session.intensityNote)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Divider()
            ForEach(session.exercises) { exercise in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(exercise.name)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text("\(exercise.sets) x \(exercise.reps)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let note = exercise.note, !note.isEmpty {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var messageBar: some View {
        HStack(spacing: 8) {
            // Open-ended on purpose -- a bad night's sleep, a stressful
            // week, travel, none of it is "fitness," but all of it
            // changes what today should look like. Narrower copy here
            // implicitly tells people not to bother mentioning it.
            TextField("What's going on?", text: $viewModel.messageDraft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
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
        .background(.bar)
    }

    private func badgeColor(_ decision: String) -> Color {
        switch decision {
        case "KEEP": return .green
        case "MODIFY": return .orange
        case "REST": return .blue
        default: return .gray
        }
    }
}

#Preview {
    TodayView()
}

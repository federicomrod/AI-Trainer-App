//
//  DebugBriefingView.swift
//  AI-Trainer
//
//  The raw briefing text the planner call actually sees -- goals,
//  recent sessions, soreness, tracked numbers, memory, all of it,
//  unfiltered. This exists for our own debugging only. It used to leak
//  onto Today's user-facing "why" chevron; it now lives here instead,
//  behind Settings > Developer, clearly labeled so it's never mistaken
//  for something written for the athlete to read. See TodayView's
//  whyDetail() for what actually renders on Today.

import Combine
import SwiftUI

@MainActor
final class DebugBriefingViewModel: ObservableObject {
    @Published var briefing: String?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let client = APIClient()

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            briefing = try await client.fetchBriefingDebug().briefing
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct DebugBriefingView: View {
    @StateObject private var viewModel = DebugBriefingViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Label("Developer only", systemImage: "wrench.and.screwdriver.fill")
                    .font(.caption.bold())
                    .foregroundStyle(Theme.textSecondary)
                Text("The raw text sent to the model on the next call. Not written for you to read -- if something here belongs on the Today screen, that's a separate fix, not a reason to show this.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)

                if viewModel.isLoading && viewModel.briefing == nil {
                    ProgressView().padding(.top, 20)
                } else if let error = viewModel.errorMessage {
                    Text(error).foregroundStyle(Theme.textSecondary)
                } else if let briefing = viewModel.briefing {
                    Text(briefing)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .flatCard()
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .appBackground()
        .navigationTitle("Briefing (debug)")
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
    }
}

#Preview {
    NavigationStack { DebugBriefingView() }
}

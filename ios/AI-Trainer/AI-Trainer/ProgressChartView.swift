//
//  ProgressChartView.swift
//  AI-Trainer
//
//  Simple trend lines and a plain weekly count -- real data straight
//  out of lifts and sessions, nothing invented. Per CLAUDE.md's
//  non-goals (no gamification, no readiness score presented as fact):
//  no points, no streaks, no scoring here either. Named *Chart*View,
//  not ProgressView, so it doesn't collide with SwiftUI's own
//  ProgressView (the loading spinner) used throughout this app.

import Charts
import Combine
import SwiftUI

@MainActor
final class ProgressViewModel: ObservableObject {
    @Published var progress: ProgressResponse?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let client = APIClient()

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            progress = try await client.fetchProgress()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct ProgressChartView: View {
    @StateObject private var viewModel = ProgressViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.progress == nil {
                    SwiftUI.ProgressView("Loading progress…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.errorMessage, viewModel.progress == nil {
                    VStack(spacing: 12) {
                        Text(error).foregroundStyle(.secondary)
                        Button("Try again") { Task { await viewModel.load() } }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let progress = viewModel.progress {
                    content(for: progress)
                } else {
                    Color.clear
                }
            }
            .navigationTitle("Progress")
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
        }
    }

    @ViewBuilder
    private func content(for progress: ProgressResponse) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                weeklySessionsSection(progress.weeklySessions)

                let sortedExercises = progress.lifts.keys.sorted()
                if sortedExercises.isEmpty {
                    Text("Nothing tracked yet — numbers you log for an exercise show up here.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedExercises, id: \.self) { name in
                        if let points = progress.lifts[name], !points.isEmpty {
                            liftSection(name: name, points: points)
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func weeklySessionsSection(_ counts: [WeeklySessionCount]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sessions per week")
                .font(.headline)
            Chart(counts) { point in
                BarMark(
                    x: .value("Week", point.weekStartValue, unit: .weekOfYear),
                    y: .value("Sessions", point.count)
                )
            }
            .frame(height: 160)
        }
    }

    private func liftSection(name: String, points: [LiftPoint]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(name)
                .font(.headline)
            Chart(points) { point in
                LineMark(
                    x: .value("Date", point.dateValue),
                    y: .value("Weight", point.weight)
                )
                .symbol(.circle)
            }
            .frame(height: 160)
            if let last = points.last {
                Text("Last: \(formattedWeight(last.weight))kg on \(last.date)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func formattedWeight(_ weight: Double) -> String {
        weight == weight.rounded() ? String(Int(weight)) : String(weight)
    }
}

#Preview {
    ProgressChartView()
}

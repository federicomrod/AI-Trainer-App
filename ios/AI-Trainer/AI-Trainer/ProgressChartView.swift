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

private struct StatTile: Identifiable {
    let id: String
    let label: String
    let value: String
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
                        Text(error).foregroundStyle(Theme.textSecondary)
                        Button("Try again") { Task { await viewModel.load() } }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let progress = viewModel.progress {
                    content(for: progress)
                } else {
                    Color.clear
                }
            }
            .background(Theme.background)
            .navigationTitle("Progress")
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
        }
    }

    @ViewBuilder
    private func content(for progress: ProgressResponse) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                statsSection(progress.stats)
                weeklySessionsSection(progress.weeklySessions)

                let sortedExercises = progress.lifts.keys.sorted()
                if sortedExercises.isEmpty {
                    Text("Nothing tracked yet — numbers you log for an exercise show up here.")
                        .foregroundStyle(Theme.textSecondary)
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

    // Emergent KPIs -- same principle as tracked exercises throughout
    // this app: a tile only exists once there's a real number behind
    // it (server/progress.py never invents one), so this grows one
    // tile at a time as real history accumulates rather than shipping
    // with empty placeholders. No streaks, no points -- "this week"
    // is a plain count, not a run to protect.
    @ViewBuilder
    private func statsSection(_ stats: ProgressStats) -> some View {
        let tiles = statTiles(stats)
        if !tiles.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Stats")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(tiles) { tile in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tile.label)
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                            Text(tile.value)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(Theme.textPrimary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                    }
                }
            }
        }
    }

    private func statTiles(_ stats: ProgressStats) -> [StatTile] {
        var tiles = [
            StatTile(
                id: "week", label: "This week",
                value: "\(stats.sessionsThisWeek) session\(stats.sessionsThisWeek == 1 ? "" : "s")"
            )
        ]
        if let ride = stats.longestRideMin {
            tiles.append(StatTile(id: "ride", label: "Longest ride", value: "\(ride) min"))
        }
        if let swim = stats.longestSwimMin {
            tiles.append(StatTile(id: "swim", label: "Longest swim", value: "\(swim) min"))
        }
        for pr in stats.liftPrs {
            tiles.append(StatTile(
                id: "pr-\(pr.exerciseName)", label: pr.exerciseName,
                value: "\(formattedWeight(pr.maxWeight))kg"
            ))
        }
        return tiles
    }

    // One accent, spent on the line/bar itself -- no per-series color
    // cycling, no red/green thresholds on the axis. The chart already
    // is the hero of this screen; it doesn't need decoration on top.
    private func weeklySessionsSection(_ counts: [WeeklySessionCount]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sessions per week")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Chart(counts) { point in
                BarMark(
                    x: .value("Week", point.weekStartValue, unit: .weekOfYear),
                    y: .value("Sessions", point.count)
                )
                .foregroundStyle(Theme.accent)
                .cornerRadius(6)
            }
            .frame(height: 160)
            .chartXAxis { AxisMarks(values: .automatic) { _ in
                AxisGridLine().foregroundStyle(Theme.textSecondary.opacity(0.25))
                AxisValueLabel().foregroundStyle(Theme.textSecondary)
            } }
            .chartYAxis { AxisMarks { _ in
                AxisGridLine().foregroundStyle(Theme.textSecondary.opacity(0.25))
                AxisValueLabel().foregroundStyle(Theme.textSecondary)
            } }
        }
    }

    private func liftSection(name: String, points: [LiftPoint]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(name)
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Chart(points) { point in
                AreaMark(
                    x: .value("Date", point.dateValue),
                    y: .value("Weight", point.weight)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Theme.accent.opacity(0.3), Theme.accent.opacity(0)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Date", point.dateValue),
                    y: .value("Weight", point.weight)
                )
                .foregroundStyle(Theme.accent)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.catmullRom)
                .symbol {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 7, height: 7)
                        .background(Circle().fill(Theme.background).frame(width: 10, height: 10))
                }
            }
            .frame(height: 160)
            .chartXAxis { AxisMarks(values: .automatic) { _ in
                AxisGridLine().foregroundStyle(Theme.textSecondary.opacity(0.25))
                AxisValueLabel().foregroundStyle(Theme.textSecondary)
            } }
            .chartYAxis { AxisMarks { _ in
                AxisGridLine().foregroundStyle(Theme.textSecondary.opacity(0.25))
                AxisValueLabel().foregroundStyle(Theme.textSecondary)
            } }
            if let last = points.last {
                Text("Last: \(formattedWeight(last.weight))kg on \(last.date)")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
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

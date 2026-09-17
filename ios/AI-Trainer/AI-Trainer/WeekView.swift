//
//  WeekView.swift
//  AI-Trainer
//
//  Calendar-style list of the current week: what was planned for each
//  day vs. what actually happened, with a clear marker on any day a
//  coaching decision moved (CLAUDE.md's plan_diff). The session rows
//  themselves are never rewritten when a decision changes the plan --
//  see server/week.py -- so `moved` here means "this day no longer
//  matches what's shown, and here's why," not "this row is stale."

import Combine
import SwiftUI

@MainActor
final class WeekViewModel: ObservableObject {
    @Published var days: [WeekDay] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let client = APIClient()

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            days = try await client.fetchWeek()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct WeekView: View {
    @StateObject private var viewModel = WeekViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.days.isEmpty {
                    ProgressView("Loading this week…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.errorMessage, viewModel.days.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Couldn't load this week", systemImage: "wifi.exclamationmark")
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(Theme.textSecondary)
                        Button("Try again") { Task { await viewModel.load() } }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                } else {
                    // The Mon-Sun list mixes three kinds of day: today
                    // (the one that actually needs a decision), what's
                    // still ahead this week, and what's already
                    // happened. Only today needs full presence --
                    // finished days are a record to glance at, not
                    // something to weigh equally against what's
                    // actionable right now.
                    let referenceDate = viewModel.days.first(where: { $0.isToday })?.date
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.days) { day in
                                DayCard(
                                    day: day,
                                    isPast: referenceDate.map { day.date < $0 } ?? false
                                )
                            }
                        }
                        .padding()
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Theme.background)
            .navigationTitle("This Week")
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
        }
    }
}

private struct DayCard: View {
    let day: WeekDay
    let isPast: Bool

    // Three tiers, not two: today leads with real presence, an
    // upcoming day reads at normal weight (it's the plan, worth
    // seeing clearly), and a finished day recedes -- lower contrast,
    // tighter, a record rather than something competing for attention
    // with what's actually still actionable.
    private var isQuiet: Bool { isPast && !day.isToday }

    var body: some View {
        VStack(alignment: .leading, spacing: isQuiet ? 4 : 6) {
            HStack {
                Text("\(day.weekday) · \(shortDate(day.date))")
                    .font(isQuiet ? .footnote.weight(.medium) : .subheadline.weight(.semibold))
                    .foregroundStyle(isQuiet ? Theme.textSecondary : Theme.textPrimary)
                if day.isToday {
                    // Today is the hero of this list -- the one place
                    // on this screen the accent earns its keep.
                    Text("TODAY")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.accent.opacity(0.18))
                        .foregroundStyle(Theme.accent)
                        .clipShape(Capsule())
                }
                Spacer()
                StatusTag(status: day.status, isQuiet: isQuiet)
            }

            if day.moved {
                // Same accent as everywhere else, not a separate
                // ad-hoc color -- this marks "something changed here,"
                // not a status judgment on the day.
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "arrow.triangle.branch")
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(displayType(day.type)) → \(day.movedTo ?? "")")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(Theme.textPrimary)
                        if let reason = day.movedReason, !reason.isEmpty {
                            Text(reason)
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                .padding(8)
                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            } else {
                Text(displayType(day.type))
                    .font(day.isToday ? .title3.weight(.bold) : .callout.weight(.medium))
                    .foregroundStyle(isQuiet ? Theme.textSecondary : Theme.textPrimary)
            }

            if let summary = summaryText(for: day) {
                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(isQuiet ? 1 : nil)
            }

            if let duration = day.durationMin {
                Text("\(duration) min")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, day.isToday ? 18 : 14)
        .padding(.vertical, isQuiet ? 10 : (day.isToday ? 18 : 14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            day.isToday ? Theme.cardElevated : Theme.card,
            in: RoundedRectangle(cornerRadius: Theme.cardRadius)
        )
        .opacity(isQuiet ? 0.72 : 1.0)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .strokeBorder(day.isToday ? Theme.accent : .clear, lineWidth: 2)
        )
    }

    private func summaryText(for day: WeekDay) -> String? {
        switch day.status {
        case "done", "partial":
            return day.actualSummary
        case "skipped":
            return day.actualSummary ?? day.plannedSummary
        default:
            return day.plannedSummary
        }
    }

    private func displayType(_ type: String) -> String {
        type.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func shortDate(_ iso: String) -> String {
        let parts = iso.split(separator: "-")
        guard parts.count == 3 else { return iso }
        return "\(parts[1])/\(parts[2])"
    }
}

/// Deliberately one neutral treatment for every status. An earlier
/// version color-coded these red/yellow/green -- that's exactly the
/// traffic-light scoring this app is meant to avoid (a skipped session
/// isn't a "failure" to flag red, per CLAUDE.md's logging philosophy).
/// Word alone carries the meaning; "planned" fades slightly since it
/// hasn't happened yet, everything else reads at full weight.
private struct StatusTag: View {
    let status: String
    let isQuiet: Bool

    var body: some View {
        Text(status.capitalized)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(isQuiet ? Theme.background : Theme.cardElevated)
            .foregroundStyle(
                status == "planned" || isQuiet ? Theme.textSecondary : Theme.textPrimary
            )
            .clipShape(Capsule())
    }
}

#Preview {
    WeekView()
}

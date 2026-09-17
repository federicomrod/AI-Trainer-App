//
//  DayDetailView.swift
//  AI-Trainer
//
//  Week view's tap-to-open detail for one calendar day: planned vs.
//  actual, any lift numbers logged that date, that day's check-in,
//  and -- if the athlete mentioned this specific day in chat -- the
//  note the coach attached to it (server/session_note_parser.py; see
//  GET /day / server/day_detail.py). Pure presentation over data
//  every other screen already reads; nothing computed here.

import Combine
import SwiftUI

@MainActor
final class DayDetailViewModel: ObservableObject {
    @Published var detail: DayDetailResponse?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isEmpty = false

    private let client = APIClient()

    func load(date: String) async {
        isLoading = true
        errorMessage = nil
        isEmpty = false
        do {
            detail = try await client.fetchDay(date: date)
        } catch APIError.http(404) {
            isEmpty = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct DayDetailView: View {
    let date: String
    @StateObject private var viewModel = DayDetailViewModel()

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.detail == nil {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .font(.largeTitle)
                        .foregroundStyle(Theme.textSecondary)
                    Text("Nothing on record for this day")
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.errorMessage {
                VStack(spacing: 12) {
                    Text(error).foregroundStyle(Theme.textSecondary)
                    Button("Try again") { Task { await viewModel.load(date: date) } }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let detail = viewModel.detail {
                content(detail)
            } else {
                Color.clear
            }
        }
        .appBackground()
        .navigationTitle(formattedTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load(date: date) }
    }

    private var formattedTitle: String {
        guard let parsed = isoDayFormatter.date(from: date) else { return date }
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: parsed)
    }

    @ViewBuilder
    private func content(_ detail: DayDetailResponse) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(detail)

                if let chatNote = detail.chatNote, !chatNote.isEmpty {
                    section(title: "From chat", icon: "bubble.left.fill") {
                        Text(chatNote)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textPrimary)
                    }
                }

                if !detail.lifts.isEmpty {
                    section(title: "Lifts logged", icon: "dumbbell.fill") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(detail.lifts) { lift in
                                liftRow(lift)
                            }
                        }
                    }
                }

                if let checkin = detail.checkin {
                    section(title: "Check-in", icon: "checkmark.circle.fill") {
                        checkInContent(checkin)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func header(_ detail: DayDetailResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if let type = detail.type {
                    Image(systemName: SessionTypeIcon.symbolName(for: type))
                        .font(.title2)
                        .foregroundStyle(Theme.accent)
                    Text(type.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(Theme.rounded(.title3, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                if let status = detail.status {
                    Text(status.capitalized)
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.cardElevated)
                        .foregroundStyle(Theme.textPrimary)
                        .clipShape(Capsule())
                }
            }

            if let planned = detail.plannedSummary {
                labeledLine(label: "Planned", value: planned)
            }
            if let actual = detail.actualSummary {
                labeledLine(label: "Actual", value: actual)
            }

            HStack(spacing: 16) {
                if let duration = detail.durationMin {
                    Label("\(duration) min", systemImage: "clock")
                }
                if let rpe = detail.rpe {
                    Label("RPE \(formattedNumber(rpe))", systemImage: "gauge.medium")
                }
            }
            .font(.footnote)
            .foregroundStyle(Theme.textSecondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .heroCard()
    }

    private func labeledLine(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private func section<Content: View>(
        title: String, icon: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(Theme.rounded(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .flatCard()
    }

    private func liftRow(_ lift: DayLift) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(lift.exerciseName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(liftSummary(lift))
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func liftSummary(_ lift: DayLift) -> String {
        var parts: [String] = []
        if let weight = lift.weight { parts.append("\(formattedNumber(weight))kg") }
        if let sets = lift.sets, let reps = lift.reps {
            parts.append("\(sets) × \(reps)")
        } else if let reps = lift.reps {
            parts.append("\(reps) reps")
        }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private func checkInContent(_ checkin: DayCheckIn) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 16) {
                if let sleep = checkin.sleep {
                    Text("Sleep: \(sleep.capitalized)")
                }
                if let energy = checkin.energy {
                    Text("Energy: \(energy)/5")
                }
            }
            .font(.subheadline)
            .foregroundStyle(Theme.textPrimary)

            if !checkin.soreness.isEmpty {
                Text(
                    "Soreness: " + checkin.soreness
                        .map { "\($0.key.capitalized) \($0.value)" }
                        .sorted()
                        .joined(separator: ", ")
                )
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            }

            if let note = checkin.note, !note.isEmpty {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func formattedNumber(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}

#Preview {
    NavigationStack {
        DayDetailView(date: "2026-09-16")
    }
}

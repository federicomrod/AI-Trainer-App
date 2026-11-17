//
//  ShareCardView.swift
//  AI-Trainer
//
//  The weekly report card for Instagram Stories (CLAUDE.md, "Goals,
//  progress and sharing"): week label, session count, minutes, one dot
//  per day. Rendered at 1080x1920 with ImageRenderer and handed to the
//  share sheet.
//
//  Real numbers only, all from GET /day for each day of the week. A
//  rest day logged as "done" gets its own dot and is not counted as a
//  session, matching server/progress.py. Goal bars are left out until a goal has a
//  measured baseline and target behind it; today goals are plain text.

import Combine
import SwiftUI

/// What one day of the card shows.
struct ShareDay: Identifiable {
    enum Kind { case strength, endurance, rest, missed, nothing }
    let id: String      // yyyy-MM-dd
    let letter: String  // "M"
    let kind: Kind
}

/// Everything the card draws. Built from server data only.
struct WeeklyCardData {
    let weekStart: Date
    let sessionCount: Int
    let minutes: Int?
    let days: [ShareDay]
}

/// The card itself, laid out for 1080x1920 points.
struct ShareCardView: View {
    let data: WeeklyCardData

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("HYBRID COACH")
                .font(.system(size: 34, weight: .heavy))
                .tracking(6)
                .foregroundStyle(Theme.textMuted)

            Spacer().frame(height: 120)

            Text("Week of " + data.weekStart.formatted(.dateTime.day().month(.wide)))
                .font(.system(size: 52, weight: .bold))
                .foregroundStyle(Theme.textMuted)
            Text("\(data.sessionCount)")
                .font(.system(size: 380, weight: .heavy))
                .tracking(-16)
                .foregroundStyle(Theme.accent)
                .padding(.top, -20)
            Text(data.sessionCount == 1 ? "session" : "sessions")
                .font(.system(size: 88, weight: .heavy))
                .tracking(-2)
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, -40)
            if let minutes = data.minutes, minutes > 0 {
                Text("\(minutes) min logged")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
                    .padding(.top, 16)
            }

            Spacer().frame(height: 100)

            HStack(spacing: 0) {
                ForEach(data.days) { day in
                    VStack(spacing: 22) {
                        dot(day.kind)
                        Text(day.letter)
                            .font(.system(size: 40, weight: .bold))
                            .foregroundStyle(Theme.textMuted)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            Spacer().frame(height: 120)

            HStack(spacing: 32) {
                split(data.days.filter { $0.kind == .strength }.count, "strength", Theme.accent)
                split(data.days.filter { $0.kind == .endurance }.count, "endurance", Theme.endurance)
            }

            Spacer()

            HStack(spacing: 28) {
                legend(Theme.accent, "Strength")
                legend(Theme.endurance, "Endurance")
                legend(Theme.surface3, "Rest")
            }
        }
        .padding(.horizontal, 96)
        .padding(.vertical, 140)
        .frame(width: 1080, height: 1920, alignment: .topLeading)
        .background(Theme.background)
    }

    @ViewBuilder
    private func dot(_ kind: ShareDay.Kind) -> some View {
        switch kind {
        case .strength:
            Circle().fill(Theme.accent).frame(width: 96, height: 96)
        case .endurance:
            Circle().fill(Theme.endurance).frame(width: 96, height: 96)
        case .rest:
            Image(systemName: "moon.fill")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(Theme.textMuted)
                .frame(width: 96, height: 96)
                .background(Theme.surface3, in: Circle())
        case .missed:
            Circle().strokeBorder(Theme.textMuted.opacity(0.6), lineWidth: 6).frame(width: 96, height: 96)
        case .nothing:
            Circle().fill(Theme.surface2).frame(width: 96, height: 96)
        }
    }

    private func split(_ count: Int, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(count)")
                .font(.system(size: 140, weight: .heavy))
                .tracking(-4)
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(Theme.textMuted)
        }
        .padding(44)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface1, in: RoundedRectangle(cornerRadius: 48))
    }

    private func legend(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 14) {
            Circle().fill(color).frame(width: 30, height: 30)
            Text(label)
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(Theme.textMuted)
        }
    }
}

@MainActor
final class WeeklyShareModel: ObservableObject {
    @Published var showLastWeek = false
    @Published var data: WeeklyCardData?
    @Published var image: UIImage?
    @Published var isLoading = false

    private let client = APIClient()
    private var progress: ProgressResponse?
    private var didPickDefault = false

    /// Session statuses that count as "happened" -- the same set
    /// server/progress.py counts, so the card and the charts agree.
    private static let completed: Set<String> = ["done", "partial", "unplanned"]

    private var calendar: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    func load(progress: ProgressResponse) async {
        self.progress = progress
        // On a week with nothing done yet (a Monday morning), last week
        // is the one worth sharing.
        if !didPickDefault {
            didPickDefault = true
            showLastWeek = progress.stats.sessionsThisWeek == 0
                && progress.weeklySessions.dropLast().last.map { $0.count > 0 } == true
        }
        await rebuild()
    }

    func rebuild() async {
        guard let progress else { return }
        isLoading = true
        defer { isLoading = false }

        // Today's date as the athlete sees it (local), then as a UTC
        // midnight to match the server's plain yyyy-MM-dd dates.
        let local = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        let todayKey = String(format: "%04d-%02d-%02d", local.year ?? 0, local.month ?? 0, local.day ?? 0)
        let today = isoDayFormatter.date(from: todayKey) ?? Date()
        guard var monday = calendar.dateInterval(of: .weekOfYear, for: today)?.start else { return }
        if showLastWeek { monday = calendar.date(byAdding: .day, value: -7, to: monday) ?? monday }

        let letters = ["M", "T", "W", "T", "F", "S", "S"]
        var days: [ShareDay] = []
        var minutes = 0
        var anyMinutes = false
        for offset in 0..<7 {
            let date = calendar.date(byAdding: .day, value: offset, to: monday) ?? monday
            let key = isoDayFormatter.string(from: date)
            var kind = ShareDay.Kind.nothing
            // A missing day is a 404: nothing on record, an empty dot.
            if let day = try? await client.fetchDay(date: key), let status = day.status {
                if Self.completed.contains(status), day.type == "rest" {
                    kind = .rest
                } else if Self.completed.contains(status) {
                    kind = SessionTypeIcon.isEndurance(day.type ?? "") ? .endurance : .strength
                    if let m = day.durationMin { minutes += m; anyMinutes = true }
                } else if status == "skipped" || (status == "planned" && date < today) {
                    kind = .missed
                }
            }
            days.append(ShareDay(id: key, letter: letters[offset], kind: kind))
        }

        let count = days.filter { $0.kind == .strength || $0.kind == .endurance }.count

        let cardData = WeeklyCardData(
            weekStart: monday, sessionCount: count,
            minutes: anyMinutes ? minutes : nil,
            days: days
        )
        data = cardData
        let renderer = ImageRenderer(content: ShareCardView(data: cardData))
        renderer.scale = 1  // the view is already 1080x1920 points
        image = renderer.uiImage
        #if DEBUG
        // Screenshots only: keep the full-size card in Documents so it
        // can be copied out of the Simulator.
        if let png = image?.pngData(),
           let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? png.write(to: docs.appendingPathComponent("weekly-card.png"))
        }
        #endif
    }
}

/// The share section on the Progress tab: a small preview of the card,
/// this week / last week, and the share sheet.
struct WeeklyShareSection: View {
    let progress: ProgressResponse
    @StateObject private var model = WeeklyShareModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Weekly card")
                    .font(Theme.font(.headline, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Picker("Week", selection: $model.showLastWeek) {
                    Text("This week").tag(false)
                    Text("Last week").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }

            HStack(alignment: .center, spacing: 16) {
                Group {
                    if let image = model.image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Theme.surface2
                    }
                }
                .frame(width: 108, height: 192)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.08)))

                VStack(alignment: .leading, spacing: 12) {
                    if let data = model.data {
                        Text("\(data.sessionCount) \(data.sessionCount == 1 ? "session" : "sessions")")
                            .font(.title2.weight(.heavy))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Week of " + data.weekStart.formatted(.dateTime.day().month(.abbreviated)))
                            .font(.subheadline)
                            .foregroundStyle(Theme.textMuted)
                    }
                    if let image = model.image {
                        ShareLink(
                            item: Image(uiImage: image),
                            preview: SharePreview("My training week", image: Image(uiImage: image))
                        ) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.primary)
                    } else if model.isLoading {
                        SwiftUI.ProgressView().tint(Theme.accent)
                    }
                }
            }
        }
        .padding(16)
        .flatCard()
        .task(id: progress.weeklySessions.map(\.count)) { await model.load(progress: progress) }
        .onChange(of: model.showLastWeek) { Task { await model.rebuild() } }
    }
}

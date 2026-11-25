//
//  ChatCards.swift
//  AI-Trainer
//
//  The structured cards under a coach reply in chat. The server sends
//  the reply as 1-3 plain sentences and the lists next to it
//  (`cards`, `workout`, `week_plan`), so a routine is a table to scan
//  and a multi-day plan is one row per day, not a paragraph.
//
//  WorkoutTableCard: one row per exercise (name, sets x reps, rest,
//  technique/note), superset rows joined, total working sets at the
//  bottom. Its header opens the Workout screen when it's for today.
//  WeekPlanCard: date block, title and detail, a kind pill.

import SwiftUI

// MARK: - Workout table

struct WorkoutTableCard: View {
    let session: TodaySession
    /// Set when this workout is today's: the header then opens the
    /// Workout screen, same as Start workout on Today.
    var onStart: (() -> Void)?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(16)
            ExerciseTable(exercises: session.exercises)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .flatCard()
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var header: some View {
        let content = Group {
            if dynamicTypeSize.isAccessibilitySize {
                // Very large text: icon and Start on one line, the
                // words full width below, so they wrap by word.
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        typeIcon
                        Spacer(minLength: 8)
                        startPill
                    }
                    headerText
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    typeIcon
                    headerText
                    Spacer(minLength: 8)
                    startPill
                }
            }
        }
        if let onStart {
            Button(action: onStart) { content.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the workout screen")
        } else {
            content
        }
    }

    private var typeIcon: some View {
        Image(systemName: SessionTypeIcon.symbolName(for: session.type))
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(SessionTypeIcon.tint(for: session.type))
            .frame(width: 36, height: 36)
            .background(SessionTypeIcon.tint(for: session.type).opacity(0.15), in: Circle())
    }

    private var headerText: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(displayType(session.type))
                    .font(Theme.font(.headline, weight: .heavy))
                    .foregroundStyle(Theme.textPrimary)
                if session.durationMin > 0 {
                    Text("~\(session.durationMin) min")
                        .font(Theme.font(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.textMuted)
                }
            }
            if !session.intensityNote.isEmpty {
                Text(session.intensityNote)
                    .font(Theme.font(.subheadline))
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var startPill: some View {
        if onStart != nil {
            Label("Start", systemImage: "play.fill")
                .font(Theme.font(.caption, weight: .bold))
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.accent, in: Capsule())
                .fixedSize()
        }
    }

    private func displayType(_ type: String) -> String {
        SessionTitle.display(type)
    }
}

/// The exercise rows and the "N working sets" line, shared by the chat
/// workout card and Today's card. Starts with a divider so it sits
/// under any header.
struct ExerciseTable: View {
    let exercises: [Exercise]
    /// Off when the table sits in its own box with nothing above it.
    var leadingDivider = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(groups) { group in
                if leadingDivider || group.id > 0 {
                    Divider().overlay(Color.white.opacity(0.06))
                }
                groupView(group)
            }
            Divider().overlay(Color.white.opacity(0.06))
            Text("\(totalSets) working \(totalSets == 1 ? "set" : "sets")")
                .font(Theme.font(.footnote, weight: .semibold))
                .foregroundStyle(Theme.textMuted)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
    }

    // Exercises in order, consecutive ones sharing a superset label
    // gathered into one group so they're drawn joined.
    private struct ExerciseGroup: Identifiable {
        let id: Int
        let label: String?
        let exercises: [Exercise]
    }

    private var groups: [ExerciseGroup] {
        var out: [ExerciseGroup] = []
        for exercise in exercises {
            let label = exercise.supersetGroup.flatMap { $0.isEmpty ? nil : $0 }
            if let label, let last = out.last, last.label == label {
                out[out.count - 1] = ExerciseGroup(id: last.id, label: label, exercises: last.exercises + [exercise])
            } else {
                out.append(ExerciseGroup(id: out.count, label: label, exercises: [exercise]))
            }
        }
        return out
    }

    @ViewBuilder
    private func groupView(_ group: ExerciseGroup) -> some View {
        if let label = group.label, group.exercises.count > 1 {
            VStack(alignment: .leading, spacing: 0) {
                Text("SUPERSET \(label.uppercased())")
                    .font(.system(.caption2).weight(.heavy))
                    .tracking(1)
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                ForEach(Array(group.exercises.enumerated()), id: \.offset) { _, exercise in
                    ExerciseTableRow(exercise: exercise)
                }
            }
            .overlay(alignment: .leading) {
                Rectangle().fill(Theme.accent).frame(width: 3).padding(.vertical, 8)
            }
        } else {
            ForEach(Array(group.exercises.enumerated()), id: \.offset) { _, exercise in
                ExerciseTableRow(exercise: exercise)
            }
        }
    }

    private var totalSets: Int { exercises.reduce(0) { $0 + max($1.sets, 0) } }

}

/// One exercise line: name left (wraps), sets x reps right in bold,
/// then rest and technique/note smaller underneath.
private struct ExerciseTableRow: View {
    let exercise: Exercise
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if dynamicTypeSize.isAccessibilitySize {
                // Very large text: name on its own line, numbers below,
                // so neither gets squeezed.
                name
                prescription
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    name
                    Spacer(minLength: 8)
                    prescription
                }
            }
            if let rest = restText {
                Text(rest)
                    .font(Theme.font(.footnote, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
            }
            ForEach(detailLines, id: \.self) { line in
                Text(line)
                    .font(Theme.font(.footnote))
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var name: some View {
        Text(exercise.name.plainHyphens)
            .font(Theme.font(.body, weight: .semibold))
            .foregroundStyle(Theme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
    }

    private var prescription: some View {
        Text("\(exercise.sets) x \(exercise.reps)")
            .font(Theme.font(.body, weight: .heavy))
            .monospacedDigit()
            .foregroundStyle(Theme.textPrimary)
            .fixedSize()
    }

    private var restText: String? {
        guard let sec = exercise.restSec, sec > 0 else { return nil }
        if sec >= 120, sec % 60 == 0 { return "\(sec / 60) min rest" }
        return "\(sec) s rest"
    }

    private var detailLines: [String] {
        [exercise.target, exercise.technique, exercise.note]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - Week plan

/// Pill colours for the week card, matching the rest of the app: Gym
/// lime (strength), Cardio blue (endurance), Rest grey.
enum WeekPlanKindStyle {
    static func label(_ kind: String) -> String? {
        switch kind {
        case "gym": return "Gym"
        case "cardio": return "Cardio"
        case "rest": return "Rest"
        default: return nil
        }
    }

    static func fill(_ kind: String) -> Color {
        switch kind {
        case "gym": return Theme.accent
        case "cardio": return Theme.endurance
        default: return Theme.surface3
        }
    }

    static func foreground(_ kind: String) -> Color {
        switch kind {
        case "gym", "cardio": return Theme.onAccent
        default: return Theme.textPrimary
        }
    }
}

struct WeekPlanCard: View {
    let days: [WeekPlanEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                if index > 0 {
                    Divider().overlay(Color.white.opacity(0.06))
                }
                WeekPlanRow(day: day)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .flatCard()
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct WeekPlanRow: View {
    let day: WeekPlanEntry
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // Very large text: date and pills on one line, the
                // words full width below, so they wrap by word.
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center) {
                        dateBlock
                        Spacer(minLength: 8)
                        pills
                    }
                    words
                }
            } else {
                HStack(alignment: .center, spacing: 14) {
                    dateBlock
                    words
                    pills
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private var dateBlock: some View {
        VStack(spacing: 0) {
            Text(weekday)
                .font(.system(.caption2).weight(.heavy))
                .tracking(0.5)
                .foregroundStyle(Theme.textMuted)
            Text(dayNumber)
                .font(.system(.title3).weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(minWidth: 44)
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12))
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(day.title)
                .font(Theme.font(.body, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let detail = day.detail, !detail.isEmpty {
                Text(detail)
                    .font(Theme.font(.footnote))
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var pills: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if let label = WeekPlanKindStyle.label(day.kind) {
                Pill(text: label,
                     fill: WeekPlanKindStyle.fill(day.kind),
                     foreground: WeekPlanKindStyle.foreground(day.kind))
            }
            if day.optional {
                Pill(text: "Optional", fill: .clear, foreground: Theme.textMuted)
                    .overlay(Capsule().strokeBorder(Theme.textMuted.opacity(0.5), lineWidth: 1))
            }
        }
        .fixedSize()
    }

    private var date: Date? { isoDayFormatter.date(from: day.date) }

    private var weekday: String {
        guard let date else { return "" }
        return weekdayFormatter.string(from: date).uppercased()
    }

    private var dayNumber: String {
        guard let date else { return day.date }
        return dayNumberFormatter.string(from: date)
    }
}

// Same UTC basis as isoDayFormatter, so "2026-11-23" is always the 23rd.
private let weekdayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "EEE"
    f.timeZone = TimeZone(identifier: "UTC")
    return f
}()

private let dayNumberFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "d"
    f.timeZone = TimeZone(identifier: "UTC")
    return f
}()

/// A workout the chat is about to open full screen.
struct ChatWorkoutLaunch: Identifiable {
    let id = UUID()
    let session: TodaySession
}

extension ChatMessage {
    /// Whether this message was written today on the athlete's clock.
    /// Server timestamps are UTC ("2026-11-22T20:06:24"); a live reply
    /// not yet reloaded from history has none and is today by definition.
    var isFromToday: Bool {
        guard !timestamp.isEmpty else { return true }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        guard let date = f.date(from: timestamp) else { return false }
        return Calendar.current.isDateInToday(date)
    }
}

//
//  WorkoutView.swift
//  AI-Trainer
//
//  The live gym screen, opened by "Start workout" on Today. One wide,
//  low row per item in today.exercises (docs/ui-notes.md):
//
//  - swipe left marks a row done (lime check), swipe right skips it
//  - tap a row to open it: technique, weight and reps steppers, Log set
//  - Log set starts the rest countdown from the row's rest_sec
//  - rows sharing a superset_group are drawn joined
//  - the header shows the time since Start workout was tapped
//
//  Finish sends what was done through the existing POST /log_session:
//  one lift entry per exercise that had a set logged (heaviest set as
//  weight/reps, set count as sets, every set spelled out in the note),
//  plus a plain summary. Nothing is sent for exercises with no numbers.

import Combine
import SwiftUI

/// One set the athlete logged in this workout.
struct LoggedSet: Equatable {
    let weight: Double?
    let reps: Int?
}

/// Where a row stands.
enum RowStatus {
    case todo, done, skipped
}

/// Per-row state for one item of today.exercises.
struct WorkoutRow: Identifiable {
    let id: Int
    let exercise: Exercise
    var status: RowStatus = .todo
    var sets: [LoggedSet] = []
    /// What the steppers show. Weight starts from the last logged
    /// weight for this exact exercise name, if there is one; otherwise
    /// empty. Reps start at the bottom of the prescribed range.
    var weight: Double?
    var reps: Int?
}

@MainActor
final class WorkoutViewModel: ObservableObject {
    @Published var rows: [WorkoutRow]
    @Published var expandedID: Int?
    @Published var restEndsAt: Date?
    @Published var restTotal: Int = 0
    @Published var isSaving = false
    @Published var saveError: String?
    @Published var savedSummary: String?

    let session: TodaySession
    let startedAt = Date()
    /// Endurance sessions have no weight to log -- rows just get done.
    let isEndurance: Bool
    private let client = APIClient()

    init(session: TodaySession) {
        self.session = session
        self.isEndurance = SessionTypeIcon.isEndurance(session.type)
        self.rows = session.exercises.enumerated().map { index, exercise in
            WorkoutRow(id: index, exercise: exercise, reps: Self.firstNumber(in: exercise.reps))
        }
    }

    /// "8-12" -> 8, "4 min" -> 4, "AMRAP" -> nil. From the prescription,
    /// never invented.
    static func firstNumber(in text: String) -> Int? {
        let digits = text.prefix { !$0.isNumber }.count
        let number = text.dropFirst(digits).prefix { $0.isNumber }
        return Int(number)
    }

    /// Prefill weights from the athlete's own logged history. Exact
    /// name matches only (ignoring case): a near-miss guess would be an
    /// invented number. /progress has every tracked exercise's weight
    /// series, so its last point is the last logged weight.
    func loadLastWeights() async {
        guard !isEndurance, let progress = try? await client.fetchProgress() else { return }
        var last: [String: Double] = [:]
        for (name, points) in progress.lifts {
            if let weight = points.last?.weight {
                last[name.lowercased()] = weight
            }
        }
        for index in rows.indices where rows[index].weight == nil {
            rows[index].weight = last[rows[index].exercise.name.lowercased()]
        }
    }

    var doneCount: Int { rows.filter { $0.status == .done }.count }

    func toggleExpanded(_ id: Int) {
        expandedID = expandedID == id ? nil : id
    }

    func mark(_ id: Int, _ status: RowStatus) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].status = rows[index].status == status ? .todo : status
        if expandedID == id, rows[index].status != .todo { expandedID = nil }
    }

    func logSet(_ id: Int) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].sets.append(LoggedSet(weight: rows[index].weight, reps: rows[index].reps))
        let row = rows[index]
        let finished = row.sets.count >= row.exercise.sets
        if finished {
            rows[index].status = .done
            expandedID = nil
        }
        // Rest after every set except the very last one of the workout.
        if let rest = row.exercise.restSec, rest > 0,
           !(finished && rows.allSatisfy({ $0.status != .todo })) {
            restTotal = rest
            restEndsAt = Date().addingTimeInterval(TimeInterval(rest))
        }
    }

    func undoLastSet(_ id: Int) {
        guard let index = rows.firstIndex(where: { $0.id == id }),
              !rows[index].sets.isEmpty else { return }
        rows[index].sets.removeLast()
        if rows[index].status == .done { rows[index].status = .todo }
    }

    func stepWeight(_ id: Int, by delta: Double) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].weight = max(0, (rows[index].weight ?? 0) + delta)
    }

    func stepReps(_ id: Int, by delta: Int) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].reps = max(0, (rows[index].reps ?? 0) + delta)
    }

    func skipRest() { restEndsAt = nil }

    var elapsedMinutes: Int { Int(Date().timeIntervalSince(startedAt) / 60) }

    /// Send what was done. Status is "done" only if every row was done.
    func finish() async -> Bool {
        isSaving = true
        saveError = nil
        defer { isSaving = false }

        let done = rows.filter { $0.status == .done || !$0.sets.isEmpty }
        let skipped = rows.filter { $0.status == .skipped }
        let status: String
        if done.isEmpty {
            status = "skipped"
        } else if done.count == rows.count {
            status = "done"
        } else {
            status = "partial"
        }

        var parts: [String] = []
        if !done.isEmpty {
            parts.append("Done: " + done.map(\.exercise.name).joined(separator: ", ") + ".")
        }
        if !skipped.isEmpty {
            parts.append("Skipped: " + skipped.map(\.exercise.name).joined(separator: ", ") + ".")
        }
        let untouched = rows.filter { $0.status == .todo && $0.sets.isEmpty }
        if !untouched.isEmpty {
            parts.append("Not reached: " + untouched.map(\.exercise.name).joined(separator: ", ") + ".")
        }
        parts.append("Logged live in the app, \(elapsedMinutes) min.")

        let lifts: [LiftEntry] = rows.compactMap { row in
            guard !row.sets.isEmpty else { return nil }
            let top = row.sets.max { ($0.weight ?? 0, $0.reps ?? 0) < ($1.weight ?? 0, $1.reps ?? 0) }
            let detail = row.sets.map(Self.describe).joined(separator: ", ")
            return LiftEntry(
                exerciseName: row.exercise.name,
                weight: top?.weight,
                reps: top?.reps,
                sets: row.sets.count,
                note: "Sets: \(detail)"
            )
        }

        do {
            let result = try await client.submitLog(LogSessionRequest(
                date: nil, status: status, notes: parts.joined(separator: " "), lifts: lifts
            ))
            savedSummary = "Saved as \(result.status). \(result.liftsRecorded.count) exercise"
                + (result.liftsRecorded.count == 1 ? "" : "s") + " with numbers."
            return true
        } catch APIError.http(404) {
            saveError = "There's no session on today's plan to log this against."
            return false
        } catch {
            saveError = error.localizedDescription
            return false
        }
    }

    static func describe(_ set: LoggedSet) -> String {
        switch (set.weight, set.reps) {
        case let (w?, r?): return "\(formatKg(w)) x \(r)"
        case let (w?, nil): return formatKg(w)
        case let (nil, r?): return "\(r) reps"
        default: return "done"
        }
    }

    static func formatKg(_ value: Double) -> String {
        (value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)) + " kg"
    }
}

struct WorkoutView: View {
    @StateObject private var viewModel: WorkoutViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingFinish = false
    @State private var confirmingClose = false
    @FocusState private var weightFocused: Int?

    init(session: TodaySession) {
        _viewModel = StateObject(wrappedValue: WorkoutViewModel(session: session))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if viewModel.restEndsAt != nil {
                restBanner
            }
            List {
                ForEach(viewModel.rows) { row in
                    rowView(row)
                        .listRowInsets(EdgeInsets(
                            top: joinedAbove(row) ? 1 : 5, leading: 16,
                            bottom: joinedBelow(row) ? 1 : 5, trailing: 16
                        ))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        // Swipe left: done. Swipe right: skip.
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                viewModel.mark(row.id, .done)
                            } label: {
                                Label(row.status == .done ? "Undo" : "Done", systemImage: "checkmark")
                            }
                            .tint(Theme.accent)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                viewModel.mark(row.id, .skipped)
                            } label: {
                                Label(row.status == .skipped ? "Undo" : "Skip", systemImage: "forward.fill")
                            }
                            .tint(Theme.surface3)
                        }
                }
                Text("Swipe left when done, right to skip. Tap to log sets.")
                    .font(.caption)
                    .foregroundStyle(Theme.textMuted)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .animation(.easeInOut(duration: 0.2), value: viewModel.expandedID)
        }
        .safeAreaInset(edge: .bottom) { finishBar }
        .appBackground()
        .task {
            await viewModel.loadLastWeights()
            #if DEBUG
            // Screenshots only: `-screenshotWorkout YES` also opens the
            // first row and marks the second done.
            if UserDefaults.standard.bool(forKey: "screenshotWorkout"), viewModel.rows.count > 1 {
                viewModel.mark(viewModel.rows[1].id, .done)
                viewModel.toggleExpanded(viewModel.rows[0].id)
            }
            #endif
        }
        .confirmationDialog("Finish workout?", isPresented: $confirmingFinish, titleVisibility: .visible) {
            Button("Save and finish") {
                Task {
                    if await viewModel.finish() {
                        try? await Task.sleep(for: .seconds(1.2))
                        dismiss()
                    }
                }
            }
            Button("Keep training", role: .cancel) {}
        } message: {
            Text("\(viewModel.doneCount) of \(viewModel.rows.count) done. This saves the session to today.")
        }
        .confirmationDialog("Leave without saving?", isPresented: $confirmingClose, titleVisibility: .visible) {
            Button("Leave, don't save", role: .destructive) { dismiss() }
            Button("Keep training", role: .cancel) {}
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                if viewModel.rows.contains(where: { $0.status != .todo || !$0.sets.isEmpty }) {
                    confirmingClose = true
                } else {
                    dismiss()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(Theme.surface2, in: Circle())
            }
            .accessibilityLabel("Close workout")

            VStack(alignment: .leading, spacing: 0) {
                Text(viewModel.session.type.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.system(.title3).weight(.heavy))
                    .tracking(-0.4)
                    .foregroundStyle(Theme.textPrimary)
                Text("\(viewModel.doneCount)/\(viewModel.rows.count) done")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textMuted)
            }
            Spacer()
            TimelineView(.periodic(from: viewModel.startedAt, by: 1)) { context in
                Text(Self.clock(context.date.timeIntervalSince(viewModel.startedAt)))
                    .font(.system(size: 28, weight: .heavy).monospacedDigit())
                    .foregroundStyle(Theme.accent)
            }
            .accessibilityLabel("Elapsed time")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var restBanner: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let remaining = max(0, (viewModel.restEndsAt ?? context.date).timeIntervalSince(context.date))
            let over = remaining <= 0
            HStack(spacing: 12) {
                Image(systemName: over ? "bolt.fill" : "timer")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 4) {
                    Text(over ? "Rest over, next set" : "Rest \(Self.clock(remaining))")
                        .font(.headline.weight(.heavy).monospacedDigit())
                    if !over, viewModel.restTotal > 0 {
                        ProgressView(value: remaining, total: Double(viewModel.restTotal))
                            .tint(over ? Theme.onAccent : Theme.accent)
                    }
                }
                Spacer()
                Button(over ? "OK" : "Skip") { viewModel.skipRest() }
                    .font(.subheadline.weight(.bold))
            }
            .foregroundStyle(over ? Theme.onAccent : Theme.textPrimary)
            .padding(14)
            .background(over ? Theme.accent : Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.rowRadius))
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
        }
    }

    private var finishBar: some View {
        VStack(spacing: 8) {
            if let error = viewModel.saveError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Theme.textMuted)
            }
            if let saved = viewModel.savedSummary {
                Label(saved, systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
            Button {
                weightFocused = nil
                confirmingFinish = true
            } label: {
                if viewModel.isSaving {
                    ProgressView().tint(Theme.onAccent)
                } else {
                    Text("Finish workout")
                }
            }
            .buttonStyle(.primary)
            .disabled(viewModel.isSaving || viewModel.savedSummary != nil)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(Theme.background.ignoresSafeArea())
    }

    // MARK: Rows

    private func group(_ row: WorkoutRow) -> String? {
        guard let g = row.exercise.supersetGroup?.trimmingCharacters(in: .whitespaces), !g.isEmpty else { return nil }
        return g
    }

    private func joinedAbove(_ row: WorkoutRow) -> Bool {
        guard let g = group(row), row.id > 0 else { return false }
        return group(viewModel.rows[row.id - 1]) == g
    }

    private func joinedBelow(_ row: WorkoutRow) -> Bool {
        guard let g = group(row), row.id + 1 < viewModel.rows.count else { return false }
        return group(viewModel.rows[row.id + 1]) == g
    }

    /// Rows in a superset share one block: square inner corners, a
    /// hairline gap, and a lime stripe down the left.
    private func shape(_ row: WorkoutRow) -> UnevenRoundedRectangle {
        let r = Theme.rowRadius
        let top: CGFloat = joinedAbove(row) ? 4 : r
        let bottom: CGFloat = joinedBelow(row) ? 4 : r
        return UnevenRoundedRectangle(
            topLeadingRadius: top, bottomLeadingRadius: bottom,
            bottomTrailingRadius: bottom, topTrailingRadius: top
        )
    }

    private func rowView(_ row: WorkoutRow) -> some View {
        let expanded = viewModel.expandedID == row.id
        let exercise = row.exercise
        return VStack(alignment: .leading, spacing: 12) {
            if let g = group(row), !joinedAbove(row) {
                Text("SUPERSET \(g.uppercased())")
                    .font(.caption2.weight(.heavy))
                    .tracking(0.6)
                    .foregroundStyle(Theme.accent)
            }
            HStack(spacing: 12) {
                statusMark(row.status)
                VStack(alignment: .leading, spacing: 3) {
                    Text(exercise.name)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(row.status == .skipped ? Theme.textMuted : Theme.textPrimary)
                        .strikethrough(row.status == .skipped)
                        .lineLimit(expanded ? nil : 1)
                    HStack(spacing: 6) {
                        Text("\(exercise.sets) x \(exercise.reps)")
                        if let target = exercise.target, !target.isEmpty {
                            Text("·")
                            Text(target).foregroundStyle(Theme.accent)
                        }
                        if !row.sets.isEmpty {
                            Text("·")
                            Text("\(row.sets.count) logged")
                        }
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let intensity = exercise.intensity, !intensity.isEmpty {
                    Pill(text: intensity.replacingOccurrences(of: "_", with: " "),
                         fill: Theme.surface3, foreground: Theme.textMuted)
                }
            }
            if expanded {
                detail(row)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(row.status == .done ? Theme.accent.opacity(0.10) : Theme.surface2, in: shape(row))
        .overlay(alignment: .leading) {
            if group(row) != nil {
                Rectangle().fill(Theme.accent).frame(width: 3)
                    .clipShape(shape(row))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { viewModel.toggleExpanded(row.id) }
    }

    @ViewBuilder
    private func statusMark(_ status: RowStatus) -> some View {
        switch status {
        case .done:
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 30, height: 30)
                .background(Theme.accent, in: Circle())
        case .skipped:
            Image(systemName: "forward.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.textMuted)
                .frame(width: 30, height: 30)
                .background(Theme.surface3, in: Circle())
        case .todo:
            Circle()
                .strokeBorder(Theme.textMuted.opacity(0.5), lineWidth: 2)
                .frame(width: 30, height: 30)
        }
    }

    @ViewBuilder
    private func detail(_ row: WorkoutRow) -> some View {
        let exercise = row.exercise
        VStack(alignment: .leading, spacing: 12) {
            if let technique = exercise.technique, !technique.isEmpty {
                Label(technique, systemImage: "hand.point.up.left.fill")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
            }
            if let note = exercise.note, !note.isEmpty {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textMuted)
            }
            if let rest = exercise.restSec, rest > 0 {
                Label("Rest \(Self.clock(TimeInterval(rest))) after each set", systemImage: "timer")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textMuted)
            }

            if !row.sets.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(row.sets.enumerated()), id: \.offset) { index, set in
                        Text("Set \(index + 1): \(WorkoutViewModel.describe(set))")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(Theme.textPrimary)
                    }
                    Button("Undo last set") { viewModel.undoLastSet(row.id) }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textMuted)
                }
            }

            if viewModel.isEndurance {
                Button {
                    viewModel.mark(row.id, .done)
                } label: {
                    Text("Mark done")
                }
                .buttonStyle(.primary)
            } else {
                HStack(spacing: 10) {
                    weightStepper(row)
                    stepper(
                        label: "reps",
                        value: row.reps.map(String.init) ?? "–",
                        minus: { viewModel.stepReps(row.id, by: -1) },
                        plus: { viewModel.stepReps(row.id, by: 1) }
                    )
                }
                Button {
                    weightFocused = nil
                    viewModel.logSet(row.id)
                } label: {
                    Text("Log set \(min(row.sets.count + 1, max(exercise.sets, row.sets.count + 1)))")
                }
                .buttonStyle(.primary)
            }
        }
    }

    /// Weight: −/+ in 2.5 kg steps, or tap the number to type it.
    private func weightStepper(_ row: WorkoutRow) -> some View {
        let binding = Binding<String>(
            get: {
                guard let w = row.weight else { return "" }
                return w == w.rounded() ? String(Int(w)) : String(w)
            },
            set: { text in
                if let index = viewModel.rows.firstIndex(where: { $0.id == row.id }) {
                    viewModel.rows[index].weight = Double(text.replacingOccurrences(of: ",", with: "."))
                }
            }
        )
        return VStack(spacing: 4) {
            HStack(spacing: 0) {
                stepButton("minus") { viewModel.stepWeight(row.id, by: -2.5) }
                TextField("–", text: binding)
                    .keyboardType(.decimalPad)
                    .focused($weightFocused, equals: row.id)
                    .multilineTextAlignment(.center)
                    .font(.title3.weight(.heavy).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity)
                stepButton("plus") { viewModel.stepWeight(row.id, by: 2.5) }
            }
            .padding(6)
            .background(Theme.surface3, in: Capsule())
            Text("kg").font(.caption2.weight(.semibold)).foregroundStyle(Theme.textMuted)
        }
    }

    private func stepper(label: String, value: String, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 0) {
                stepButton("minus", action: minus)
                Text(value)
                    .font(.title3.weight(.heavy).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity)
                stepButton("plus", action: plus)
            }
            .padding(6)
            .background(Theme.surface3, in: Capsule())
            Text(label).font(.caption2.weight(.semibold)).foregroundStyle(Theme.textMuted)
        }
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 36, height: 36)
                .background(Theme.surface2, in: Circle())
        }
        .buttonStyle(.plain)
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

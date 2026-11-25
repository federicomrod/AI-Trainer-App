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
import PhotosUI
import SwiftUI

@MainActor
final class TodayViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var response: TurnResponse?
    @Published var errorMessage: String?
    /// Headline above `errorMessage`. Set alongside it, because not
    /// every failure is a network failure: a server that answered
    /// perfectly well and rejected its own decision was still being
    /// announced as "Couldn't reach the coach", which sent us looking
    /// at the network for a problem that was never there.
    @Published var errorTitle = "Couldn't reach the coach"
    @Published var errorSymbol = "wifi.exclamationmark"
    @Published var messageDraft = ""
    @Published var pendingMessage: String?
    /// The message whose turn failed, kept so it can be retried.
    @Published var failedMessage: String?

    func retryFailedSend() async {
        let message = failedMessage ?? ""
        failedMessage = nil
        await send(message: message)
    }
    @Published var photoPickerItem: PhotosPickerItem?
    #if os(iOS)
    @Published var attachedImage: UIImage?
    #endif

    private let client = APIClient()

    /// Goals in priority order, from GET /goals. Empty until loaded.
    @Published var goals: [String] = []

    /// Today's session row from GET /day: whether it's already done,
    /// what was logged, and what a decision changed it to. nil when
    /// nothing is on record for today (a 404) or before it loads.
    @Published var todayDay: DayDetailResponse?

    func loadTodayDay() async {
        do {
            todayDay = try await client.fetchDay(date: DayLabel.todayISO)
        } catch APIError.http(404) {
            todayDay = nil
        } catch {
            // Keep what was there; the decision card still works.
        }
    }

    /// Today's session is finished (done, partial or logged off-plan),
    /// and it wasn't a rest day.
    var todayIsDone: Bool {
        guard let day = todayDay, let status = day.status,
              ["done", "partial", "unplanned"].contains(status) else { return false }
        return (day.actualType ?? "").lowercased() != "rest"
    }

    /// Goals for the card under the session. Progress bars are only
    /// drawn from real numbers, and /goals is plain text with no
    /// baseline or target, so for now the card lists the text only.
    func loadGoals() async {
        goals = (try? await client.fetchGoals().goals) ?? goals
    }

    #if os(iOS)
    func loadAttachedImage() async {
        guard let item = photoPickerItem else { return }
        photoPickerItem = nil
        if let data = try? await item.loadTransferable(type: Data.self) {
            attachedImage = UIImage(data: data)
        }
    }

    var hasAttachment: Bool { attachedImage != nil }
    #else
    var hasAttachment: Bool { false }
    #endif

    func loadToday() async {
        await send(message: "")
    }

    func sendDraft() async {
        let text = messageDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || hasAttachment else { return }
        messageDraft = ""
        #if os(iOS)
        let imageBase64 = attachedImage?.jpegBase64ForUpload()
        attachedImage = nil
        #else
        let imageBase64: String? = nil
        #endif
        await send(message: text, imageBase64: imageBase64)
        // What was said can mark today done ("did legs, 60 min").
        await loadTodayDay()
    }

    /// True when what's on screen came from the cache rather than the
    /// backend just now.
    @Published var isShowingCached = false
    @Published var cachedAt: Date?

    /// Opening screen when the backend is known to be unreachable: show
    /// the remembered decision immediately rather than spending a
    /// timeout rediscovering that it's still down.
    func loadCachedIfOffline() -> Bool {
        guard ConnectionState.shared.isOffline,
              let cached = Cache.load(TurnResponse.self, for: .today)
        else { return false }
        response = cached
        cachedAt = Cache.savedAt(.today)
        isShowingCached = true
        return true
    }

    private func send(message: String, imageBase64: String? = nil) async {
        isLoading = true
        errorMessage = nil
        // What the athlete just said, held only while the call is in
        // flight. Without this Today gives no sign at all that a
        // message went anywhere: the decision card silently swaps for
        // the next one, and an unchanged KEEP looks identical to
        // having sent nothing.
        pendingMessage = message.isEmpty ? nil : message
        defer { pendingMessage = nil }
        failedMessage = nil
        do {
            let result = try await client.turn(message: message, imageBase64: imageBase64)
            response = result
            // The backend can succeed at the HTTP level but still
            // report a failure inside the JSON (planner_error when the
            // model call itself failed, validation_error when the
            // decision was rejected) -- surface that the same way as a
            // network failure, since neither case has anything safe to
            // show as "today's plan".
            if let problem = result.userFacingError {
                // It answered -- it just couldn't produce a session.
                errorTitle = "The coach couldn't answer"
                errorSymbol = "exclamationmark.triangle"
                // Corrections are written before the model call, so
                // say what was saved even when the answer failed.
                errorMessage = [result.savedUpdates, problem]
                    .compactMap { $0 }
                    .joined(separator: "\n\n")
            } else {
                // Only remember a decision that's actually usable --
                // caching an error would mean opening to it tomorrow.
                Cache.save(result, for: .today)
                isShowingCached = false
                cachedAt = nil
            }
        } catch {
            switch error {
            case APIError.timedOut:
                errorTitle = "The coach took too long"
                errorSymbol = "clock.badge.exclamationmark"
            case APIError.unreachable:
                errorTitle = "Couldn't reach the coach"
                errorSymbol = "wifi.exclamationmark"
            default:
                errorTitle = "Something went wrong"
                errorSymbol = "exclamationmark.triangle"
            }
            errorMessage = error.localizedDescription
            // Hold on to what they said so Retry can resend it. Without
            // this a failed turn loses the message: the thinking
            // indicator just disappears and there's nothing to press.
            failedMessage = message
            // Fall back to the last good decision rather than leaving
            // the screen empty behind an error.
            if response == nil, let cached = Cache.load(TurnResponse.self, for: .today) {
                response = cached
                cachedAt = Cache.savedAt(.today)
                isShowingCached = true
            }
        }
        isLoading = false
    }
}

struct TodayView: View {
    @StateObject private var viewModel = TodayViewModel()
    // Owned here, not by the button, so the send arrow can finish a
    // recording in progress rather than sending around it.
    @StateObject private var voice = SpeechRecognizer()
    @State private var showingCheckIn = false
    @State private var showingLogSession = false
    @State private var showingGoals = false
    @State private var showingSettings = false
    @State private var showingWhyDetail = false
    @State private var showingWorkout = false
    /// See ChatView: the keyboard covers the tab bar, so there has to
    /// be a way to put it away.
    @FocusState private var draftFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if viewModel.isShowingCached {
                        OfflineBanner(savedAt: viewModel.cachedAt) {
                            Task { await viewModel.loadToday() }
                        }
                    }
                    content
                    goalsCard
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .appBackground()
            .scrollContentBackground(.hidden)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture { draftFocused = false }
            .toolbar {
                // Check in, Log session and Goals are labelled buttons
                // under the title now; only Settings stays an icon.
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
            .sheet(isPresented: $showingLogSession, onDismiss: {
                Task { await viewModel.loadTodayDay() }
            }) {
                LogSessionView()
            }
            .sheet(isPresented: $showingGoals, onDismiss: {
                Task { await viewModel.loadGoals() }
            }) {
                GoalsView()
            }
            .fullScreenCover(isPresented: $showingWorkout, onDismiss: {
                // Finishing a workout logs today: swap Start for done.
                Task { await viewModel.loadTodayDay() }
            }) {
                if let decision = viewModel.response?.decision {
                    WorkoutView(session: decision.today,
                                title: displayName(sessionType(for: decision)))
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    sendingBanner
                    sendFailedBanner
                    attachmentPreview
                    messageBar
                }
            }
            .task {
                await viewModel.loadGoals()
                await viewModel.loadTodayDay()
            }
            #if DEBUG
            // Screenshots only: `-screenshotWorkout YES` opens the
            // workout a few seconds after today's session arrives.
            .onChange(of: viewModel.response?.decision?.today.exercises.count) {
                guard UserDefaults.standard.bool(forKey: "screenshotWorkout"),
                      viewModel.response?.decision != nil else { return }
                Task {
                    try? await Task.sleep(for: .seconds(6))
                    showingWorkout = true
                }
            }
            #endif
            .task {
                if viewModel.response == nil, !viewModel.loadCachedIfOffline() {
                    await viewModel.loadToday()
                }
            }
            #if os(iOS)
            .onChange(of: viewModel.photoPickerItem) {
                Task { await viewModel.loadAttachedImage() }
            }
            #endif
        }
    }

    // Sits directly above the input, where the athlete is already
    // looking after speaking: what was heard, and that the coach has
    // it. The model call runs 10-30 seconds, so silence here reads as
    // a dropped message.
    @ViewBuilder
    private var sendingBanner: some View {
        if viewModel.isLoading, let pending = viewModel.pendingMessage {
            HStack(alignment: .top, spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .tint(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sent — coach is thinking…")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                    Text(pending)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(3)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal)
            .padding(.top, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appBackground()
        }
    }

    // A turn that failed while an earlier decision is still on screen
    // would otherwise be invisible: content shows the old decision, so
    // errorContent never renders, and the thinking indicator simply
    // vanishes. That's the "hangs forever" complaint wearing a
    // different hat -- this is the bounded, retryable end of it.
    @ViewBuilder
    private var sendFailedBanner: some View {
        if !viewModel.isLoading, viewModel.response != nil,
           let message = viewModel.errorMessage {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.accent)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
                Button("Retry") {
                    Task { await viewModel.retryFailedSend() }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.accent)
            }
            .padding(.horizontal)
            .padding(.top, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appBackground()
        }
    }

    @ViewBuilder
    private var attachmentPreview: some View {
        #if os(iOS)
        if let image = viewModel.attachedImage {
            HStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Text("Screenshot attached")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Button {
                    viewModel.attachedImage = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.horizontal)
            .padding(.top, 10)
            .appBackground()
        }
        #endif
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.todayIsDone, let day = viewModel.todayDay {
            // Done is a fact on record: no need to wait for the coach.
            doneCard(day)
            if let response = viewModel.response, response.error == nil {
                ForEach(Array(response.segments.filter { !$0.isHeadCoach }.enumerated()), id: \.offset) { _, segment in
                    specialistBlock(segment)
                }
            }
        } else if viewModel.isLoading && viewModel.response == nil {
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
            Label(viewModel.errorTitle, systemImage: viewModel.errorSymbol)
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text(message)
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
            Button("Try again") {
                Task { await viewModel.loadToday() }
            }
            .buttonStyle(.primary)
        }
        .padding(.top, 40)
    }

    /// Small date label over a big heavy "Today", then the three
    /// things you can do from here, each with its name on it.
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(DayLabel.from(date: .now))
                    .eyebrowStyle()
                Text("Today")
                    .screenTitleStyle()
            }
            ChipFlow(spacing: 8) {
                actionChip("Check in", "checkmark.circle") { showingCheckIn = true }
                actionChip("Log session", "square.and.pencil") { showingLogSession = true }
                actionChip("Goals", "target") { showingGoals = true }
            }
        }
    }

    private func actionChip(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(Theme.font(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Theme.surface2, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func decisionContent(_ response: TurnResponse) -> some View {
        if let decision = response.decision {
            heroCard(decision, coachLine: decision.why)
        } else if let first = response.segments.first {
            // Safety-flagged turns have no decision, only the coach's words.
            Text(first.text)
                .font(Theme.font(.title3, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .heroCard()
        }

        // A specialist chiming in stays visible under the card. The
        // head coach's full reply lives in Coach chat; the card keeps
        // to the short `why`.
        ForEach(Array(response.segments.filter { !$0.isHeadCoach }.enumerated()), id: \.offset) { _, segment in
            specialistBlock(segment)
        }
    }

    /// The one card for today: what, how long, one coaching line, the
    /// exercises as chips, "Why this", and the big Start button.
    private func heroCard(_ decision: Decision, coachLine: String) -> some View {
        let session = decision.today
        let titleType = sessionType(for: decision)
        let isRest = decision.decision == "REST" || titleType.lowercased() == "rest"
        let tint = SessionTypeIcon.tint(for: titleType)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: SessionTypeIcon.symbolName(for: isRest ? "rest" : titleType))
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 48, height: 48)
                    .background(tint.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(isRest ? "Rest" : displayName(titleType))
                        .font(.system(.title2).weight(.heavy))
                        .tracking(-0.5)
                        .foregroundStyle(Theme.textPrimary)
                    if !isRest {
                        Text("\(session.durationMin) min")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textMuted)
                    }
                }
                Spacer()
                // Only worth a word when the plan was actually changed.
                if decision.decision == "MODIFY" {
                    Pill(text: "Changed", fill: Theme.accent.opacity(0.18), foreground: Theme.accent)
                }
            }

            Text(coachLine)
                .font(.callout)
                .lineLimit(4)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if !session.exercises.isEmpty {
                // The same table as the workout card in Coach chat.
                ExerciseTable(exercises: session.exercises, leadingDivider: false)
                    .background(Theme.surface1, in: RoundedRectangle(cornerRadius: Theme.rowRadius))
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showingWhyDetail.toggle() }
            } label: {
                Label("Why this", systemImage: showingWhyDetail ? "chevron.up" : "questionmark.circle")
            }
            .buttonStyle(.secondary)

            if showingWhyDetail {
                whyDetail(decision.reasons)
            }

            if !isRest && !session.exercises.isEmpty {
                Button {
                    showingWorkout = true
                } label: {
                    Label("Start workout", systemImage: "play.fill")
                }
                .buttonStyle(.primary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .heroCard()
    }

    // A specialist's own line, marked by its icon and name
    // (SpeakerStyle), same as in Coach chat.
    private func specialistBlock(_ segment: MessageSegment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(SpeakerStyle.label(for: segment.speaker).uppercased(), systemImage: SpeakerStyle.icon(for: segment.speaker))
                .font(.caption2.bold())
                .foregroundStyle(Theme.accent)
            Text(segment.text)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .flatCard()
    }

    // The real inputs behind the call, in plain language (the
    // decision's `reasons`), not the raw briefing.
    @ViewBuilder
    private func whyDetail(_ reasons: [Reason]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if reasons.isEmpty {
                Text("No further detail for this call.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(reasons) { reason in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: reason.symbolName)
                        .font(.footnote)
                        .foregroundStyle(reason.direction == "caution" ? Theme.accent : Theme.textSecondary)
                        .padding(.top, 1)
                    Text(reason.factor)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rowCard(fill: Theme.surface3)
    }

    private func displayName(_ type: String) -> String {
        SessionTitle.display(type)
    }

    /// What to call today's session. The coach's plan type when it
    /// names one ("legs"); when it only says "gym", today's own
    /// session from the week names it better (the changed one, if a
    /// decision changed it).
    private func sessionType(for decision: Decision) -> String {
        let planned = decision.today.type
        if SessionTitle.isGeneric(planned), let day = viewModel.todayDay?.actualType, !day.isEmpty {
            return day
        }
        return planned
    }

    /// Today is already done: what it was, how long, what was logged.
    /// No Start button.
    private func doneCard(_ day: DayDetailResponse) -> some View {
        let type = day.actualType ?? "session"
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "checkmark")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(Theme.onAccent)
                    .frame(width: 48, height: 48)
                    .background(Theme.accent, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName(type))
                        .font(.system(.title2).weight(.heavy))
                        .tracking(-0.5)
                        .foregroundStyle(Theme.textPrimary)
                    if let minutes = day.durationMin, minutes > 0 {
                        Text("\(minutes) min")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textMuted)
                    }
                }
                Spacer()
                Pill(text: day.status == "partial" ? "Partly done" : "Done",
                     fill: Theme.accent.opacity(0.18), foreground: Theme.accent)
            }

            if let from = day.type, day.movedTo != nil, from.lowercased() != type.lowercased() {
                Label("Changed from \(displayName(from))", systemImage: "arrow.triangle.branch")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textMuted)
            }

            if !day.lifts.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(day.lifts.enumerated()), id: \.offset) { index, lift in
                        if index > 0 { Divider().overlay(Color.white.opacity(0.06)) }
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(lift.exerciseName.plainHyphens)
                                .font(Theme.font(.body, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            Text(liftNumbers(lift))
                                .font(Theme.font(.body, weight: .heavy))
                                .monospacedDigit()
                                .foregroundStyle(Theme.textPrimary)
                                .fixedSize()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
                .background(Theme.surface1, in: RoundedRectangle(cornerRadius: Theme.rowRadius))
            }

            if let summary = day.actualSummary, !summary.isEmpty {
                Text(summary.plainHyphens)
                    .font(.callout)
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .heroCard()
    }

    /// "3 x 10 · 40 kg" from what was logged; only the parts that exist.
    private func liftNumbers(_ lift: DayLift) -> String {
        var parts: [String] = []
        switch (lift.sets, lift.reps) {
        case let (s?, r?): parts.append("\(s) x \(r)")
        case let (nil, r?): parts.append("\(r) reps")
        case let (s?, nil): parts.append("\(s) sets")
        default: break
        }
        if let w = lift.weight {
            parts.append(WorkoutViewModel.formatKg(w))
        }
        return parts.isEmpty ? "logged" : parts.joined(separator: " · ")
    }

    /// Goals in priority order. Text only: there is no measured
    /// baseline or target behind them yet, so no bar is drawn.
    /// Tapping opens the goal editor.
    @ViewBuilder
    private var goalsCard: some View {
        if !viewModel.goals.isEmpty {
            Button {
                showingGoals = true
            } label: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Goals")
                            .font(.system(.title3).weight(.heavy))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.textMuted)
                    }
                    ForEach(Array(viewModel.goals.enumerated()), id: \.offset) { index, goal in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(index + 1)")
                                .font(.caption.weight(.heavy))
                                .foregroundStyle(index == 0 ? Theme.onAccent : Theme.textMuted)
                                .frame(width: 22, height: 22)
                                .background(index == 0 ? Theme.accent : Theme.surface3, in: Circle())
                            Text(goal)
                                .font(.subheadline)
                                .foregroundStyle(Theme.textPrimary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .rowCard()
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .flatCard()
            }
            .buttonStyle(.plain)
        }
    }

    private var messageBar: some View {
        VStack(spacing: 12) {
            // Voice lives in the big centre mic of the tab bar now
            // (it opens Coach). Typing stays here. Open-ended copy on
            // purpose -- a bad night's sleep, a stressful week,
            // travel, none of it is "fitness," but all of it changes
            // what today should look like.
            HStack(spacing: 8) {
                TextField("Or type: what's going on?", text: $viewModel.messageDraft, axis: .vertical)
                    .focused($draftFocused)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .padding(9)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1...3)
                if draftFocused {
                    // See ChatView: the keyboard's own toolbar doesn't
                    // reach a field inside a safeAreaInset, so the way
                    // out lives here.
                    Button {
                        draftFocused = false
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .accessibilityLabel("Hide keyboard")
                }
                PhotosPicker(selection: $viewModel.photoPickerItem, matching: .images) {
                    Image(systemName: "photo.on.rectangle")
                        .foregroundStyle(Theme.textSecondary)
                }
                Button {
                    // Mid-recording, "send" means finish and send what
                    // was said -- the take submits itself when it ends.
                    if voice.isActive {
                        Task { await voice.finish() }
                    } else {
                        draftFocused = false
                        Task { await viewModel.sendDraft() }
                    }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                }
                .disabled(
                    (viewModel.messageDraft.trimmingCharacters(in: .whitespaces).isEmpty
                        && !viewModel.hasAttachment && !voice.isActive)
                    || viewModel.isLoading
                    || voice.phase == .finishing
                )
            }
        }
        .padding()
        .appBackground()
    }
}

#Preview {
    TodayView()
}

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
    /// See ChatView: the keyboard covers the tab bar, so there has to
    /// be a way to put it away.
    @FocusState private var draftFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if viewModel.isShowingCached {
                        OfflineBanner(savedAt: viewModel.cachedAt) {
                            Task { await viewModel.loadToday() }
                        }
                    }
                    content
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .appBackground()
            .scrollContentBackground(.hidden)
            .navigationTitle("Today")
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture { draftFocused = false }
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
            .sheet(isPresented: $showingLogSession) {
                LogSessionView()
            }
            .sheet(isPresented: $showingGoals) {
                GoalsView()
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
            Label(viewModel.errorTitle, systemImage: viewModel.errorSymbol)
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text(message)
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
            Button("Try again") {
                Task { await viewModel.loadToday() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.top, 40)
    }

    @ViewBuilder
    private func decisionContent(_ response: TurnResponse) -> some View {
        // The decision itself is the hero of this screen -- the one
        // thing the accent color gets spent on here. Every decision
        // gets the same treatment regardless of KEEP/MODIFY/REST:
        // color-coding "which decision" would read as a status score,
        // which this app deliberately doesn't do anywhere.
        if let decision = response.decision {
            HStack {
                Text(decision.decision)
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Theme.accent.opacity(0.18))
                    .foregroundStyle(Theme.accent)
                    .clipShape(Capsule())
                Spacer()
            }
        }

        ForEach(Array(response.segments.enumerated()), id: \.offset) { index, segment in
            if index == 0 {
                // Bold, confident type for the one thing that matters
                // on this screen -- the coach's actual call for today.
                // Tappable: reveals the real inputs behind the call
                // (soreness, this week's plan, recent load) rather
                // than asking the athlete to just trust one line.
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingWhyDetail.toggle()
                    }
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Text(segment.text)
                            .font(Theme.rounded(.title3, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                        Image(systemName: showingWhyDetail ? "chevron.up" : "chevron.down")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.top, 4)
                    }
                }
                .buttonStyle(.plain)

                if showingWhyDetail {
                    whyDetail(response.decision?.reasons ?? [])
                }
            } else {
                specialistBlock(segment)
            }
        }

        if let decision = response.decision,
           decision.decision != "REST",
           !decision.today.exercises.isEmpty {
            sessionCard(decision.today)
        }
    }

    // A specialist's own line, distinguished from Head Coach's by its
    // own icon + name (SpeakerStyle, per coach-voice.md's cast) rather
    // than a color -- same treatment as Coach chat, so the two screens
    // read consistently.
    private func specialistBlock(_ segment: MessageSegment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(SpeakerStyle.label(for: segment.speaker).uppercased(), systemImage: SpeakerStyle.icon(for: segment.speaker))
                .font(.caption2.bold())
                .foregroundStyle(Theme.accent)
            Text(segment.text)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.top, 2)
    }

    // The actual inputs behind the call, in plain language -- not the
    // raw briefing (that's developer debug output; see Settings >
    // Developer for that). Each reason is a short factor from the
    // briefing plus whether it backed today's call or was a reason for
    // caution, so tapping "why" shows real substance instead of a text
    // dump the athlete never asked for.
    @ViewBuilder
    private func whyDetail(_ reasons: [Reason]) -> some View {
        if reasons.isEmpty {
            Text("No further detail for this call.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .flatCard()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(reasons) { reason in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: reason.symbolName)
                            .font(.footnote)
                            .foregroundStyle(reason.direction == "caution" ? Theme.accent : Theme.textSecondary)
                            .padding(.top, 1)
                        Text(reason.factor)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .flatCard()
        }
    }

    @ViewBuilder
    private func sessionCard(_ session: TodaySession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: SessionTypeIcon.symbolName(for: session.type))
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                Text(session.type.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(Theme.rounded(.headline, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(session.durationMin) min")
                    .foregroundStyle(Theme.textSecondary)
            }
            if !session.intensityNote.isEmpty {
                Text(session.intensityNote)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            Divider().overlay(Theme.textSecondary.opacity(0.2))
            ForEach(session.exercises) { exercise in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(exercise.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text("\(exercise.sets) x \(exercise.reps)")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    if let note = exercise.note, !note.isEmpty {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .heroCard()
    }

    private var messageBar: some View {
        VStack(spacing: 12) {
            // Primary: the main way to talk to the coach.
            VoiceInputButton(recognizer: voice, text: $viewModel.messageDraft) {
                Task { await viewModel.sendDraft() }
            }

            // Secondary: typing stays fully available, just visually
            // smaller now that voice leads. Open-ended copy on
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

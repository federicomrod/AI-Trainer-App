//
//  ChatView.swift
//  AI-Trainer
//
//  M1's second screen: the full conversation with the coach, not just
//  today's single decision. History comes from GET /messages -- the
//  conversation lives in the backend's database, not on the phone, so
//  this is what makes that visible and lets you keep talking to it.
//  Sending a message uses the same POST /turn as the Today screen;
//  this view just also keeps the running thread instead of only the
//  latest answer.

import Combine
import PhotosUI
import SwiftUI

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isLoadingHistory = false
    @Published var isSending = false
    @Published var draft = ""
    @Published var errorMessage: String?
    @Published var photoPickerItem: PhotosPickerItem?
    #if os(iOS)
    @Published var attachedImage: UIImage?
    /// Screenshots already sent, by the message id they were sent
    /// with, so the bubble can show what went with the message. The
    /// backend doesn't store the image (it's consumed by the one model
    /// call), so this only lasts as long as the screen does -- a
    /// reload from history shows the text alone.
    @Published var sentImages: [Int: UIImage] = [:]
    #endif

    private let client = APIClient()

    func loadHistory() async {
        isLoadingHistory = true
        errorMessage = nil
        do {
            messages = try await client.fetchHistory()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingHistory = false
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

    func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || hasAttachment, !isSending else { return }
        draft = ""
        errorMessage = nil

        // Optimistic echo: show what was just typed immediately rather
        // than waiting on the model call before anything appears.
        // Negative ids keep these out of the way of real server ids,
        // which loadHistory() would otherwise duplicate against.
        let placeholderID = -(messages.count + 1)
        let echoText = text.isEmpty ? "📷 Screenshot" : text
        messages.append(ChatMessage(id: placeholderID, role: "user", text: echoText, timestamp: "", segments: []))

        #if os(iOS)
        let imageBase64 = attachedImage?.jpegBase64ForUpload()
        if let image = attachedImage { sentImages[placeholderID] = image }
        attachedImage = nil
        #else
        let imageBase64: String? = nil
        #endif

        isSending = true
        do {
            let result = try await client.turn(message: text, imageBase64: imageBase64)
            if let reply = result.reply {
                messages.append(ChatMessage(
                    id: placeholderID - 1, role: "assistant", text: reply, timestamp: "",
                    segments: result.segments,
                    cards: result.cards,
                    // A live turn carries the workout inside the decision.
                    workout: result.cards.contains("workout") ? result.decision?.today : nil,
                    weekPlan: result.weekPlan
                ))
            } else {
                // planner_error or validation_error: nothing safe to
                // show as the coach's reply. Surface it inline rather
                // than pretending the exchange completed normally.
                // Name what was written even though the reply failed
                // -- the rows are already in the database.
                errorMessage = [result.savedUpdates, result.userFacingError ?? "No reply."]
                    .compactMap { $0 }
                    .joined(separator: "\n\n")
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isSending = false
    }
}

struct ChatView: View {
    @StateObject private var viewModel = ChatViewModel()
    // Owned by MainTabView, so the big centre mic in the tab bar can
    // start a take here; observed here so the send arrow can still
    // finish a recording in progress rather than sending around it.
    @ObservedObject var voice: SpeechRecognizer
    /// Whether the typing field holds the keyboard. Tracked explicitly
    /// because the keyboard covers the tab bar while it's up: with no
    /// way to put it away, the app was unusable until it was
    /// force-quit. Three ways out now -- Done on the keyboard's own
    /// toolbar, dragging the conversation, and sending.
    @FocusState private var draftFocused: Bool
    /// A workout opened from a chat card's header.
    @State private var workoutLaunch: ChatWorkoutLaunch?
    #if DEBUG
    private static var didDebugSend = false
    #endif

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if viewModel.isLoadingHistory && viewModel.messages.isEmpty {
                            ProgressView("Loading conversation…")
                                .frame(maxWidth: .infinity)
                                .padding(.top, 60)
                        }
                        ForEach(viewModel.messages) { message in
                            exchange(message)
                                .id(message.id)
                        }
                        if viewModel.isSending {
                            typingIndicator
                        }
                        if let error = viewModel.errorMessage {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding()
                }
                .scrollContentBackground(.hidden)
                .appBackground()
                .scrollDismissesKeyboard(.interactively)
                .onTapGesture { draftFocused = false }
                .onChange(of: viewModel.messages.count) {
                    scrollToBottom(proxy)
                }
                .onChange(of: viewModel.isSending) {
                    scrollToBottom(proxy)
                }
                #if DEBUG
                // Screenshots only: `-chatScrollTo <message id>` shows
                // that message at the top once history has loaded.
                .task(id: viewModel.messages.count) {
                    let target = UserDefaults.standard.integer(forKey: "chatScrollTo")
                    guard target != 0, viewModel.messages.contains(where: { $0.id == target }) else { return }
                    try? await Task.sleep(for: .seconds(1))
                    proxy.scrollTo(target, anchor: .top)
                }
                #endif
            }
            .navigationTitle("Coach")
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    attachmentPreview
                    messageBar
                }
            }
            .task {
                if viewModel.messages.isEmpty {
                    await viewModel.loadHistory()
                }
                #if DEBUG
                // Simulator checks only: `-chatSendOnLaunch "text"` sends
                // one message once, through the normal send path.
                if !ChatView.didDebugSend,
                   let text = UserDefaults.standard.string(forKey: "chatSendOnLaunch"), !text.isEmpty {
                    ChatView.didDebugSend = true
                    viewModel.draft = text
                    await viewModel.send()
                }
                #endif
            }
            .fullScreenCover(item: $workoutLaunch) { launch in
                WorkoutView(session: launch.session)
            }
            #if os(iOS)
            .onChange(of: viewModel.photoPickerItem) {
                Task { await viewModel.loadAttachedImage() }
            }
            #endif
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

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let last = viewModel.messages.last else { return }
        withAnimation {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    // One exchange (one row from GET /messages) can render as several
    // bubbles -- Head Coach plus a specialist chiming in are two
    // different voices, not one paragraph with an inline bold label.
    // Tight spacing between them reads as one back-and-forth moment;
    // the looser spacing between *exchanges* (set by the outer
    // LazyVStack) is what separates one turn from the next.
    @ViewBuilder
    private func exchange(_ message: ChatMessage) -> some View {
        if message.isUser {
            #if os(iOS)
            bubble(text: message.text, isUser: true,
                   image: viewModel.sentImages[message.id])
            #else
            bubble(text: message.text, isUser: true)
            #endif
        } else {
            VStack(alignment: .leading, spacing: 10) {
                if message.segments.isEmpty {
                    // Defensive fallback -- shouldn't happen once the
                    // backend always returns segments, but a message
                    // with no segments should still show something
                    // rather than vanish.
                    bubble(text: message.text, isUser: false)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(message.segments) { segment in
                            assistantBubble(segment)
                        }
                    }
                }
                cards(for: message)
            }
        }
    }

    // The structured cards under a reply, full chat width (wider than
    // the bubble) so a table has room. Text stays above.
    @ViewBuilder
    private func cards(for message: ChatMessage) -> some View {
        if let workout = message.workoutCard {
            let startable = message.isFromToday && workout.type.lowercased() != "rest"
            WorkoutTableCard(
                session: workout,
                onStart: startable ? { workoutLaunch = ChatWorkoutLaunch(session: workout) } : nil
            )
        }
        if let week = message.weekCard {
            WeekPlanCard(days: week)
        }
    }

    // Rounder, softer, tighter padding than a generic chat-UI bubble --
    // borrowing iMessage/WhatsApp's instinct that a message from a
    // person is compact and gently shaped, not a wide rectangular card.
    private func bubble(text: String, isUser: Bool, image: UIImage? = nil) -> some View {
        HStack {
            if isUser { Spacer(minLength: 50) }
            VStack(alignment: .trailing, spacing: 6) {
                // The screenshot rides inside the bubble, so "I sent a
                // picture" is something you can see rather than take on
                // faith -- previously the only sign was the word
                // "Screenshot" in the text.
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: 180, maxHeight: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .accessibilityLabel("Screenshot sent with this message")
                }
                Text(text)
                    .foregroundStyle(isUser ? Theme.onAccent : Theme.textPrimary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                isUser ? Theme.accent : Theme.card,
                in: RoundedRectangle(cornerRadius: 20)
            )
            if !isUser { Spacer(minLength: 50) }
        }
    }

    // Every speaker gets the same treatment now: a small icon + name
    // (SpeakerStyle, per coach-voice.md's cast), consistent every time
    // that voice appears -- the previous tiny dot for Head Coach read
    // as barely-there. A specialist's bubble also gets a slightly
    // different card tone and a colored left-edge bar, so a multi-
    // voice moment reads as someone else chiming in at a glance, not
    // just a smaller caption above the same-looking bubble.
    @ViewBuilder
    private func assistantBubble(_ segment: MessageSegment) -> some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 4) {
                Label(SpeakerStyle.label(for: segment.speaker).uppercased(), systemImage: SpeakerStyle.icon(for: segment.speaker))
                    .font(.caption2.bold())
                    .foregroundStyle(Theme.accent)
                Text(segment.text)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        segment.isHeadCoach ? Theme.card : Theme.cardElevated,
                        in: RoundedRectangle(cornerRadius: 20)
                    )
                    .overlay(alignment: .leading) {
                        if !segment.isHeadCoach {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Theme.accent)
                                .frame(width: 3)
                                .padding(.vertical, 6)
                        }
                    }
            }
            Spacer(minLength: 50)
        }
    }

    private var typingIndicator: some View {
        HStack {
            ProgressView()
            Text("Coach is thinking…")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
        }
    }

    private var messageBar: some View {
        VStack(spacing: 12) {
            // Started from the centre mic in the tab bar. Always in the
            // view tree, because it is what turns a finished take into
            // a sent message; drawn only while a take is under way (or
            // to show a voice error), so there aren't two big mics.
            VoiceInputButton(recognizer: voice, text: $viewModel.draft) {
                Task { await viewModel.send() }
            }
            .frame(height: voice.isActive || voice.errorMessage != nil ? nil : 0)
            .opacity(voice.isActive || voice.errorMessage != nil ? 1 : 0)
            .clipped()

            // Secondary: typing stays fully available, just visually
            // smaller now that voice leads.
            HStack(spacing: 8) {
                TextField("Or type…", text: $viewModel.draft, axis: .vertical)
                    .focused($draftFocused)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .padding(9)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1...3)
                if draftFocused {
                    // The way out of the keyboard. It sits in the bar
                    // rather than on the keyboard's own toolbar,
                    // because a ToolbarItemGroup(placement: .keyboard)
                    // never appears for a field inside a
                    // safeAreaInset -- checked in the Simulator, not
                    // assumed. Shown only while the keyboard is up.
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
                        Task { await viewModel.send() }
                    }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                }
                .disabled(
                    (viewModel.draft.trimmingCharacters(in: .whitespaces).isEmpty
                        && !viewModel.hasAttachment && !voice.isActive)
                    || viewModel.isSending
                    || voice.phase == .finishing
                )
            }
        }
        .padding()
        .appBackground()
    }
}

#Preview {
    ChatView(voice: SpeechRecognizer())
}

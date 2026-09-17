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
        messages.append(ChatMessage(id: placeholderID, role: "user", text: echoText, timestamp: ""))

        #if os(iOS)
        let imageBase64 = attachedImage?.jpegBase64ForUpload()
        attachedImage = nil
        #else
        let imageBase64: String? = nil
        #endif

        isSending = true
        do {
            let result = try await client.turn(message: text, imageBase64: imageBase64)
            if let reply = result.reply {
                messages.append(ChatMessage(
                    id: placeholderID - 1, role: "assistant", text: reply, timestamp: ""
                ))
            } else {
                // planner_error or validation_error: nothing safe to
                // show as the coach's reply. Surface it inline rather
                // than pretending the exchange completed normally.
                errorMessage = result.errorDetail ?? result.error ?? "No reply."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isSending = false
    }
}

struct ChatView: View {
    @StateObject private var viewModel = ChatViewModel()

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
                            bubble(message)
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
                .background(Theme.background)
                .onChange(of: viewModel.messages.count) {
                    scrollToBottom(proxy)
                }
                .onChange(of: viewModel.isSending) {
                    scrollToBottom(proxy)
                }
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
            .background(Theme.background)
        }
        #endif
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let last = viewModel.messages.last else { return }
        withAnimation {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    // Rounder, softer, tighter padding than a generic chat-UI bubble --
    // borrowing iMessage/WhatsApp's instinct that a message from a
    // person is compact and gently shaped, not a wide rectangular card.
    @ViewBuilder
    private func bubble(_ message: ChatMessage) -> some View {
        HStack {
            if message.isUser { Spacer(minLength: 50) }
            Text(message.text)
                .foregroundStyle(message.isUser ? Theme.background : Theme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    message.isUser ? Theme.accent : Theme.card,
                    in: RoundedRectangle(cornerRadius: 20)
                )
            if !message.isUser { Spacer(minLength: 50) }
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
        HStack(spacing: 8) {
            TextField("Message the coach…", text: $viewModel.draft, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(10)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1...4)
            PhotosPicker(selection: $viewModel.photoPickerItem, matching: .images) {
                Image(systemName: "photo.on.rectangle")
                    .font(.title3)
                    .foregroundStyle(Theme.textSecondary)
            }
            VoiceInputButton(text: $viewModel.draft)
            Button {
                Task { await viewModel.send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .disabled(
                (viewModel.draft.trimmingCharacters(in: .whitespaces).isEmpty && !viewModel.hasAttachment)
                || viewModel.isSending
            )
        }
        .padding()
        .background(Theme.background)
    }
}

#Preview {
    ChatView()
}

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
import SwiftUI

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isLoadingHistory = false
    @Published var isSending = false
    @Published var draft = ""
    @Published var errorMessage: String?

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

    func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        draft = ""
        errorMessage = nil

        // Optimistic echo: show what was just typed immediately rather
        // than waiting on the model call before anything appears.
        // Negative ids keep these out of the way of real server ids,
        // which loadHistory() would otherwise duplicate against.
        let placeholderID = -(messages.count + 1)
        messages.append(ChatMessage(id: placeholderID, role: "user", text: text, timestamp: ""))

        isSending = true
        do {
            let result = try await client.turn(message: text)
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
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) {
                    scrollToBottom(proxy)
                }
                .onChange(of: viewModel.isSending) {
                    scrollToBottom(proxy)
                }
            }
            .navigationTitle("Coach")
            .safeAreaInset(edge: .bottom) { messageBar }
            .task {
                if viewModel.messages.isEmpty {
                    await viewModel.loadHistory()
                }
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let last = viewModel.messages.last else { return }
        withAnimation {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    @ViewBuilder
    private func bubble(_ message: ChatMessage) -> some View {
        HStack {
            if message.isUser { Spacer(minLength: 40) }
            Text(message.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    message.isUser ? Color.accentColor : Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 16)
                )
                .foregroundStyle(message.isUser ? .white : .primary)
            if !message.isUser { Spacer(minLength: 40) }
        }
    }

    private var typingIndicator: some View {
        HStack {
            ProgressView()
            Text("Coach is thinking…")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var messageBar: some View {
        HStack(spacing: 8) {
            TextField("Message the coach…", text: $viewModel.draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
            VoiceInputButton(text: $viewModel.draft)
            Button {
                Task { await viewModel.send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .disabled(
                viewModel.draft.trimmingCharacters(in: .whitespaces).isEmpty
                || viewModel.isSending
            )
        }
        .padding()
        .background(.bar)
    }
}

#Preview {
    ChatView()
}

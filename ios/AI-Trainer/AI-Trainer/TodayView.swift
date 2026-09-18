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
    @Published var messageDraft = ""
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

    private func send(message: String, imageBase64: String? = nil) async {
        isLoading = true
        errorMessage = nil
        do {
            let result = try await client.turn(message: message, imageBase64: imageBase64)
            response = result
            // The backend can succeed at the HTTP level but still
            // report a failure inside the JSON (planner_error when the
            // model call itself failed, validation_error when the
            // decision was rejected) -- surface that the same way as a
            // network failure, since neither case has anything safe to
            // show as "today's plan".
            if let backendError = result.error {
                errorMessage = result.errorDetail ?? backendError
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct TodayView: View {
    @StateObject private var viewModel = TodayViewModel()
    @State private var showingCheckIn = false
    @State private var showingLogSession = false
    @State private var showingGoals = false
    @State private var showingSettings = false
    @State private var showingWhyDetail = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    content
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .appBackground()
            .scrollContentBackground(.hidden)
            .navigationTitle("Today")
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
                    attachmentPreview
                    messageBar
                }
            }
            .task {
                if viewModel.response == nil {
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
            Label("Couldn't reach the coach", systemImage: "wifi.exclamationmark")
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
            VoiceInputButton(text: $viewModel.messageDraft)

            // Secondary: typing stays fully available, just visually
            // smaller now that voice leads. Open-ended copy on
            // purpose -- a bad night's sleep, a stressful week,
            // travel, none of it is "fitness," but all of it changes
            // what today should look like.
            HStack(spacing: 8) {
                TextField("Or type: what's going on?", text: $viewModel.messageDraft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .padding(9)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1...3)
                PhotosPicker(selection: $viewModel.photoPickerItem, matching: .images) {
                    Image(systemName: "photo.on.rectangle")
                        .foregroundStyle(Theme.textSecondary)
                }
                Button {
                    Task { await viewModel.sendDraft() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                }
                .disabled(
                    (viewModel.messageDraft.trimmingCharacters(in: .whitespaces).isEmpty && !viewModel.hasAttachment)
                    || viewModel.isLoading
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

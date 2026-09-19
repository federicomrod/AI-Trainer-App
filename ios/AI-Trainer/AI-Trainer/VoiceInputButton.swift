//
//  VoiceInputButton.swift
//  AI-Trainer
//
//  The main way to talk to the coach: a large, central control --
//  think the old iPhone home button, not a small icon lost in a
//  toolbar. Typing stays available, just visually secondary.
//
//  The screen owns the SpeechRecognizer and passes it in, so its send
//  arrow can finish a recording in progress instead of sending around
//  it (which left the microphone running after the message had gone).

import SwiftUI

struct VoiceInputButton: View {
    @ObservedObject var recognizer: SpeechRecognizer
    @Binding var text: String
    /// Called when a take finishes with something in it, right after
    /// `text` has been filled with the final transcript. The X cancels
    /// instead, and never calls this.
    var onSubmit: (() -> Void)?

    private let diameter: CGFloat = 72
    private let cancelDiameter: CGFloat = 44

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 16) {
                if recognizer.isActive {
                    // Discards the recording and transcript entirely.
                    // Shown from the moment a recording is starting, so
                    // there's always a way out.
                    Button {
                        text = ""
                        Task { await recognizer.cancel() }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Theme.card)
                                .frame(width: cancelDiameter, height: cancelDiameter)
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel("Discard recording")
                }

                Button {
                    recognizer.toggle()
                } label: {
                    ZStack {
                        Circle()
                            .fill(recognizer.isActive ? Color.red.opacity(0.85) : Theme.accent)
                            .frame(width: diameter, height: diameter)
                            .shadow(
                                color: (recognizer.isActive ? Color.red : Theme.accent).opacity(0.35),
                                radius: 14, y: 4
                            )
                        micGlyph
                    }
                }
                .buttonStyle(.plain)
                // Finishing is short and bounded (see Config.voiceStallTimeout);
                // taps during it would only queue up confusion.
                .disabled(recognizer.phase == .finishing)
                .accessibilityLabel(recognizer.isActive ? "Stop and send" : "Record a message")
            }
            .animation(.easeOut(duration: 0.15), value: recognizer.isActive)

            // Inline rather than an alert: an alert is modal, and a
            // voice problem should never block the rest of the app.
            if let error = recognizer.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .onTapGesture { recognizer.errorMessage = nil }
            }
        }
        .onChange(of: recognizer.transcript) {
            if recognizer.isRecording {
                text = recognizer.transcript
            }
        }
        .onChange(of: recognizer.finishedTranscript) {
            guard let finished = recognizer.finishedTranscript else { return }
            text = finished
            recognizer.consumeFinished()
            onSubmit?()
        }
        // Leaving the screen mid-recording stops it. What was heard stays
        // in the draft, unsent -- nothing keeps listening off screen.
        .onDisappear {
            if recognizer.isActive {
                Task { await recognizer.cancel() }
            }
        }
    }

    @ViewBuilder
    private var micGlyph: some View {
        switch recognizer.phase {
        case .idle:
            Image(systemName: "mic.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Theme.background)
        case .starting, .finishing:
            ProgressView().tint(Theme.background)
        case .recording:
            // symbolEffect rather than a repeatForever animation: it
            // stops cleanly when recording does.
            Image(systemName: "waveform")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Theme.background)
                .symbolEffect(.variableColor.iterative, isActive: true)
        }
    }
}

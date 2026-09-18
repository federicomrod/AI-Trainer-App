//
//  VoiceInputButton.swift
//  AI-Trainer
//
//  The main way to talk to the coach: a large, central control --
//  think the old iPhone home button, not a small icon lost in a
//  toolbar -- because per CLAUDE.md's logging philosophy and the
//  athlete's own feedback, speaking is the primary input this app
//  wants, not an alternative buried next to a text field. Typing
//  stays fully available (the text field it fills is right above),
//  just visually secondary now. Owns its own SpeechRecognizer, so
//  each input surface (Today, Coach) gets an independent one with no
//  shared state to manage.

import SwiftUI

struct VoiceInputButton: View {
    @Binding var text: String
    /// Called when a take finishes with something in it, right after
    /// `text` has been filled with the final transcript. Finishing a
    /// take is the athlete saying "send this" -- making them then hunt
    /// for a smaller arrow is exactly the friction this control exists
    /// to remove. The X cancels instead, and never calls this.
    var onSubmit: (() -> Void)?
    @StateObject private var recognizer = SpeechRecognizer()

    private let diameter: CGFloat = 72
    private let cancelDiameter: CGFloat = 44

    var body: some View {
        HStack(spacing: 16) {
            if recognizer.isRecording {
                // Discards the recording and transcript entirely --
                // separate from the mic button, which finishes/sends.
                // Appears only while recording, so there's never a
                // moment it could be mistaken for the main control.
                Button {
                    recognizer.cancel()
                    text = ""
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
            }

            Button {
                recognizer.toggleRecording()
            } label: {
                ZStack {
                    Circle()
                        .fill(recognizer.isRecording ? Color.red.opacity(0.85) : Theme.accent)
                        .frame(width: diameter, height: diameter)
                        .shadow(
                            color: (recognizer.isRecording ? Color.red : Theme.accent).opacity(0.35),
                            radius: 14, y: 4
                        )
                    Image(systemName: recognizer.isRecording ? "waveform" : "mic.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Theme.background)
                }
            }
            .buttonStyle(.plain)
            .scaleEffect(recognizer.isRecording ? 1.05 : 1.0)
            .animation(
                recognizer.isRecording
                    ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
                    : .easeOut(duration: 0.2),
                value: recognizer.isRecording
            )
        }
        .animation(.easeOut(duration: 0.15), value: recognizer.isRecording)
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
        .alert(
            "Voice input",
            isPresented: Binding(
                get: { recognizer.errorMessage != nil },
                set: { if !$0 { recognizer.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(recognizer.errorMessage ?? "")
        }
    }
}

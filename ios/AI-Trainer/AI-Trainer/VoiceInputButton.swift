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
    @StateObject private var recognizer = SpeechRecognizer()

    private let diameter: CGFloat = 72

    var body: some View {
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
        .onChange(of: recognizer.transcript) {
            if recognizer.isRecording {
                text = recognizer.transcript
            }
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

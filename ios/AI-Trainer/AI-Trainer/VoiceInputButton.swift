//
//  VoiceInputButton.swift
//  AI-Trainer
//
//  A mic button that fills a text binding via on-device speech
//  recognition. Drop it into any message bar next to a TextField --
//  it owns its own SpeechRecognizer, so each input surface (Today,
//  Coach) gets an independent one with no shared state to manage.

import SwiftUI

struct VoiceInputButton: View {
    @Binding var text: String
    @StateObject private var recognizer = SpeechRecognizer()

    var body: some View {
        Button {
            recognizer.toggleRecording()
        } label: {
            Image(systemName: recognizer.isRecording ? "mic.fill" : "mic")
                .font(.title2)
                .foregroundStyle(recognizer.isRecording ? .red : .secondary)
        }
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

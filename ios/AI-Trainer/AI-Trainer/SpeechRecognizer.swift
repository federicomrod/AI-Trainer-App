//
//  SpeechRecognizer.swift
//  AI-Trainer
//
//  Voice input, per CLAUDE.md's tech decision: Apple on-device speech
//  recognition. Free, instant, no upload. This turns speech into text
//  locally and nothing else -- no audio ever leaves the device, and
//  voice never becomes a separate path to the coach. The transcript
//  just fills the same text field typing would, and the athlete
//  reviews and sends it exactly like any other message.

import AVFoundation
import Combine
import Speech

@MainActor
final class SpeechRecognizer: ObservableObject {
    enum RecognizerError: Error, LocalizedError {
        case notAuthorized
        case unavailable

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "Speech recognition and microphone access are both "
                    + "needed for voice input. Enable them in Settings."
            case .unavailable:
                return "On-device speech recognition isn't available on "
                    + "this device right now."
            }
        }
    }

    @Published private(set) var isRecording = false
    @Published private(set) var transcript = ""
    @Published var errorMessage: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func toggleRecording() {
        if isRecording {
            stop()
        } else {
            Task { await start() }
        }
    }

    func start() async {
        errorMessage = nil
        transcript = ""

        do {
            try await requestPermissions()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            return
        }

        guard let recognizer, recognizer.isAvailable else {
            errorMessage = RecognizerError.unavailable.errorDescription
            return
        }

        #if os(iOS)
        // AVAudioSession itself is iOS-only -- macOS has no equivalent
        // concept (this project's scheme can offer "My Mac" as a
        // destination automatically on Apple Silicon; this guard keeps
        // the file buildable there even though voice input is only
        // meant to run on an actual iPhone).
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Couldn't start the microphone: \(error.localizedDescription)"
            return
        }
        #endif

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // On-device only, deliberately. If a locale or device doesn't
        // support the on-device model, this fails rather than quietly
        // falling back to sending audio to Apple's servers -- CLAUDE.md
        // is explicit that voice input never uploads.
        request.requiresOnDeviceRecognition = true
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            errorMessage = "Couldn't start the microphone: \(error.localizedDescription)"
            return
        }

        isRecording = true

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if error != nil || (result?.isFinal ?? false) {
                    self.stop()
                }
            }
        }
    }

    func stop() {
        guard isRecording || audioEngine.isRunning else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isRecording = false
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    private func requestPermissions() async throws {
        let speechStatus = await withCheckedContinuation {
            (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else {
            throw RecognizerError.notAuthorized
        }

        #if os(iOS)
        let micGranted = await withCheckedContinuation {
            (continuation: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        guard micGranted else {
            throw RecognizerError.notAuthorized
        }
        #endif
    }
}

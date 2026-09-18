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

    // On-device SFSpeechRecognizer has an internal session limit --
    // observed to cut a running task off anywhere from ~30 to ~60
    // seconds in, regardless of what's being said. Rather than let
    // that surface as a broken/truncated transcript, this proactively
    // starts a fresh recognition task well inside that window, folding
    // whatever was heard so far into `committed` first. The published
    // `transcript` is always committed + the live partial, so a
    // restart is invisible to anything reading it -- the audio tap and
    // engine are never touched, only the request/task pair. 25s gives
    // real margin under the earliest observed cutoff.
    private static let restartInterval: Duration = .seconds(25)
    private var committed = ""
    private var restartTask: Task<Void, Never>?

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
        committed = ""

        do {
            try await requestPermissions()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            return
        }

        guard recognizer?.isAvailable == true else {
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

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
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
        beginRecognitionTask()
    }

    /// Starts (or restarts) the recognizer's request+task pair against
    /// the audio already flowing from the tap installed in start().
    /// Safe to call repeatedly while the same recording session
    /// continues -- each call replaces `request`/`task` without
    /// touching the audio engine.
    private func beginRecognitionTask() {
        guard let recognizer else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // On-device only, deliberately. If a locale or device doesn't
        // support the on-device model, this fails rather than quietly
        // falling back to sending audio to Apple's servers -- CLAUDE.md
        // is explicit that voice input never uploads.
        request.requiresOnDeviceRecognition = true
        self.request = request

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self, self.request === request else { return }
                if let result {
                    self.transcript = self.joined(self.committed, result.bestTranscription.formattedString)
                }
                if error != nil || (result?.isFinal ?? false) {
                    // A restart deliberately cancels the previous task,
                    // which delivers here as an error too -- only treat
                    // this as session-ending if we're not already
                    // mid-restart (isRecording still true but request
                    // has already moved on to a newer one).
                    if self.isRecording && self.request === request {
                        self.stop()
                    }
                }
            }
        }

        scheduleRestart()
    }

    private func scheduleRestart() {
        restartTask?.cancel()
        restartTask = Task { [weak self] in
            try? await Task.sleep(for: Self.restartInterval)
            guard let self, !Task.isCancelled else { return }
            await self.restart()
        }
    }

    @MainActor
    private func restart() async {
        guard isRecording else { return }
        committed = transcript
        request?.endAudio()
        task?.cancel()
        beginRecognitionTask()
    }

    private func joined(_ committed: String, _ partial: String) -> String {
        guard !committed.isEmpty else { return partial }
        guard !partial.isEmpty else { return committed }
        return "\(committed) \(partial)"
    }

    func stop() {
        restartTask?.cancel()
        restartTask = nil
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

    /// Discards the current recording and transcript entirely -- the
    /// cancel control next to the mic while recording, distinct from
    /// stop() which is also used to finish/send normally. The caller
    /// (VoiceInputButton) is responsible for also clearing whatever
    /// text field this had been mirrored into.
    func cancel() {
        stop()
        transcript = ""
        committed = ""
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

//
//  SpeechRecognizer.swift
//  AI-Trainer
//
//  Voice input, per CLAUDE.md's tech decision: Apple on-device speech
//  recognition. Free, instant, no upload. This turns speech into text
//  locally and nothing else -- no audio ever leaves the device. The
//  transcript fills the same text field typing would.
//
//  Built as an explicit state machine, because the previous version
//  could get stuck or crash:
//
//  - Starting the microphone takes around half a second, during which
//    it still looked idle. Another tap in that window started a second
//    recording, which attached a second tap to the microphone -- and
//    AVAudioEngine raises an exception for that ('nullptr == Tap()').
//    Under the Xcode debugger that exception freezes the whole app.
//  - A "stop" in that same window was silently ignored, and the mic went
//    live anyway after being told to stop.
//  - Audio session and engine calls block, and they ran on the main
//    thread.
//
//  Now: every request is judged against the current phase, so a
//  recording can only be started from idle and a stop during startup is
//  honoured; microphone work runs off the main thread (AudioCapture);
//  and a watchdog guarantees that starting or finishing can never hang
//  -- if either stalls, the recording is torn down and the UI is back to
//  idle within a few seconds, whatever the cause.

import AVFoundation
import Combine
import Speech

@MainActor
final class SpeechRecognizer: ObservableObject {
    enum Phase: Equatable {
        case idle
        /// Permission granted; the microphone is being switched on.
        case starting
        case recording
        /// The athlete said done; collecting the final words.
        case finishing
    }

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

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var transcript = ""
    @Published var errorMessage: String?

    /// Set once, when a take finishes normally with something in it.
    /// Finishing a take is the athlete saying "send this", so the view
    /// watches this and submits. Cleared by consumeFinished() so two
    /// identical takes in a row both fire.
    @Published private(set) var finishedTranscript: String?

    #if DEBUG
    /// Self-test only: stand in for Apple's recognizer, whose model
    /// doesn't load in the Simulator.
    static var engineOverride: RecognitionEngine?
    #endif

    /// Starting, recording or finishing -- anything but idle.
    var isActive: Bool { phase != .idle }
    var isRecording: Bool { phase == .recording }

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var capture = AudioCapture()
    private var stitcher: TranscriptStitcher?
    private var handoverTask: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    /// Identifies one attempt at recording. Anything that finishes late
    /// for an older attempt is ignored rather than acted on.
    private var attempt = 0

    /// The mic button: start when idle, finish otherwise.
    func toggle() {
        switch phase {
        case .idle:
            Task { await start() }
        case .starting, .recording:
            Task { await finish() }
        case .finishing:
            break // already ending; the watchdog guarantees it does
        }
    }

    func start() async {
        guard phase == .idle else { return }
        attempt += 1
        let mine = attempt
        errorMessage = nil
        transcript = ""
        finishedTranscript = nil
        phase = .starting

        // Not under the watchdog: this can legitimately wait on the
        // athlete answering a permission prompt.
        do {
            try await requestPermissions()
        } catch {
            fail(mine, error)
            return
        }
        guard attempt == mine, phase == .starting else { return } // stopped while asking

        guard let recognizer, recognizer.isAvailable else {
            fail(mine, RecognizerError.unavailable)
            return
        }

        var engine: RecognitionEngine = AppleRecognitionEngine(recognizer: recognizer, requiresOnDevice: true)
        #if DEBUG
        if let override = Self.engineOverride { engine = override }
        #endif
        let stitcher = TranscriptStitcher(engine: engine)
        stitcher.onChange = { [weak self] text in
            guard let self, self.attempt == mine else { return }
            self.transcript = text
        }
        stitcher.onFailure = { [weak self] message in
            guard let self, self.attempt == mine else { return }
            Task { await self.abandon(mine, keepingTranscript: true, message: message) }
        }
        self.stitcher = stitcher
        stitcher.start()

        armWatchdog(mine, phase: .starting)
        do {
            try await capture.start(feed: stitcher.feed)
        } catch {
            guard attempt == mine else { return }
            stitcher.cancel()
            fail(mine, error)
            return
        }
        guard attempt == mine, phase == .starting else {
            // Stopped (or reset) while the microphone was coming on.
            return
        }
        watchdog?.cancel()
        phase = .recording
        scheduleHandovers(mine)
    }

    /// Stop recording and submit what was said. Safe to call in any
    /// phase: during startup it simply calls the start off.
    func finish() async {
        switch phase {
        case .idle, .finishing:
            return
        case .starting:
            await abandon(attempt, keepingTranscript: false, message: nil)
            return
        case .recording:
            break
        }
        let mine = attempt
        phase = .finishing
        handoverTask?.cancel()
        armWatchdog(mine, phase: .finishing)

        await capture.stop() // microphone off first: nothing more goes in
        let text = await stitcher?.finish(timeout: .seconds(2)) ?? transcript
        guard attempt == mine, phase == .finishing else { return } // watchdog got here first

        watchdog?.cancel()
        stitcher = nil
        phase = .idle
        deliver(text)
    }

    /// Discard the recording and its transcript entirely.
    func cancel() async {
        guard phase != .idle else { return }
        await abandon(attempt, keepingTranscript: false, message: nil)
        transcript = ""
        finishedTranscript = nil
    }

    /// Marks the finished take as handled.
    func consumeFinished() {
        finishedTranscript = nil
    }

    // MARK: - Internals

    /// Hand over to a fresh recognition task every so often, so no one
    /// task runs long enough to hit a recognizer limit. The stitcher
    /// makes the handover lossless.
    private func scheduleHandovers(_ mine: Int) {
        handoverTask?.cancel()
        handoverTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Config.voiceHandoverInterval)
                guard let self, !Task.isCancelled, self.attempt == mine, self.phase == .recording else { return }
                self.stitcher?.rollOver()
            }
        }
    }

    /// The guarantee: if starting or finishing hasn't completed within
    /// Config.voiceStallTimeout, force everything back to idle.
    private func armWatchdog(_ mine: Int, phase watched: Phase) {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: Config.voiceStallTimeout)
            guard let self, !Task.isCancelled, self.attempt == mine, self.phase == watched else { return }
            self.forceReset(keepingTranscript: watched == .finishing)
        }
    }

    /// Last resort, when the audio system stops answering. Doesn't wait
    /// on anything: the stuck microphone is abandoned in favour of a
    /// fresh one, so the next recording never queues behind it, and
    /// whatever had already been transcribed is still delivered.
    private func forceReset(keepingTranscript: Bool) {
        attempt += 1
        handoverTask?.cancel()
        watchdog?.cancel()
        let salvage = keepingTranscript ? (stitcher?.text ?? transcript) : ""
        stitcher?.cancel()
        stitcher = nil
        let stuck = capture
        capture = AudioCapture()
        Task.detached { await stuck.stop() }
        phase = .idle
        errorMessage = "The microphone stopped responding, so it was reset."
        deliver(salvage)
    }

    /// Tear down an attempt that shouldn't produce a message: called off
    /// during startup, cancelled, or recognition failed.
    private func abandon(_ mine: Int, keepingTranscript: Bool, message: String?) async {
        guard attempt == mine, phase != .idle else { return }
        attempt += 1
        handoverTask?.cancel()
        watchdog?.cancel()
        let salvage = keepingTranscript ? (stitcher?.text ?? transcript) : ""
        stitcher?.cancel()
        stitcher = nil
        phase = .idle
        if let message { errorMessage = message }
        await capture.stop()
        if keepingTranscript { deliver(salvage) }
    }

    private func fail(_ mine: Int, _ error: Error) {
        guard attempt == mine else { return }
        attempt += 1
        watchdog?.cancel()
        stitcher = nil
        phase = .idle
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let stuck = capture
        Task { await stuck.stop() }
    }

    private func deliver(_ text: String) {
        let spoken = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spoken.isEmpty else { return }
        transcript = spoken
        finishedTranscript = spoken
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

/// The microphone, confined to its own serial queue.
///
/// Activating the audio session and starting or stopping the engine are
/// blocking calls -- Apple warns they can take a while -- and the
/// previous version made them on the main thread, where a slow one
/// freezes every screen. Here they never touch the main thread, and
/// start/stop are idempotent: a second start can't attach a second tap.
nonisolated final class AudioCapture: @unchecked Sendable {
    enum CaptureError: LocalizedError {
        case noInput
        var errorDescription: String? { "No microphone input is available right now." }
    }

    #if DEBUG
    /// Self-test only: make stop() hang, to prove the watchdog recovers.
    nonisolated(unsafe) static var simulatedStopHang: Duration?
    #endif

    private let queue = DispatchQueue(label: "AudioCapture", qos: .userInitiated)
    private let engine = AVAudioEngine()
    private var tapInstalled = false

    func start(feed: AudioFeed) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                do {
                    #if os(iOS)
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.record, mode: .measurement, options: .duckOthers)
                    try session.setActive(true, options: .notifyOthersOnDeactivation)
                    #endif
                    let input = engine.inputNode
                    let format = input.outputFormat(forBus: 0)
                    guard format.sampleRate > 0, format.channelCount > 0 else { throw CaptureError.noInput }
                    if tapInstalled {
                        input.removeTap(onBus: 0)
                        tapInstalled = false
                    }
                    input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                        feed.append(buffer)
                    }
                    tapInstalled = true
                    engine.prepare()
                    try engine.start()
                    continuation.resume()
                } catch {
                    teardown()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                #if DEBUG
                if let hang = Self.simulatedStopHang {
                    Thread.sleep(forTimeInterval: Double(hang.components.seconds))
                }
                #endif
                teardown()
                continuation.resume()
            }
        }
    }

    /// Runs on `queue` only.
    private func teardown() {
        if engine.isRunning { engine.stop() }
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}

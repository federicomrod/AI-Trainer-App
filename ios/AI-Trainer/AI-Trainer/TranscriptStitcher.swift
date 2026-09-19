//
//  TranscriptStitcher.swift
//  AI-Trainer
//
//  Turns one continuous recording into one transcript, even though the
//  recognizer works in pieces.
//
//  A recognition task doesn't last indefinitely, and its running
//  transcription isn't a simple growing string. The previous version
//  lost words in three ways:
//
//  1. Every 25s it handed over to a fresh task by keeping the last
//     *partial* result and cancelling the old task. Partial results
//     trail the audio, and a cancelled task delivers nothing further,
//     so whatever was said just before each handover was thrown away --
//     a hole mid-message.
//  2. On stop, it ignored the final result, which is the one carrying
//     the last words.
//  3. After a pause the recognizer can start a new utterance within the
//     same task, and its running transcription then restarts from there.
//     Keeping only the latest transcription replaced everything said
//     before the pause.
//
//  Here each task owns a segment. A handover closes the old task's audio
//  and lets it *finish*, so its final result covers everything it heard,
//  while new audio already flows to the replacement. Within a segment, a
//  restart after a pause is detected and the earlier utterance is kept.
//  A task ending by itself just starts the next segment: only the
//  athlete ends a recording.

import AVFoundation
import Foundation
import Speech

// MARK: - The recognizer, abstracted

/// One recognition task's worth of audio in, words out.
nonisolated protocol RecognitionSegment: AnyObject, Sendable {
    func append(_ buffer: AVAudioPCMBuffer)
    /// No more audio is coming: finish what was heard and deliver a
    /// final result.
    func endAudio()
    /// Stop immediately; nothing further is delivered.
    func cancel()
}

/// Results may arrive on any thread.
typealias RecognitionResultHandler = @Sendable (_ words: String?, _ isFinal: Bool, _ errorCode: Int?) -> Void

nonisolated protocol RecognitionEngine: Sendable {
    func begin(onResult: @escaping RecognitionResultHandler) -> RecognitionSegment
}

/// Apple's on-device speech recognition.
nonisolated final class AppleRecognitionEngine: RecognitionEngine, @unchecked Sendable {
    private let recognizer: SFSpeechRecognizer
    private let requiresOnDevice: Bool

    init(recognizer: SFSpeechRecognizer, requiresOnDevice: Bool) {
        self.recognizer = recognizer
        self.requiresOnDevice = requiresOnDevice
    }

    func begin(onResult: @escaping RecognitionResultHandler) -> RecognitionSegment {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // On-device only in the app: CLAUDE.md is explicit that voice
        // input never uploads audio.
        request.requiresOnDeviceRecognition = requiresOnDevice
        let task = recognizer.recognitionTask(with: request) { result, error in
            onResult(
                result?.bestTranscription.formattedString,
                result?.isFinal ?? false,
                error.map { ($0 as NSError).code }
            )
        }
        return AppleSegment(request: request, task: task)
    }
}

nonisolated private final class AppleSegment: RecognitionSegment, @unchecked Sendable {
    private let request: SFSpeechAudioBufferRecognitionRequest
    private let task: SFSpeechRecognitionTask

    init(request: SFSpeechAudioBufferRecognitionRequest, task: SFSpeechRecognitionTask) {
        self.request = request
        self.task = task
    }

    func append(_ buffer: AVAudioPCMBuffer) { request.append(buffer) }
    func endAudio() { request.endAudio() }
    func cancel() { task.cancel() }
}

// MARK: - Audio hand-off

/// The one place audio buffers cross from the audio thread to whichever
/// segment is current.
///
/// Appending and swapping happen under the same lock, and the outgoing
/// segment's audio is closed inside that lock, so a buffer goes to
/// exactly one segment and never to one that has already been ended.
/// It also keeps the audio thread away from main-actor state, which the
/// previous version read directly from the audio thread.
nonisolated final class AudioFeed: @unchecked Sendable {
    private let lock = NSLock()
    private var segment: RecognitionSegment?

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        segment?.append(buffer)
    }

    /// Route audio to `next`, closing the audio of whatever was
    /// receiving it until now.
    func swap(to next: RecognitionSegment?) {
        lock.lock()
        defer { lock.unlock() }
        segment?.endAudio()
        segment = next
    }
}

// MARK: - Stitching

@MainActor
final class TranscriptStitcher {
    let feed = AudioFeed()

    /// The whole transcript so far, every time any part of it changes.
    var onChange: ((String) -> Void)?
    /// Recognition can't carry on -- it keeps failing straight away.
    /// Called at most once.
    var onFailure: ((String) -> Void)?
    /// Diagnostics, for the self-test.
    var onEvent: ((String) -> Void)?

    private struct Segment {
        /// Utterances this task already finished before restarting its
        /// running transcription after a pause.
        var kept = ""
        /// Its current running transcription.
        var live = ""
        var text: String { Self.join(kept, live) }
        static func join(_ a: String, _ b: String) -> String {
            [a, b].map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }.joined(separator: " ")
        }
    }

    private let engine: RecognitionEngine
    private var segments: [Segment] = []
    private var open: [Int: RecognitionSegment] = [:]
    private var startedAt: [Int: ContinuousClock.Instant] = [:]
    private var current: Int?
    /// Bumped on start and cancel, so results from an earlier session
    /// can never land in a later one's transcript.
    private var session = 0
    private var isClosing = false
    private var quickFailures = 0
    private var didFail = false
    private var closeWaiters: [CheckedContinuation<Void, Never>] = []

    init(engine: RecognitionEngine) {
        self.engine = engine
    }

    var text: String {
        segments.map(\.text).filter { !$0.isEmpty }.joined(separator: " ")
    }

    func start() {
        session += 1
        segments = []
        open = [:]
        startedAt = [:]
        isClosing = false
        quickFailures = 0
        didFail = false
        beginSegment()
    }

    /// Hand over to a fresh task without losing anything.
    func rollOver() {
        guard !isClosing, current != nil else { return }
        beginSegment()
    }

    /// Stop taking audio, give every open task a bounded chance to
    /// deliver its final words, and return the transcript. Never waits
    /// longer than `timeout`; a task that hasn't answered by then is
    /// abandoned, keeping whatever it had already reported.
    func finish(timeout: Duration) async -> String {
        isClosing = true
        feed.swap(to: nil)
        if !open.isEmpty {
            let deadline = Task { [weak self] in
                try? await Task.sleep(for: timeout)
                guard let self, !Task.isCancelled else { return }
                self.onEvent?("finish deadline reached with \(self.open.count) task(s) still open")
                self.releaseCloseWaiters()
            }
            await withCheckedContinuation { continuation in
                if open.isEmpty { continuation.resume() } else { closeWaiters.append(continuation) }
            }
            deadline.cancel()
        }
        for segment in open.values { segment.cancel() }
        open = [:]
        return text
    }

    /// Discard everything, immediately.
    func cancel() {
        session += 1
        isClosing = true
        feed.swap(to: nil)
        for segment in open.values { segment.cancel() }
        open = [:]
        segments = []
        releaseCloseWaiters()
    }

    private func beginSegment() {
        let index = segments.count
        let session = self.session
        segments.append(Segment())
        let segment = engine.begin { [weak self] words, isFinal, errorCode in
            Task { @MainActor [weak self] in
                self?.handle(session: session, index: index, words: words,
                             isFinal: isFinal, errorCode: errorCode)
            }
        }
        open[index] = segment
        startedAt[index] = .now
        current = index
        // New audio goes to the new segment from here on; the previous
        // one is closed and left to finish on its own.
        feed.swap(to: segment)
    }

    private func handle(session: Int, index: Int, words: String?, isFinal: Bool, errorCode: Int?) {
        guard session == self.session, index < segments.count else { return }

        if let words, !words.isEmpty {
            if Self.isRestart(from: segments[index].live, to: words) {
                segments[index].kept = segments[index].text
                onEvent?("segment \(index): running transcription restarted after a pause; kept \"…\(segments[index].kept.suffix(30))\"")
            }
            segments[index].live = words
            quickFailures = 0
            onChange?(text)
        }
        guard isFinal || errorCode != nil else { return }

        open[index] = nil
        if isClosing {
            if open.isEmpty { releaseCloseWaiters() }
            return
        }
        guard index == current else { return } // an earlier segment finishing after a handover

        // The recognizer ended this segment by itself while the athlete
        // is still talking. That isn't "done" -- keep listening.
        let lived = startedAt[index].map { $0.duration(to: .now) } ?? .zero
        if errorCode != nil, segments[index].text.isEmpty, lived < .seconds(2) {
            quickFailures += 1
        }
        if quickFailures >= 3 {
            if !didFail {
                didFail = true
                onFailure?("Voice input isn't working right now. Try again, or type instead.")
                onEvent?("gave up after repeated immediate failures (error \(errorCode ?? 0))")
            }
            return
        }
        onEvent?("segment \(index) ended on its own (\(errorCode.map { "error \($0)" } ?? "final")); continuing in a new segment")
        beginSegment()
    }

    /// Whether `next` is a fresh utterance rather than a revision of
    /// `previous`. Revisions rewrite recent words but keep how it
    /// started; a restart after a pause is shorter and starts somewhere
    /// else entirely.
    static func isRestart(from previous: String, to next: String) -> Bool {
        let before = words(previous)
        let after = words(next)
        guard before.count >= 3, after.count < before.count else { return false }
        return Array(after.prefix(2)) != Array(before.prefix(2))
    }

    private static func words(_ s: String) -> [String] {
        s.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private func releaseCloseWaiters() {
        let waiting = closeWaiters
        closeWaiters = []
        for continuation in waiting { continuation.resume() }
    }
}

//
//  VoiceSelfTest.swift
//  AI-Trainer
//
//  Debug-only harness for voice input. Runs only when the app is
//  launched with `-voiceSelfTest <scenario>`; never in a normal launch,
//  never in a release build.
//
//  Transcript scenarios feed a recorded voice note through the
//  recognition pipeline in real time, and write the result to Documents/
//  for comparison with the known script. The Simulator's speech model
//  fails to load (kLSRErrorDomain 300), so real recognition can't run
//  here; ScriptedEngine stands in for it, behaving the way Apple's
//  recognizer does in the three ways that matter:
//
//  - partial results trail the audio (by `lag`)
//  - a cancelled task delivers nothing further
//  - after a pause, the running transcription restarts from the new
//    utterance
//
//  Legacy and fixed pipelines run against the identical engine and
//  audio, so any difference is down to the pipeline.

#if DEBUG
import AVFoundation
import Foundation
import Speech

enum VoiceSelfTest {
    static func runIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-voiceSelfTest"), i + 1 < args.count else { return }
        let scenario = args[i + 1]
        Task { @MainActor in
            write(["scenario": scenario, "state": "started, no result yet"], scenario: scenario)
            let report = scenario.hasPrefix("lifecycle")
                ? await VoiceLifecycleTest.run(scenario)
                : await runTranscript(scenario)
            write(report, scenario: scenario)
        }
    }

    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func write(_ report: [String: Any], scenario: String) {
        let url = documents.appendingPathComponent("voice-selftest-\(scenario).json")
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url)
        }
    }

    @MainActor
    private static func runTranscript(_ scenario: String) async -> [String: Any] {
        guard let file = try? AVAudioFile(forReading: documents.appendingPathComponent("voice-harness.wav")),
              let timing = try? Data(contentsOf: documents.appendingPathComponent("voice-harness-words.json")),
              let json = try? JSONSerialization.jsonObject(with: timing) as? [String: Any],
              let list = json["words"] as? [[String: Any]]
        else { return ["error": "missing harness audio or word timings"] }
        let engine = ScriptedEngine(words: list.compactMap {
            guard let w = $0["w"] as? String, let t = $0["t"] as? Double else { return nil }
            return .init(text: w, time: t)
        })
        let interval: Duration = scenario.hasSuffix("6") ? .seconds(6) : .seconds(25)
        let pipeline: HarnessPipeline = scenario.hasPrefix("legacy")
            ? LegacyPipeline(engine: engine)
            : FixedPipeline(engine: engine)

        let started = ContinuousClock.now
        pipeline.begin()
        var nextHandover = started + interval
        let chunk = AVAudioFrameCount(file.processingFormat.sampleRate / 10) // 100ms, like a mic tap
        while file.framePosition < file.length {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk),
                  (try? file.read(into: buffer, frameCount: chunk)) != nil else { break }
            pipeline.append(buffer)
            try? await Task.sleep(for: .milliseconds(100))
            if ContinuousClock.now >= nextHandover {
                pipeline.rollOver(at: started.duration(to: .now))
                nextHandover = ContinuousClock.now + interval
            }
        }
        // The athlete taps done about half a second after the last word.
        try? await Task.sleep(for: .milliseconds(500))
        let text = await pipeline.finish()
        return ["scenario": scenario, "transcript": text, "events": pipeline.events]
    }
}

@MainActor
protocol HarnessPipeline: AnyObject {
    var events: [String] { get }
    func begin()
    func append(_ buffer: AVAudioPCMBuffer)
    func rollOver(at elapsed: Duration)
    func finish() async -> String
}

/// SpeechRecognizer's restart/stop logic as of 5f6ef60
/// (beginRecognitionTask / restart / stop), line for line, with the
/// request+task pair behind RecognitionSegment. `currentID` plays the
/// part of the old `self.request === request` identity check.
@MainActor
final class LegacyPipeline: HarnessPipeline {
    private let engine: RecognitionEngine
    private var segment: RecognitionSegment?
    private var currentID = 0
    private var committed = ""
    private var transcript = ""
    private var isRecording = true
    private(set) var events: [String] = []

    init(engine: RecognitionEngine) { self.engine = engine }

    func begin() {
        currentID += 1
        let id = currentID
        segment = engine.begin { [weak self] words, isFinal, error in
            Task { @MainActor [weak self] in
                guard let self, self.currentID == id else { return }
                if let words {
                    self.transcript = Self.joined(self.committed, words)
                }
                if error != nil || isFinal {
                    if self.isRecording && self.currentID == id {
                        self.events.append("task ended on its own -> whole recording stopped")
                        self.stop()
                    }
                }
            }
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) { segment?.append(buffer) }

    func rollOver(at elapsed: Duration) {
        guard isRecording else { return }
        events.append("restart at \(elapsed.formatted(.units(allowed: [.seconds], fractionalPart: .show(length: 1)))): committed \"…\(transcript.suffix(35))\"")
        committed = transcript                 // restart(): committed = transcript
        segment?.endAudio()                    // request?.endAudio()
        segment?.cancel()                      // task?.cancel()
        begin()                                // beginRecognitionTask()
    }

    func finish() async -> String {
        stop()
        return transcript
    }

    private func stop() {
        segment?.endAudio()                    // request?.endAudio(); task?.finish()
        segment = nil                          // request = nil; task = nil
        currentID = -1                         // late results now fail the identity check
        isRecording = false
    }

    private static func joined(_ committed: String, _ partial: String) -> String {
        guard !committed.isEmpty else { return partial }
        guard !partial.isEmpty else { return committed }
        return "\(committed) \(partial)"
    }
}

/// The replacement, exactly as SpeechRecognizer uses it.
@MainActor
final class FixedPipeline: HarnessPipeline {
    private let stitcher: TranscriptStitcher
    private(set) var events: [String] = []

    init(engine: RecognitionEngine) {
        stitcher = TranscriptStitcher(engine: engine)
        stitcher.onEvent = { [weak self] in self?.events.append($0) }
    }

    func begin() { stitcher.start() }
    func append(_ buffer: AVAudioPCMBuffer) { stitcher.feed.append(buffer) }
    func rollOver(at elapsed: Duration) {
        events.append("handover at \(elapsed.formatted(.units(allowed: [.seconds], fractionalPart: .show(length: 1))))")
        stitcher.rollOver()
    }
    func finish() async -> String { await stitcher.finish(timeout: .seconds(3)) }
}

// MARK: - Stand-in recognizer

nonisolated final class ScriptedEngine: RecognitionEngine, @unchecked Sendable {
    struct Word { let text: String; let time: Double }

    let words: [Word]
    /// How far partial results trail the audio.
    let lag = 0.8
    /// A silence this long starts a new utterance.
    let utteranceGap = 1.5

    private let lock = NSLock()
    private var audioTime = 0.0

    init(words: [Word]) { self.words = words }

    /// Audio position so far, across every segment. Only one segment
    /// receives audio at a time, so the running total is the clock.
    func advance(by seconds: Double) -> Double {
        lock.lock(); defer { lock.unlock() }
        audioTime += seconds
        return audioTime
    }

    func begin(onResult: @escaping RecognitionResultHandler) -> RecognitionSegment {
        ScriptedSegment(engine: self, onResult: onResult)
    }
}

nonisolated private final class ScriptedSegment: RecognitionSegment, @unchecked Sendable {
    private let engine: ScriptedEngine
    private let onResult: RecognitionResultHandler
    private let lock = NSLock()
    private var heardFrom: Double?
    private var heardUntil = 0.0
    private var ended = false
    private var cancelled = false

    init(engine: ScriptedEngine, onResult: @escaping RecognitionResultHandler) {
        self.engine = engine
        self.onResult = onResult
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        let seconds = Double(buffer.frameLength) / buffer.format.sampleRate
        let now = engine.advance(by: seconds)
        lock.lock()
        guard !ended, !cancelled else { lock.unlock(); return }
        if heardFrom == nil { heardFrom = now - seconds }
        heardUntil = now
        lock.unlock()
        report(upTo: now - engine.lag, isFinal: false)
    }

    func endAudio() {
        lock.lock()
        guard !ended else { lock.unlock(); return }
        ended = true
        lock.unlock()
        // A final result, covering everything heard, shortly afterwards.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { [self] in
            report(upTo: .infinity, isFinal: true)
        }
    }

    func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
        onResult(nil, false, 216) // what a cancelled SFSpeechRecognitionTask reports
    }

    private func report(upTo limit: Double, isFinal: Bool) {
        lock.lock()
        let from = heardFrom, until = heardUntil, dead = cancelled
        lock.unlock()
        guard !dead else { return }
        guard let from else {
            if isFinal { onResult("", true, nil) }
            return
        }
        var heard = engine.words.filter { $0.time >= from && $0.time <= min(limit, until) }
        // After a pause the running transcription restarts: keep only
        // the latest utterance.
        if let restart = heard.indices.dropFirst().last(where: { heard[$0].time - heard[$0 - 1].time >= engine.utteranceGap }) {
            heard = Array(heard[restart...])
        }
        onResult(heard.map(\.text).joined(separator: " "), isFinal, nil)
    }
}
#endif

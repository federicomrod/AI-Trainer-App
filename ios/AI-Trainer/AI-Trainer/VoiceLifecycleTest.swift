//
//  VoiceLifecycleTest.swift
//  AI-Trainer
//
//  Debug-only: drives SpeechRecognizer through the timing cases a real
//  finger produces -- and a microphone that stops responding -- and
//  records what state it ends up in. Uses the real microphone and audio
//  engine; only the recognizer is stood in for (see VoiceSelfTest).

#if DEBUG
import Foundation

@MainActor
enum VoiceLifecycleTest {
    static func run(_ scenario: String) async -> [String: Any] {
        SpeechRecognizer.engineOverride = ScriptedEngine(words: [])
        AudioCapture.simulatedStopHang = nil
        var log: [String] = []
        let clock = ContinuousClock()
        let t0 = clock.now
        let r = SpeechRecognizer()
        func stamp(_ s: String) {
            log.append("+\(t0.duration(to: clock.now).formatted(.units(allowed: [.milliseconds]))) \(s) [phase=\(r.phase)]")
        }
        func waitFor(_ phase: SpeechRecognizer.Phase, within: Duration) async -> Bool {
            let deadline = clock.now + within
            while clock.now < deadline {
                if r.phase == phase { return true }
                try? await Task.sleep(for: .milliseconds(20))
            }
            return r.phase == phase
        }

        switch scenario {
        case "lifecycleDoubleTap":
            // Three quick taps before the microphone has finished coming on.
            stamp("tap 1"); r.toggle()
            try? await Task.sleep(for: .milliseconds(30))
            stamp("tap 2"); r.toggle()
            try? await Task.sleep(for: .milliseconds(30))
            stamp("tap 3"); r.toggle()
            // Three taps = start, stop, start: every tap honoured, in order.
            stamp("3 taps -> recording (start/stop/start): \(await waitFor(.recording, within: .seconds(3)))")
            try? await Task.sleep(for: .seconds(1))
            stamp("still recording, one microphone tap attached (a second would have crashed)")
            // And it still works normally afterwards.
            r.toggle()
            stamp("tap -> idle: \(await waitFor(.idle, within: .seconds(4)))")
            r.toggle()
            stamp("tap -> recording: \(await waitFor(.recording, within: .seconds(3)))")
            r.toggle()
            stamp("tap -> idle: \(await waitFor(.idle, within: .seconds(4)))")

        case "lifecycleStopWhileStarting":
            stamp("start requested")
            let starting = Task { await r.start() }
            try? await Task.sleep(for: .milliseconds(15))
            stamp("stop requested")
            await r.finish()
            await starting.value
            stamp("start() returned")
            try? await Task.sleep(for: .seconds(1))
            stamp("1s later -- must be idle, not recording")

        case "lifecycleSendWhileRecording":
            r.toggle()
            stamp("recording: \(await waitFor(.recording, within: .seconds(3)))")
            try? await Task.sleep(for: .seconds(2))
            stamp("send arrow tapped mid-recording")
            await r.finish()
            stamp("finish returned")
            try? await Task.sleep(for: .seconds(2))
            stamp("2s later -- microphone must be off, not still listening")

        case "lifecycleStallWatchdog":
            r.toggle()
            stamp("recording: \(await waitFor(.recording, within: .seconds(3)))")
            AudioCapture.simulatedStopHang = .seconds(12)
            stamp("microphone shutdown now hangs for 12s; tapping done")
            Task { await r.finish() }
            for second in 1...6 {
                try? await Task.sleep(for: .seconds(1))
                stamp("t+\(second)s")
            }
            stamp("error shown: \(r.errorMessage ?? "none")")
            AudioCapture.simulatedStopHang = nil
            // The stuck microphone is still hung -- a new recording must
            // not queue behind it.
            r.toggle()
            stamp("new recording while the old mic is still stuck: \(await waitFor(.recording, within: .seconds(3)))")
            r.toggle()
            stamp("and finishes normally: \(await waitFor(.idle, within: .seconds(4)))")

        default:
            return ["error": "unknown scenario \(scenario)"]
        }
        SpeechRecognizer.engineOverride = nil
        AudioCapture.simulatedStopHang = nil
        return ["scenario": scenario, "log": log, "completed": true]
    }
}
#endif

//
//  Config.swift
//  AI-Trainer
//
//  Every knob that decides *where* the backend is and *how long* we're
//  willing to wait for it. One file, so changing the address is one
//  edit in one obvious place -- the original arrangement buried a
//  hardcoded LAN IP in APIClient, which went stale every time the
//  router handed out a different lease.

import Foundation

enum Config {
    // MARK: - Where the backend lives

    /// The deployed backend. Paste the address the host gives you
    /// between the quotes, including https:// and with no trailing
    /// slash, e.g.
    ///
    ///     "https://ai-trainer-production-1a2b.up.railway.app"
    ///
    /// Leave it empty to work entirely against a laptop on the LAN.
    /// This is the only line that needs changing to move the app
    /// between the two.
    static let deployedBackend = "https://ai-trainer-app-production-c991.up.railway.app"

    /// Machines that have run the server on the local network. Kept
    /// after deploying so development against a laptop still works:
    /// with `deployedBackend` set these are only reached if it's
    /// unreachable, which on a phone away from home it always will be.
    private static let localBackends = [
        "http://Federicos-Mac-mini.local:8000",
        "http://Federicos-MacBook-Pro.local:8000",
    ]

    /// Every address worth trying, best first. ServerDiscovery works
    /// down this list and keeps the first that answers as a real,
    /// working backend.
    static let backendCandidates: [URL] = (
        [deployedBackend] + localBackends
    ).compactMap { address in
        let trimmed = address.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : URL(string: trimmed)
    }

    /// Where requests go before anything has been resolved, and the
    /// address an error screen names.
    static let backendURL = backendCandidates.first
        ?? URL(string: "http://localhost:8000")!

    // MARK: - How long we wait

    /// Ceiling on any ordinary request. These are small reads that
    /// normally answer in a fraction of a second, so 30s is already
    /// enormously generous -- it exists only so a dead or unreachable
    /// host fails visibly instead of hanging.
    static let requestTimeout: TimeInterval = 30

    /// POST /turn is the one request that waits on a real model call,
    /// measured at 12-18s against an almost-empty database and longer
    /// with a full history or an attached screenshot. Holding it to the
    /// ordinary 30s would abort answers that were on their way, so it
    /// gets its own ceiling -- still bounded, so "Coach is thinking"
    /// always ends in either an answer or a retry, never in waiting
    /// forever.
    static let coachTurnTimeout: TimeInterval = 90

    /// How long to wait on a single "are you really there?" probe while
    /// working out which address is live. Short on purpose: several of
    /// these run back to back at launch, and a wrong guess should cost
    /// a moment, not a stall. A little longer than a LAN probe needs,
    /// because a deployed host may be waking from idle.
    static let reachabilityProbeTimeout: TimeInterval = 8

    /// Second chance for the deployed backend before deciding it isn't
    /// there. A host that sleeps when idle takes several seconds to
    /// come back, and the short probe above is tuned for a machine on
    /// the LAN that either answers at once or isn't home. Without
    /// this, the first launch of the day could show "can't reach your
    /// coach" for a backend that was simply waking up.
    static let coldStartProbeTimeout: TimeInterval = 25

    // MARK: - Voice

    /// How often a recording hands over to a fresh recognition task, so
    /// no single task runs into a recognizer limit. Lossless: see
    /// TranscriptStitcher.
    static let voiceHandoverInterval: Duration = .seconds(25)

    /// The longest starting or finishing a recording may take before
    /// it's forcibly reset to idle. Finishing normally waits up to 2s
    /// for the last words, so this sits comfortably above that.
    static let voiceStallTimeout: Duration = .seconds(4)
}

/// The shared token for a deployed backend, if one is set up.
///
/// Typed once in Settings rather than compiled in, because this repo is
/// public: a secret written into a source file is published the moment
/// it's pushed. Stored per-install on the phone, and simply absent
/// while the backend is a laptop on the LAN that needs no guarding.
enum BackendAuth {
    private static let key = "backendAccessKey"

    static var token: String? {
        let stored = UserDefaults.standard.string(forKey: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (stored?.isEmpty ?? true) ? nil : stored
    }

    static func save(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set(trimmed, forKey: key)
        }
    }
}

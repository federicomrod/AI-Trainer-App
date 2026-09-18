//
//  Config.swift
//  AI-Trainer
//
//  Every knob that decides *where* the backend is and *how long* we're
//  willing to wait for it. One file, so changing the address is one
//  edit in one obvious place -- the previous arrangement buried a
//  hardcoded LAN IP in APIClient, which went stale every time the
//  router handed out a different lease.
//
//  The address is a .local hostname rather than an IP for exactly that
//  reason: mDNS resolves the name to whatever address the machine
//  currently has, so a new DHCP lease is invisible to the app.
//  Resolving a .local name needs local-network permission, which is why
//  NSLocalNetworkUsageDescription is in the Info.plist.

import Foundation

enum Config {
    /// The backend's home. Change this one line to point the app
    /// somewhere else.
    static let backendURL = URL(string: "http://Federicos-Mac-mini.local:8000")!

    /// Tried when the primary doesn't answer. The server has also run
    /// on the laptop, so during the move to the mini either machine
    /// might be the live one; without this the app would simply fail on
    /// whichever day it guessed wrong. ServerDiscovery's Bonjour browse
    /// backs both of these up and finds the server wherever it is.
    static let fallbackBackendURL = URL(string: "http://Federicos-MacBook-Pro.local:8000")!

    /// Ceiling on any ordinary request. These are local database reads
    /// that normally answer in well under a tenth of a second, so 30s
    /// is already enormously generous -- it exists only so a dead or
    /// unreachable host fails visibly instead of hanging.
    static let requestTimeout: TimeInterval = 30

    /// POST /turn is the one request that waits on a real model call,
    /// measured at 12-18s against an almost-empty database and longer
    /// with a full history or an attached screenshot. Holding it to the
    /// ordinary 30s would abort answers that were on their way, so it
    /// gets its own ceiling -- still bounded, so "Coach is thinking"
    /// always ends in either an answer or a retry, never in waiting
    /// forever.
    static let coachTurnTimeout: TimeInterval = 90

    /// How long to wait on a single "are you there?" probe while
    /// working out which address is live. Short on purpose: several of
    /// these run back to back at launch, and a wrong guess should cost
    /// a moment, not a stall.
    static let reachabilityProbeTimeout: TimeInterval = 3
}

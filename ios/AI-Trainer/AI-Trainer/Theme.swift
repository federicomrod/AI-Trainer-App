//
//  Theme.swift
//  AI-Trainer
//
//  The whole visual language in one place: dark-first, warm charcoal
//  (not navy, not pure black), one confident accent spent sparingly,
//  soft rounded cards. This is a companion, not a dashboard -- no
//  red/green status coding and no gauges/rings anywhere in this app;
//  a single accent carries emphasis instead, on whatever's the hero
//  of that particular screen (today's session, a trend line).
//
//  Applied at the root via .preferredColorScheme(.dark) and .tint(),
//  so most controls (buttons, pickers, the tab bar's selected icon)
//  pick up the accent automatically with no per-view work. This file
//  only touches color, type, and spacing -- it doesn't restructure
//  any layout already built.

import SwiftUI

enum Theme {
    // Warm charcoal. Deliberately not navy, not pure black -- a hint
    // of warmth in the darkness rather than a cold "data" tone.
    static let background = Color(red: 0.098, green: 0.090, blue: 0.086)
    static let card = Color(red: 0.157, green: 0.145, blue: 0.137)
    static let cardElevated = Color(red: 0.196, green: 0.180, blue: 0.169)

    // The one accent, used for the hero element of each screen and
    // nothing else -- not status coding, not decoration.
    static let accent = Color(red: 1.0, green: 0.616, blue: 0.290)

    static let textPrimary = Color(red: 0.961, green: 0.941, blue: 0.914)
    static let textSecondary = Color(red: 0.663, green: 0.624, blue: 0.584)

    static let cardRadius: CGFloat = 20
    static let controlRadius: CGFloat = 14
}

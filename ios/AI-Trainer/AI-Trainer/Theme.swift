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
//  pick up the accent automatically with no per-view work.
//
//  Second pass: the first visual pass was deliberately restricted to
//  color/type/spacing on top of default SwiftUI components. This one
//  lifts that -- real card elevation (gradient fill, shadow) on
//  whatever's the hero of a screen, SF Rounded for headers, a faint
//  warm bleed in the background instead of a flat fill. Still one
//  accent, still no rings/scores -- structure and material, not new
//  colors.

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
    static let heroCardRadius: CGFloat = 24
    static let controlRadius: CGFloat = 14

    /// SF Rounded for headers -- the quick, real-difference change
    /// toward Day One/Things 3's warmth instead of default San
    /// Francisco everywhere.
    static func rounded(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .rounded).weight(weight)
    }
}

/// The subtle gradient fill for whatever card is leading a screen
/// (today's session, today's entry in Week) -- not a flat color, a
/// soft lift from cardElevated into card so it reads as lit from
/// above rather than a flat rectangle.
extension View {
    func heroCard() -> some View {
        self
            .background(
                LinearGradient(
                    colors: [Theme.cardElevated, Theme.card],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: Theme.heroCardRadius)
            )
            .shadow(color: .black.opacity(0.4), radius: 18, x: 0, y: 10)
            .shadow(color: Theme.accent.opacity(0.08), radius: 24, x: 0, y: 0)
    }

    /// The normal, non-hero card -- flat fill, no shadow. Still soft
    /// and rounded, just not competing for attention.
    func flatCard(radius: CGFloat = Theme.cardRadius) -> some View {
        self.background(Theme.card, in: RoundedRectangle(cornerRadius: radius))
    }

    /// A finished/past entry: lower contrast, tighter, sits flatter
    /// than a flat card even -- a record to glance at, not something
    /// competing with what's still actionable.
    func quietCard(radius: CGFloat = Theme.cardRadius) -> some View {
        self
            .background(Theme.card, in: RoundedRectangle(cornerRadius: radius))
            .opacity(0.72)
    }

    /// The app-wide backdrop: warm charcoal with a faint radial bleed
    /// of the accent color from the top, instead of one flat fill.
    /// This alone is a big part of why Flighty/Day One read as alive
    /// rather than just "dark mode."
    func appBackground() -> some View {
        self.background(
            ZStack {
                Theme.background
                RadialGradient(
                    colors: [Theme.accent.opacity(0.06), Theme.accent.opacity(0.0)],
                    center: .top, startRadius: 0, endRadius: 480
                )
            }
            .ignoresSafeArea()
        )
    }
}

/// One SF Symbol per session type, filled style, always accent-
/// colored -- shown consistently in Today and Week so a session's
/// kind reads at a glance instead of needing to parse the label text.
enum SessionTypeIcon {
    static func symbolName(for type: String) -> String {
        let lowered = type.lowercased()
        if lowered.contains("push") { return "figure.strengthtraining.traditional" }
        // figure.strengthtraining.functional reads too close to
        // figure.run at a glance (similar dynamic-pose silhouette) --
        // rowing's pulling motion is a much more distinct shape.
        if lowered.contains("pull") { return "figure.rower" }
        if lowered.contains("legs") { return "figure.squat" }
        if lowered.contains("swim") { return "figure.pool.swim" }
        if lowered.contains("run") { return "figure.run" }
        if lowered.contains("ride") || lowered.contains("cycl") { return "figure.outdoor.cycle" }
        if lowered.contains("interval") { return "bolt.fill" }
        if lowered.contains("rest") { return "moon.zzz.fill" }
        return "figure.mixed.cardio"
    }
}

/// One small, consistent marker per voice in coach-voice.md's cast --
/// Head Coach speaks in almost every message and gets the same marker
/// every time (a person icon, not a color, since it's the default/
/// near-constant voice); a specialist is the rare one and gets its own
/// distinct icon so a multi-voice moment reads as someone else
/// chiming in, not a different mood of the same coach. One accent
/// color throughout -- the icon shape carries the distinction, not a
/// new hue per speaker.
enum SpeakerStyle {
    static func icon(for speaker: String) -> String {
        switch speaker {
        case "head_coach": return "person.fill"
        case "strength": return "dumbbell.fill"
        case "endurance": return "bolt.heart.fill"
        case "recovery": return "leaf.fill"
        default: return "person.fill"
        }
    }

    static func label(for speaker: String) -> String {
        switch speaker {
        case "head_coach": return "Coach"
        case "strength": return "Strength"
        case "endurance": return "Endurance"
        case "recovery": return "Recovery"
        default: return speaker.capitalized
        }
    }
}

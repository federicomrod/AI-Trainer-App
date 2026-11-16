//
//  Theme.swift
//  AI-Trainer
//
//  The whole visual language in one place, from the approved mockup
//  (docs/overnight-ios-brief.md, "The look"): near-black background,
//  three stepped surfaces, neon lime for strength and "done", a cool
//  blue for endurance. Heavy SF Pro with tight tracking for headings,
//  large radii everywhere.
//
//  Applied at the root via .preferredColorScheme(.dark) and .tint(),
//  so most controls pick up the lime automatically. Anything that puts
//  text ON lime must use Theme.onAccent -- white on lime is unreadable.
//
//  The older names (card, cardElevated, textSecondary, ...) are kept
//  as aliases of the new tokens so every screen keeps compiling and
//  picks up the new look without a rewrite.

import SwiftUI

extension Color {
    /// "#D4FF3A" -> Color. Only for the fixed tokens below.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

enum Theme {
    // MARK: Colors

    static let background = Color(hex: 0x09090B)
    /// Three surface steps, lowest to highest.
    static let surface1 = Color(hex: 0x141417)
    static let surface2 = Color(hex: 0x1C1C21)
    static let surface3 = Color(hex: 0x25252B)

    static let textPrimary = Color(hex: 0xF4F4F6)
    static let textMuted = Color(hex: 0x9A9AA5)

    /// Neon lime: strength, "done", the primary action.
    static let accent = Color(hex: 0xD4FF3A)
    /// Text and icons drawn on top of lime.
    static let onAccent = Color(hex: 0x0A0A0A)
    /// Endurance blue: ride, run, swim, intervals.
    static let endurance = Color(hex: 0x6C8CFF)

    // Older names, kept so existing screens compile unchanged.
    static let card = surface1
    static let cardElevated = surface2
    static let textSecondary = textMuted

    // MARK: Shape

    static let heroCardRadius: CGFloat = 28
    static let cardRadius: CGFloat = 24
    static let rowRadius: CGFloat = 18
    static let controlRadius: CGFloat = 18

    // MARK: Type

    /// SF Pro at a text style, so Dynamic Type still works.
    static func font(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style).weight(weight)
    }

    /// The big screen heading ("Today"): heavy SF Pro.
    static let screenTitle = Font.system(size: 40, weight: .heavy)
    /// Small caps-style label above a heading (the date on Today).
    static let eyebrow = Font.system(.footnote).weight(.semibold)
}

extension View {
    /// A big heavy heading with the tight tracking from the mockup.
    func screenTitleStyle() -> some View {
        self.font(Theme.screenTitle)
            .tracking(-1.2)
            .foregroundStyle(Theme.textPrimary)
    }

    /// The small label above a heading, e.g. "MONDAY 16 NOV".
    func eyebrowStyle() -> some View {
        self.font(Theme.eyebrow)
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(Theme.textMuted)
    }

    /// The card leading a screen (today's session): the highest
    /// surface, largest radius, a hairline edge so it lifts off the
    /// near-black background.
    func heroCard() -> some View {
        self
            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.heroCardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.heroCardRadius)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
    }

    /// The normal card.
    func flatCard(radius: CGFloat = Theme.cardRadius) -> some View {
        self.background(Theme.surface1, in: RoundedRectangle(cornerRadius: radius))
    }

    /// A finished/past entry: same surface, lower contrast.
    func quietCard(radius: CGFloat = Theme.cardRadius) -> some View {
        self
            .background(Theme.surface1, in: RoundedRectangle(cornerRadius: radius))
            .opacity(0.72)
    }

    /// One wide, low row (an exercise, a goal).
    func rowCard(fill: Color = Theme.surface2) -> some View {
        self.background(fill, in: RoundedRectangle(cornerRadius: Theme.rowRadius))
    }

    /// The app-wide backdrop: flat near-black.
    func appBackground() -> some View {
        self.background(Theme.background.ignoresSafeArea())
    }
}

/// The one big lime action on a screen ("Start workout"). Full width,
/// fully round, dark text on lime.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline).weight(.bold))
            .foregroundStyle(Theme.onAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.accent, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

/// A quieter round button on a raised surface ("Why this").
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline).weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.surface3, in: Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

/// A small fully-round chip: "Bench press · 4 x 8-12".
struct Pill: View {
    let text: String
    var fill: Color = Theme.surface3
    var foreground: Color = Theme.textPrimary

    var body: some View {
        Text(text)
            .font(.system(.caption).weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(fill, in: Capsule())
    }
}

/// One SF Symbol per session type, shown consistently in Today and
/// Week so a session's kind reads at a glance. Colored by family:
/// lime for strength, blue for endurance (see `tint(for:)`).
enum SessionTypeIcon {
    /// Endurance work is blue, everything else (strength, rest) lime.
    static func isEndurance(_ type: String) -> Bool {
        let lowered = type.lowercased()
        return ["ride", "cycl", "run", "swim", "interval"].contains { lowered.contains($0) }
    }

    static func tint(for type: String) -> Color {
        isEndurance(type) ? Theme.endurance : Theme.accent
    }

    static func symbolName(for type: String) -> String {
        let lowered = type.lowercased()
        if lowered.contains("push") { return "figure.strengthtraining.traditional" }
        // figure.strengthtraining.functional reads too close to
        // figure.run at a glance (similar dynamic-pose silhouette) --
        // rowing's pulling motion is a much more distinct shape.
        if lowered.contains("pull") { return "figure.rower" }
        if lowered.contains("legs") { return "figure.cross.training" }
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
        // Not a coach: this is the app reporting what it wrote down.
        case "log": return "checkmark.circle.fill"
        default: return "person.fill"
        }
    }

    static func label(for speaker: String) -> String {
        switch speaker {
        case "head_coach": return "Coach"
        case "strength": return "Strength"
        case "endurance": return "Endurance"
        case "recovery": return "Recovery"
        case "log": return "Saved"
        default: return speaker.capitalized
        }
    }
}

// MARK: - Keyboard

#if os(iOS)
/// Puts the keyboard away whatever has it.
///
/// Every screen that takes typing needs this, and not every field can
/// dismiss itself: a decimal or number pad has no return key at all,
/// and a multi-line field's return key inserts a newline. Without a
/// way out, the keyboard sits over the tab bar and the app is stuck
/// until it's force-quit -- which is exactly what happened on Coach.
func dismissKeyboard() {
    UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
    )
}

extension View {
    /// A Done button on the keyboard's own toolbar, shown only while
    /// the keyboard is up. Use on screens with several fields, where
    /// tracking focus per field would be noise; a single field is
    /// clearer with @FocusState (see ChatView).
    func keyboardDoneButton() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { dismissKeyboard() }
            }
        }
    }
}
#endif

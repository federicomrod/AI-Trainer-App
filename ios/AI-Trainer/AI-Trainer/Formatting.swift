//
//  Formatting.swift
//  AI-Trainer
//
//  Small display helpers shared by every screen, so the same thing
//  reads the same way everywhere:
//
//  - DayLabel: one date format, "Sun 22 Nov".
//  - plainHyphens: en dashes and other dash look-alikes the coach
//    writes in exercise names ("high–wide") shown as a plain "-".
//  - SessionTitle: "legs" -> "Legs", and which session a day really
//    became when a coaching decision changed it.

import Foundation

enum DayLabel {
    /// "Sun 22 Nov" for a server date ("2026-11-22").
    static func from(iso: String) -> String {
        guard let date = isoDayFormatter.date(from: String(iso.prefix(10))) else { return iso }
        return utcFormatter.string(from: date)
    }

    /// "Sun 22 Nov" for a moment on the athlete's own clock.
    static func from(date: Date) -> String {
        localFormatter.string(from: date)
    }

    /// Today as the server writes dates: "2026-11-22", local calendar.
    static var todayISO: String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static let utcFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEE d MMM"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private static let localFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEE d MMM"
        return f
    }()
}

extension String {
    /// En dash, figure dash and non-breaking hyphen shown as a plain
    /// hyphen. Display only; what's stored is left as written.
    var plainHyphens: String {
        var s = self
        for dash in ["\u{2013}", "\u{2012}", "\u{2011}", "\u{2010}"] {
            s = s.replacingOccurrences(of: dash, with: "-")
        }
        return s
    }
}

enum SessionTitle {
    /// "upper_push" -> "Upper Push", "legs" -> "Legs".
    static func display(_ type: String) -> String {
        type.replacingOccurrences(of: "_", with: " ").plainHyphens.capitalized
    }

    /// Words that say "a workout" without saying which one. When the
    /// coach's plan uses one of these, the day's own session type
    /// (from the week) names it better.
    static func isGeneric(_ type: String) -> Bool {
        ["gym", "strength", "workout", "session", "training", "other", "lift", "lifting", ""]
            .contains(type.lowercased().trimmingCharacters(in: .whitespaces))
    }
}

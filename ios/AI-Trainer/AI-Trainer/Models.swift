//
//  Models.swift
//  AI-Trainer
//
//  Mirrors the decision JSON schema from CLAUDE.md and the shape of
//  server/api.py's /turn response exactly. Field names differ only in
//  case convention (snake_case on the wire, camelCase in Swift) --
//  CodingKeys spell out the mapping so it's obvious at a glance which
//  wire field each property comes from.

import Foundation

/// One exercise prescription within today's session.
struct Exercise: Codable, Identifiable {
    var id: String { name }
    let name: String
    let sets: Int
    let reps: String
    let note: String?
}

/// Today's prescribed session, part of a Decision.
struct TodaySession: Codable {
    let type: String
    let durationMin: Int
    let exercises: [Exercise]
    let intensityNote: String

    enum CodingKeys: String, CodingKey {
        case type
        case durationMin = "duration_min"
        case exercises
        case intensityNote = "intensity_note"
    }
}

/// One change to the rest of the week's plan, alongside today's call.
struct PlanDiffEntry: Codable, Identifiable {
    var id: String { "\(date)-\(from)-\(to)" }
    let date: String
    let from: String
    let to: String
    let reason: String
}

/// A specialist coach's note, alongside the Head Coach's own
/// reasoning. Per prompts/coach-voice.md, this is usually empty --
/// a specialist speaks only when they'd change or defend the decision.
struct SpecialistNote: Codable, Identifiable {
    var id: String { coach }
    let coach: String
    let text: String
}

/// The decision itself: KEEP, MODIFY, or REST, plus everything that
/// explains it. This is exactly what the one planner call returns,
/// already validated by the backend before the app ever sees it.
struct Decision: Codable {
    let decision: String
    let today: TodaySession
    let why: String
    let planDiff: [PlanDiffEntry]
    let specialistNotes: [SpecialistNote]
    let memoryToAdd: [String]
    let question: String?
    let safetyFlag: String?

    enum CodingKeys: String, CodingKey {
        case decision, today, why
        case planDiff = "plan_diff"
        case specialistNotes = "specialist_notes"
        case memoryToAdd = "memory_to_add"
        case question
        case safetyFlag = "safety_flag"
    }
}

/// The full response from POST /turn: the briefing that was assembled,
/// the decision (nil if the model call itself failed), the rendered
/// coach reply (nil if validation rejected the decision), and whether
/// the safety pre-check skipped the model entirely.
struct TurnResponse: Codable {
    let briefing: String
    let decision: Decision?
    let reply: String?
    let safetyFlagged: Bool
    let error: String?
    let errorDetail: String?

    enum CodingKeys: String, CodingKey {
        case briefing, decision, reply
        case safetyFlagged = "safety_flagged"
        case error
        case errorDetail = "error_detail"
    }
}

/// One row from GET /messages, for Coach chat. `text` is already the
/// final display text either way -- a user row's own words, or an
/// assistant row's reply reconstructed server-side by
/// coach.reply_text_for() from the decision JSON that was actually
/// saved. This view never sees or re-derives that JSON itself.
struct ChatMessage: Codable, Identifiable {
    let id: Int
    let role: String
    let text: String
    let timestamp: String

    var isUser: Bool { role == "user" }
}

/// One day in the current week, from GET /week. `type`/`plannedSummary`
/// are what was originally scheduled -- sessions rows are never
/// rewritten when a decision changes the plan (see server/coach.py and
/// server/week.py), so a non-nil `movedTo` is the marker that this day
/// no longer matches what's shown here, and why.
struct WeekDay: Codable, Identifiable {
    let date: String
    let weekday: String
    let isToday: Bool
    let type: String
    let status: String
    let plannedSummary: String?
    let actualSummary: String?
    let durationMin: Int?
    let movedTo: String?
    let movedReason: String?

    var id: String { date }
    var moved: Bool { movedTo != nil }

    enum CodingKeys: String, CodingKey {
        case date, weekday
        case isToday = "is_today"
        case type, status
        case plannedSummary = "planned_summary"
        case actualSummary = "actual_summary"
        case durationMin = "duration_min"
        case movedTo = "moved_to"
        case movedReason = "moved_reason"
    }
}

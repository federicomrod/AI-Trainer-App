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

/// POST /checkin's body. One check-in per calendar day -- submitting
/// again today updates that day's row server-side (see
/// server/checkin.py) rather than creating a duplicate.
struct CheckInRequest: Encodable {
    let sleep: String  // "poor" | "normal" | "good"
    let energy: Int    // 1...5
    let soreness: [String: String]
    let note: String?
}

struct CheckInResponse: Decodable {
    let id: Int
    let date: String
    let sleep: String
    let energy: Int
    let soreness: [String: String]
    let note: String?
}

/// One tracked exercise worth prompting for on the logging screen,
/// with its most recent numbers for context (e.g. "last time: 100kg
/// x3x5"). Only ever appears when the session's type plausibly
/// matches it -- see server/log_session.py's TYPE_KEYWORDS.
struct RelevantExercise: Decodable, Identifiable {
    let name: String
    let lastDate: String?
    let lastWeight: Double?
    let lastReps: Int?
    let lastSets: Int?

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name
        case lastDate = "last_date"
        case lastWeight = "last_weight"
        case lastReps = "last_reps"
        case lastSets = "last_sets"
    }
}

struct LogContextResponse: Decodable {
    let date: String
    let type: String
    let status: String
    let plannedSummary: String?
    let relevantExercises: [RelevantExercise]

    enum CodingKeys: String, CodingKey {
        case date, type, status
        case plannedSummary = "planned_summary"
        case relevantExercises = "relevant_exercises"
    }
}

/// One tracked-exercise number entered on the logging screen. `weight`
/// etc. are all optional -- an exercise the athlete skips just isn't
/// included in the submitted array at all.
struct LiftEntry: Encodable {
    let exerciseName: String
    let weight: Double?
    let reps: Int?
    let sets: Int?
    let note: String?

    enum CodingKeys: String, CodingKey {
        case exerciseName = "exercise_name"
        case weight, reps, sets, note
    }
}

struct LogSessionRequest: Encodable {
    let date: String?  // nil = today, resolved server-side
    let status: String  // "done" | "partial" | "skipped"
    let notes: String?
    let lifts: [LiftEntry]
}

struct LogSessionResponse: Decodable {
    let date: String
    let type: String
    let status: String
    let actualSummary: String?

    enum CodingKeys: String, CodingKey {
        case date, type, status
        case actualSummary = "actual_summary"
    }
}

/// GET/PUT /goals. List order IS priority order -- CLAUDE.md's profile
/// table has no separate priority field, first = highest priority.
struct GoalsPayload: Codable {
    let goals: [String]
}

/// Both progress series use plain "yyyy-MM-dd" dates from the server;
/// parsed once here so charts get a real continuous timeline instead
/// of evenly-spaced category labels.
let isoDayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.timeZone = TimeZone(identifier: "UTC")
    return f
}()

/// One point in an exercise's weight-over-time series, from
/// GET /progress.
struct LiftPoint: Decodable, Identifiable {
    let date: String
    let weight: Double

    var id: String { date }
    var dateValue: Date { isoDayFormatter.date(from: date) ?? Date() }
}

struct WeeklySessionCount: Decodable, Identifiable {
    let weekStart: String
    let count: Int

    var id: String { weekStart }
    var weekStartValue: Date { isoDayFormatter.date(from: weekStart) ?? Date() }

    enum CodingKeys: String, CodingKey {
        case weekStart = "week_start"
        case count
    }
}

struct ProgressResponse: Decodable {
    let lifts: [String: [LiftPoint]]
    let weeklySessions: [WeeklySessionCount]

    enum CodingKeys: String, CodingKey {
        case lifts
        case weeklySessions = "weekly_sessions"
    }
}

/// One workout read from HealthKit, on its way to POST
/// /healthkit_import. `hkType` is the raw HKWorkoutActivityType name
/// (see HealthKitManager) -- server/healthkit_import.py owns the
/// mapping to a session type, so an unrecognized type is the server's
/// call to skip, not this struct's.
struct HealthKitWorkout: Encodable {
    let date: String
    let hkType: String
    let durationMin: Int?
    let summary: String?

    enum CodingKeys: String, CodingKey {
        case date
        case hkType = "hk_type"
        case durationMin = "duration_min"
        case summary
    }
}

struct HealthKitImportRequest: Encodable {
    let workouts: [HealthKitWorkout]
}

struct HealthKitImportResponse: Decodable {
    let imported: Int
    let skipped: Int
}

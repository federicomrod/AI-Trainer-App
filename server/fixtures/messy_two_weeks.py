"""
Fixture: messy_two_weeks

Two weeks with real interruptions — a rained-out ride, a hike that
wrecks leg day, and a wedding weekend that eats two sessions. This is
the fixture for testing whether the coach handles real life well.

Every *_rows() function returns a list of tuples ready to insert,
in the exact column order db.py defines for that table. seed.py just
loops over them; all the story lives here.
"""

import json
from datetime import date, timedelta

TODAY = date(2026, 9, 14)  # Monday


def d(offset):
    """TODAY plus/minus N days, as an ISO date string."""
    return (TODAY + timedelta(days=offset)).isoformat()


def profile_row():
    return (
        json.dumps([
            "Keep getting stronger, don't shrink",
            "Build real cycling endurance for a fondo next spring",
            "General aerobic fitness / long-term health",
        ]),
        "5-6 days/week, mornings before work, weekends flexible but "
        "often social",
        60,
        "Full commercial gym, own road bike, pool access 2x/week",
        json.dumps(["hip thrust", "pull-ups", "incline DB press"]),
        json.dumps(["back extensions", "treadmill running"]),
        "Mild lower back stiffness if deadlifting heavy 2 days in a row",
        "Intermediate — lifting 4+ years, new to structured endurance",
    )


# (day offset, type, status, planned_summary, actual_summary,
#  duration_min, rpe, notes, source)
_SESSIONS = [
    # --- Week 1: Aug 31 - Sep 6 ---
    (-14, "push", "done",
     "Upper push: incline DB press, OHP, dips, lateral raise",
     "Incline DB press, OHP, dips, lateral raise to finish. Good session.",
     62, 7, None, "manual"),
    (-13, "run", "done", "Easy 30 min run",
     "30 min easy, felt good, kept it conversational pace",
     30, 4, None, "healthkit"),
    (-12, "legs", "done",
     "Squat day: back squat, RDL, leg press, calf raise",
     "Squat day. RDL 90kg x8x3, hack squat 3x12 (swapped leg press, "
     "machine taken), calf raise 3x15.",
     65, 8, "swapped leg press for hack squat, machine was taken", "manual"),
    (-11, "rest", "done", "Rest day", None, None, None, None, None),
    (-10, "pull", "done", "Pull day: pull-ups, barbell row, face pull, curl",
     "Pull day. Barbell row 70kg x8x3, face pull 3x15, curl 3x12.",
     58, 7, None, "manual"),
    (-9, "ride", "partial", "Long ride 90 min Z2",
     "Cut short by rain, 55 min easy before it hit",
     55, 6, "rain cut it short", "voice"),
    (-8, "rest", "done", "Rest day", None, None, None, None, None),

    # --- Week 2: Sep 7 - Sep 13 ---
    (-7, "push", "done", "Upper push, chest emphasis",
     "Incline DB press, OHP, dips. Chest lead as planned.",
     60, 7, None, "manual"),
    (-6, "run", "skipped", "Easy 30 min run", None, None, None,
     "went hiking with family instead, ~12k steps", "manual"),
    (-5, "legs", "done", "Squat day",
     "Legs still tired from the hike, backed off: RDL 85kg x8x3, "
     "leg curl 3x12, hip thrust 100kg x10x3, skipped squat entirely",
     55, 6, "legs still tired from Tuesday's hike, dropped squat", "manual"),
    (-4, "swim", "done", "40 min easy swim",
     "40 min continuous easy aerobic",
     40, 4, None, "manual"),
    (-3, "pull", "done", "Pull day",
     "Pull day. Barbell row 72.5kg x8x3, face pull 3x15.",
     60, 7, None, "manual"),
    (-2, "ride", "skipped", "Long ride 2hr Z2", None, None, None,
     "wedding rehearsal dinner, skipped", "manual"),
    (-1, "swim", "skipped", "Easy recovery swim, 30 min", None, None, None,
     "wedding day, exhausted, slept in", "manual"),

    # --- This week's plan, starting today (Mon Sep 14) ---
    (0, "push", "planned", "Upper push, as usual", None, None, None, None, None),
    (1, "run", "planned", "Easy 30 min run", None, None, None, None, None),
    (2, "legs", "planned", "Squat day", None, None, None, None, None),
    (3, "swim", "planned", "40 min easy swim", None, None, None, None, None),
    (4, "pull", "planned", "Pull day", None, None, None, None, None),
    (5, "ride", "planned", "Long ride 90 min Z2", None, None, None, None, None),
    (6, "rest", "planned", "Rest day", None, None, None, None, None),
]


def session_rows():
    return [
        (d(offset), type_, status, planned, actual, dur, rpe, notes, source)
        for (offset, type_, status, planned, actual, dur, rpe, notes, source)
        in _SESSIONS
    ]


# (day offset, exercise_name, weight, reps, sets, note)
# Note squat has no entry after Sep 2 — it got dropped after the hike
# and hasn't come back yet. That gap is deliberate: it's the test case
# for "never chases one that's gone quiet".
_LIFTS = [
    (-12, "Back Squat", 100, 5, 3, "RPE 8"),
    (-10, "Weighted Pull-up", 20, 5, 4, "added weight"),
    (-3, "Weighted Pull-up", 22.5, 5, 4, None),
]


def lift_rows():
    return [
        (d(offset), name, weight, reps, sets, note)
        for (offset, name, weight, reps, sets, note) in _LIFTS
    ]


# (day offset, sleep, energy, soreness dict, pain_flag, note)
_CHECKINS = [
    (-12, "normal", 4, {"legs": "low"}, 0, None),
    (-9, "normal", 4, {"legs": "moderate"}, 0, "legs a little flat after squats"),
    (-6, "good", 4, {"legs": "low"}, 0, None),
    (-5, "poor", 2, {"legs": "high"}, 0,
     "legs wrecked from the hike, slept badly too"),
    (-2, "normal", 3, {"legs": "low"}, 0, None),
    (0, "normal", 3, {"legs": "moderate", "shoulders": "low"}, 0,
     "still catching up on sleep after the wedding, legs a bit tired "
     "generally, nothing sharp"),
]


def checkin_rows():
    return [
        (d(offset), sleep, energy, json.dumps(soreness), pain, note)
        for (offset, sleep, energy, soreness, pain, note) in _CHECKINS
    ]


# (start offset, end offset, type, note, effect_on_availability)
_EVENTS = [
    (-6, -6, "big_walk", "Family hike, ~12k steps",
     "legs more fatigued than usual the next day, treat like a light "
     "extra session"),
    (-2, -1, "social", "Friend's wedding, rehearsal dinner Saturday, "
     "reception Sunday", "skipped weekend cardio, short on sleep into "
     "Monday"),
    (6, 8, "travel", "Work trip, flying out Sunday",
     "hotel gym unconfirmed, may only have bodyweight options"),
]


def event_rows():
    return [
        (d(start), d(end), type_, note, effect)
        for (start, end, type_, note, effect) in _EVENTS
    ]


# (day offset, text)
_MEMORY = [
    (-12, "responds well to swapping leg press for hack squat, no "
          "noticeable drop-off"),
    (-5, "prefers hip thrust over back squat when legs are already "
         "fried, rather than forcing the squat"),
    (-1, "long weekend social events tend to wipe out Sunday sessions — "
         "treat Monday as a soft reset, not a missed week"),
]


def memory_rows():
    return [(d(offset), text) for (offset, text) in _MEMORY]


# Two real coaching decisions from these two weeks, stored the way the
# app will actually store them once the planner exists: the assistant
# message's content IS the decision JSON. This is what lets the
# "recent decisions" briefing section work, and it's what a rendering
# layer would later turn into coach-voice text.
_DECISION_HIKE = {
    "decision": "MODIFY",
    "today": {
        "type": "legs",
        "duration_min": 55,
        "exercises": [
            {"name": "RDL", "sets": 3, "reps": "6-8",
             "note": "moderate, not a squat replacement"},
            {"name": "Leg curl", "sets": 3, "reps": "10-15", "note": ""},
            {"name": "Hip thrust", "sets": 3, "reps": "8-10",
             "note": "fine to load, hips aren't the fatigued part"},
        ],
        "intensity_note": "back off overall, skip the squat",
    },
    "why": "12k steps of hiking is real fatigue in the same muscles a "
           "squat day would hit. Dropping the squat and leaning on hip "
           "thrust and RDL keeps the session useful without digging "
           "the hole deeper.",
    "plan_diff": [
        {"date": "2026-09-09", "from": "legs (squat-focused)",
         "to": "legs (squat dropped, hip thrust + RDL)",
         "reason": "unplanned 12k-step hike left legs too fatigued for "
                    "a normal squat day"},
    ],
    "specialist_notes": [],
    "memory_to_add": ["legs run down for ~24-36h after a long unplanned "
                       "walk/hike"],
    "question": None,
    "safety_flag": None,
}

_DECISION_WEDDING = {
    "decision": "MODIFY",
    "today": {
        "type": "pull",
        "duration_min": 60,
        "exercises": [
            {"name": "Weighted pull-up", "sets": 4, "reps": "4-6",
             "note": "push this one, nothing competing with it this "
                     "weekend"},
            {"name": "Barbell row", "sets": 3, "reps": "8-10", "note": ""},
            {"name": "Face pull", "sets": 3, "reps": "15", "note": ""},
        ],
        "intensity_note": "normal pull day, nothing to hold back for",
    },
    "why": "Good call flagging it now rather than after. Saturday's ride "
           "and Sunday's swim come off the plan instead of sitting there "
           "as pressure you'll ignore anyway.",
    "plan_diff": [
        {"date": "2026-09-12", "from": "ride", "to": "rest (optional)",
         "reason": "wedding weekend, protecting a realistic plan over "
                    "an ambitious ride that wasn't going to happen"},
        {"date": "2026-09-13", "from": "swim", "to": "rest",
         "reason": "wedding weekend, same reason"},
    ],
    "specialist_notes": [],
    "memory_to_add": [],
    "question": None,
    "safety_flag": None,
}

# (day offset, time, role, content)
_MESSAGES = [
    (-6, "08:10", "user",
     "hiked all day yesterday with the family, like 12k steps, legs are "
     "trashed. still doing squats today?"),
    (-6, "08:11", "assistant", json.dumps(_DECISION_HIKE)),
    (-3, "07:40", "user",
     "heads up, friend's wedding this weekend — rehearsal dinner sat, "
     "reception sun, gonna be a lot of standing and drinking. "
     "realistically the ride and swim probably aren't happening"),
    (-3, "07:41", "assistant", json.dumps(_DECISION_WEDDING)),
]


def message_rows():
    return [
        (role, content, f"{d(offset)}T{time}:00")
        for (offset, time, role, content) in _MESSAGES
    ]

"""
Fixture: calm_two_weeks

Two weeks where absolutely nothing went wrong: the plan happened
exactly as planned, sleep was normal, no events, no plan changes. This
exists to test the opposite failure mode from messy_two_weeks — a coach
that invents a change to seem useful is just as broken as one that
ignores real problems. The right decision on this fixture is KEEP,
every day, with a one-line "why".

Same shape as messy_two_weeks.py: each *_rows() returns tuples in the
exact column order db.py defines.
"""

import json
from datetime import date, timedelta

TODAY = date(2026, 9, 14)  # Monday, same anchor as the messy fixture


def d(offset):
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


# One repeating weekly template, executed exactly as planned both
# weeks: push / run / legs / swim / pull / ride / rest.
_TEMPLATE = [
    ("push", "Upper push, chest lead"),
    ("run", "Easy 30 min run"),
    ("legs", "Squat day"),
    ("swim", "40 min easy swim"),
    ("pull", "Pull day"),
    ("ride", "Long ride 90 min Z2"),
    ("rest", "Rest day"),
]
_DURATIONS = {"push": 60, "run": 30, "legs": 60, "swim": 40, "pull": 58,
              "ride": 90, "rest": None}
_RPE = {"push": 7, "run": 4, "legs": 7, "swim": 4, "pull": 7, "ride": 6,
        "rest": None}


def session_rows():
    rows = []
    # Two past weeks, both done exactly as planned.
    for week_offset in (-14, -7):
        for i, (type_, planned) in enumerate(_TEMPLATE):
            offset = week_offset + i
            dur = _DURATIONS[type_]
            rpe = _RPE[type_]
            actual = None if type_ == "rest" else f"{planned}. Went as planned."
            rows.append((
                d(offset), type_, "done", planned, actual, dur, rpe, None,
                "manual" if type_ != "rest" else None,
            ))
    # This week, still just planned — same template continuing.
    for i, (type_, planned) in enumerate(_TEMPLATE):
        rows.append((d(i), type_, "planned", planned, None, None, None,
                     None, None))
    return rows


# Steady, gap-free progress on the same two lifts — contrast with
# messy_two_weeks.py, where squat goes quiet after one entry.
_LIFTS = [
    (-12, "Back Squat", 97.5, 5, 3, None),
    (-5, "Back Squat", 100, 5, 3, "felt solid"),
    (-10, "Weighted Pull-up", 17.5, 5, 4, "added weight"),
    (-3, "Weighted Pull-up", 20, 5, 4, None),
]


def lift_rows():
    return [
        (d(offset), name, weight, reps, sets, note)
        for (offset, name, weight, reps, sets, note) in _LIFTS
    ]


# Boringly normal, every check-in.
_CHECKIN_OFFSETS = [-12, -9, -6, -3, -1, 0]


def checkin_rows():
    return [
        (d(offset), "normal", 4, json.dumps({"legs": "low"}), 0, None)
        for offset in _CHECKIN_OFFSETS
    ]


def event_rows():
    return []  # nothing happened


def memory_rows():
    return []  # nothing new to learn from a week that went to plan


def message_rows():
    return []  # no plan changes were needed, so no decisions to log

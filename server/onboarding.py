"""
onboarding.py — first run: who the athlete is, and what their week
normally looks like.

This is what fills the PROFILE section of the briefing (briefing.py),
which is most of what separates this from a generic chatbot. It writes
the one profile row, and optionally turns a weekly routine ("Mon push,
Tue run, ...") into real planned sessions.

One deliberate rule about that routine: it only creates sessions from
today forward. Back-filling the days already gone this week would
invent training that never happened -- exactly the problem that made
the fixture data useless to reason about. Real history gets in the
honest way: by logging it, or by telling the coach.
"""

import json
from datetime import timedelta

# Matches the CHECK constraint on sessions.type in db.py. A routine
# naming anything else is rejected rather than silently dropped, so a
# typo surfaces at setup instead of as a quietly missing training day.
SESSION_TYPES = (
    "push", "pull", "legs", "ride", "run", "swim", "intervals", "rest",
)

WEEKDAYS = (
    "monday", "tuesday", "wednesday", "thursday", "friday",
    "saturday", "sunday",
)


class OnboardingError(Exception):
    """Raised when the submitted setup can't be stored as given."""


def get_profile(conn):
    """The athlete's profile, or None if they haven't set one up yet.
    None is what the app treats as "show onboarding"."""
    row = conn.execute("SELECT * FROM profile WHERE id = 1").fetchone()
    if row is None:
        return None
    return {
        "goals": json.loads(row["goals_json"]),
        "weekly_availability": row["weekly_availability"],
        "typical_session_length_min": row["typical_session_length_min"],
        "equipment": row["equipment"],
        "preferred_exercises": json.loads(row["preferred_exercises_json"] or "[]"),
        "disliked_exercises": json.loads(row["disliked_exercises_json"] or "[]"),
        "injuries": row["injuries"],
        "experience_level": row["experience_level"],
    }


def validate_setup(profile, routine):
    """Check the whole submission before any of it is written.

    Split out from the writers on purpose: saving the profile and
    planning the week are two commits, so validating as we went meant a
    bad routine could reject the request *after* the profile had
    already been replaced -- leaving a half-applied setup behind. All
    the checks happen here, first, and nothing is written unless they
    all pass.
    """
    if not profile.get("goals"):
        raise OnboardingError(
            "At least one goal is required -- the coach weighs everything "
            "against them, so with none there's nothing to reason from."
        )
    if not routine:
        return
    unknown_days = [d for d in routine if d.lower() not in WEEKDAYS]
    if unknown_days:
        raise OnboardingError(f"Not weekdays: {', '.join(sorted(unknown_days))}")
    unknown_types = [t for t in routine.values() if t.lower() not in SESSION_TYPES]
    if unknown_types:
        raise OnboardingError(
            f"Unknown session type(s): {', '.join(sorted(set(unknown_types)))}. "
            f"Use one of: {', '.join(SESSION_TYPES)}"
        )


def save_profile(conn, profile):
    """Write the single profile row, replacing whatever was there.
    INSERT OR REPLACE on a fixed id = 1 because CLAUDE.md's profile
    table is one row by design -- one athlete, v1. Assumes
    validate_setup() has already passed."""
    conn.execute(
        """INSERT OR REPLACE INTO profile
           (id, goals_json, weekly_availability, typical_session_length_min,
            equipment, preferred_exercises_json, disliked_exercises_json,
            injuries, experience_level)
           VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?)""",
        (
            json.dumps(profile["goals"]),
            profile.get("weekly_availability"),
            profile.get("typical_session_length_min"),
            profile.get("equipment"),
            json.dumps(profile.get("preferred_exercises") or []),
            json.dumps(profile.get("disliked_exercises") or []),
            profile.get("injuries"),
            profile.get("experience_level"),
        ),
    )
    conn.commit()


def apply_routine(conn, routine, today):
    """Turn {"monday": "push", ...} into planned sessions for the rest
    of this week (today through Sunday). Returns the dates written.

    Skips any date that already has a session, so this can't overwrite
    something already planned or logged. Assumes validate_setup() has
    already passed.
    """
    if not routine:
        return []

    by_weekday = {day.lower(): kind.lower() for day, kind in routine.items()}
    # Monday of the current week, then walk forward to Sunday.
    monday = today - timedelta(days=today.weekday())
    written = []
    for offset in range(7):
        day = monday + timedelta(days=offset)
        if day < today:
            continue  # never invent training for days already gone
        kind = by_weekday.get(WEEKDAYS[offset])
        if kind is None:
            continue
        existing = conn.execute(
            "SELECT id FROM sessions WHERE date = ?", (day.isoformat(),)
        ).fetchone()
        if existing is not None:
            continue
        conn.execute(
            """INSERT INTO sessions
               (date, type, status, planned_summary, source)
               VALUES (?, ?, 'planned', ?, 'manual')""",
            (day.isoformat(), kind, f"{kind.capitalize()} (from your usual week)"),
        )
        written.append(day.isoformat())
    conn.commit()
    return written

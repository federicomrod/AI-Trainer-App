"""
log_session.py — post-workout logging: mark a session done/partial/
skipped, with optional free text, and optionally record numbers for
whichever tracked exercises are plausibly relevant to that session's
type.

There's no formal link anywhere in the schema between a session's
`type` (push/pull/legs/...) and an exercise's name -- lifts.exercise_name
is free text, same as everywhere else. TYPE_KEYWORDS below is a
simple, honest heuristic for "would this exercise plausibly come up in
a session of this type", not a real categorization system. It exists
so the UI can decide whether to show a tracked-exercise number prompt
at all, per the actual ask: only when the session type matches
something the athlete already has lift history for.
"""

from datetime import date

import lift_parser

TYPE_KEYWORDS = {
    "legs": ["squat", "deadlift", "rdl", "leg", "lunge", "hip thrust"],
    "push": ["press", "bench", "dip", "push"],
    "pull": ["pull-up", "pullup", "chin-up", "row", "pulldown"],
    # ride/run/swim/intervals/rest: deliberately no keywords -- a
    # cardio or rest day never prompts for a strength number.
}


def _relevant_exercises(conn, session_type):
    """Every emergent tracked exercise (CLAUDE.md: any exercise with
    rows in `lifts`) whose name loosely matches this session type,
    each with its most recent numbers for context."""
    keywords = TYPE_KEYWORDS.get(session_type, [])
    if not keywords:
        return []

    names = conn.execute("SELECT DISTINCT exercise_name FROM lifts").fetchall()

    relevant = []
    for row in names:
        name = row["exercise_name"]
        if not any(kw in name.lower() for kw in keywords):
            continue
        last = conn.execute(
            "SELECT date, weight, reps, sets FROM lifts "
            "WHERE exercise_name = ? ORDER BY date DESC LIMIT 1",
            (name,),
        ).fetchone()
        relevant.append({
            "name": name,
            "last_date": last["date"] if last else None,
            "last_weight": last["weight"] if last else None,
            "last_reps": last["reps"] if last else None,
            "last_sets": last["sets"] if last else None,
        })
    return relevant


def get_log_context(conn, target_date=None):
    """What the logging screen needs to render itself: today's
    scheduled type/summary, plus which tracked exercises (if any) are
    worth prompting for. Returns None if nothing is scheduled for that
    date at all."""
    if target_date is None:
        target_date = date.today().isoformat()
    row = conn.execute(
        "SELECT * FROM sessions WHERE date = ?", (target_date,)
    ).fetchone()
    if row is None:
        return None
    return {
        "date": target_date,
        "type": row["type"],
        "status": row["status"],
        "planned_summary": row["planned_summary"],
        "relevant_exercises": _relevant_exercises(conn, row["type"]),
    }


def _merge_lifts(manual, parsed):
    """A manually typed number wins over anything the parser also
    found for the same exercise -- it's a deliberate, precise entry;
    the parsed one is a best-effort backstop for whatever the athlete
    only said, not typed. Matched by exercise name, case-insensitive."""
    manual = manual or []
    manual_names = {l["exercise_name"].strip().lower() for l in manual}
    extra = [
        l for l in (parsed or [])
        if l.get("exercise_name", "").strip().lower() not in manual_names
    ]
    return manual + extra


def save_log(conn, target_date, status, notes, lifts):
    """Record what actually happened. Updates the existing sessions
    row (there should always be exactly one per date, from the week's
    plan) rather than inserting a second row for the same day.

    `lifts` is whatever the athlete typed into the per-exercise number
    fields, if anything -- optional, per CLAUDE.md's logging
    philosophy (voice/summary first, structured entry is a fallback).
    `notes` (typed or voice-dictated) is also run through
    lift_parser.py for any numbers mentioned there instead; the two
    are merged, manual entries taking precedence on a name clash."""
    existing = conn.execute(
        "SELECT id FROM sessions WHERE date = ?", (target_date,)
    ).fetchone()
    if existing is None:
        raise ValueError(f"No session scheduled for {target_date}")

    conn.execute(
        "UPDATE sessions SET status = ?, actual_summary = ?, "
        "source = 'manual' WHERE id = ?",
        (status, notes, existing["id"]),
    )

    all_lifts = _merge_lifts(lifts, lift_parser.parse_lifts(conn, notes))
    for lift in all_lifts:
        conn.execute(
            "INSERT INTO lifts (date, exercise_name, weight, reps, sets, note) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            (target_date, lift["exercise_name"], lift.get("weight"),
             lift.get("reps"), lift.get("sets"), lift.get("note")),
        )
    conn.commit()

    row = conn.execute(
        "SELECT * FROM sessions WHERE id = ?", (existing["id"],)
    ).fetchone()
    return {
        "date": row["date"],
        "type": row["type"],
        "status": row["status"],
        "actual_summary": row["actual_summary"],
        "lifts_recorded": all_lifts,
    }

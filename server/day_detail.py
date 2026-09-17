"""
day_detail.py — everything for one calendar day, for Week view's
tap-to-open detail: the session (planned vs actual), any lift numbers
logged that date, that day's check-in, and any note the coach attached
to that day from a chat mention (see coach.py's _attach_session_note()
and session_note_parser.py -- that's what "chat_note" below actually
is: sessions.notes, a real column nothing wrote to before that pass).

No new tables, no new joins nobody's done before -- this is the same
three tables (sessions, lifts, checkins) every other screen already
reads, just all three keyed to one date instead of a range.
"""

import json


def get_day_detail(conn, date_iso):
    """None if there's truly nothing on record for this date at all
    (no session, no logged lifts, no check-in) -- lets the caller show
    "nothing here" instead of an empty-but-present detail screen."""
    session = conn.execute(
        "SELECT * FROM sessions WHERE date = ?", (date_iso,)
    ).fetchone()
    lifts = conn.execute(
        "SELECT exercise_name, weight, reps, sets, note FROM lifts "
        "WHERE date = ? ORDER BY id ASC",
        (date_iso,),
    ).fetchall()
    checkin = conn.execute(
        "SELECT sleep, energy, soreness_json, pain_flag, note FROM checkins "
        "WHERE date = ?",
        (date_iso,),
    ).fetchone()

    if session is None and not lifts and checkin is None:
        return None

    return {
        "date": date_iso,
        "type": session["type"] if session else None,
        "status": session["status"] if session else None,
        "planned_summary": session["planned_summary"] if session else None,
        "actual_summary": session["actual_summary"] if session else None,
        "duration_min": session["duration_min"] if session else None,
        "rpe": session["rpe"] if session else None,
        "chat_note": session["notes"] if session else None,
        "lifts": [
            {
                "exercise_name": row["exercise_name"],
                "weight": row["weight"],
                "reps": row["reps"],
                "sets": row["sets"],
                "note": row["note"],
            }
            for row in lifts
        ],
        "checkin": (
            {
                "sleep": checkin["sleep"],
                "energy": checkin["energy"],
                "soreness": json.loads(checkin["soreness_json"] or "{}"),
                "pain_flag": bool(checkin["pain_flag"]),
                "note": checkin["note"],
            }
            if checkin
            else None
        ),
    }

"""
session_corrections.py — when a message says what actually happened on
earlier days, write it to the `sessions` table.

This is the path that was missing. The planner call reads a message
like "Monday push, Tuesday the pool, Wednesday pull instead of rest"
and quite correctly uses it for today's decision, but CLAUDE.md's
decision schema has nowhere to record five earlier days, so nothing
was ever saved: Week and Progress stayed empty, and the correction had
to be repeated every day. A bigger prompt can't fix that -- there was
no code that wrote the rows.

So: one small extraction call (same shape as lift_parser.py and
session_note_parser.py, prompt in prompts/session-corrections.md),
then every row it returns is checked here and applied in plain SQL.
What was actually written comes back to the caller, which is what lets
the coach's reply name the days instead of claiming something
unverifiable. Anything rejected is reported too -- a correction that
quietly vanishes is the bug this file exists to fix.

No eighth table: this writes to `sessions`, the same table logging and
planning already use.
"""

from datetime import date, timedelta
from pathlib import Path

import planner
from providers import PlannerError

PROMPT_PATH = Path(__file__).parent.parent / "prompts" / "session-corrections.md"

# CLAUDE.md's session types, and the sessions.type CHECK constraint.
SESSION_TYPES = ("push", "pull", "legs", "ride", "run", "swim",
                 "intervals", "rest")

# A correction describes something that already happened, so
# 'planned' -- valid in the table, for a future day -- is not accepted
# here.
CORRECTION_STATUSES = ("done", "partial", "skipped", "unplanned")

# How far back a correction may reach. Two weeks is what the briefing
# shows and what someone can actually remember day by day; a date
# outside it is far likelier to be a mis-parse than a real memory.
WINDOW_DAYS = 14

SCHEMA = {
    "type": "object",
    "properties": {
        "corrections": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "date": {"type": "string"},
                    "type": {"type": "string", "enum": list(SESSION_TYPES)},
                    "status": {"type": "string", "enum": list(CORRECTION_STATUSES)},
                    "summary": {"type": "string"},
                    "duration_min": {"type": ["integer", "null"]},
                },
                "required": ["date", "type", "status", "summary", "duration_min"],
            },
        }
    },
    "required": ["corrections"],
}


def _recent_days(conn, today):
    """The window the model may correct, each with whatever is already
    on record. Given as explicit dates *with* weekday names so day
    names never have to be worked out from arithmetic."""
    rows = {
        r["date"]: r
        for r in conn.execute(
            "SELECT date, type, status, actual_summary FROM sessions "
            "WHERE date >= ? AND date <= ? ORDER BY date",
            ((today - timedelta(days=WINDOW_DAYS)).isoformat(), today.isoformat()),
        ).fetchall()
    }
    lines = []
    for offset in range(WINDOW_DAYS, -1, -1):
        day = today - timedelta(days=offset)
        iso = day.isoformat()
        label = f"{iso} ({day.strftime('%a')})"
        row = rows.get(iso)
        if row is None:
            lines.append(f"{label}: nothing on record")
        else:
            detail = row["actual_summary"] or row["type"]
            lines.append(f"{label}: {row['type']} / {row['status']} — {detail}")
    return lines


def parse_corrections(conn, message, today_iso):
    """Ask the model which past days this message states something
    definite about. Best-effort: returns [] on any failure, exactly
    like lift_parser.py, so this never takes the turn down with it."""
    message = (message or "").strip()
    if not message:
        return []

    today = date.fromisoformat(today_iso)
    user_content = (
        f"TODAY: {today_iso} ({today.strftime('%A')})\n\n"
        f"RECENT DAYS (what's on record now):\n" + "\n".join(_recent_days(conn, today))
        + f"\n\nMESSAGE:\n{message}"
    )

    try:
        provider = planner.active_provider()
        result = provider.get_structured(PROMPT_PATH.read_text(), user_content, SCHEMA)
    except PlannerError:
        return []
    corrections = result.get("corrections")
    return corrections if isinstance(corrections, list) else []


def _check(correction, today):
    """Either a clean correction or a reason it can't be applied. The
    model is told the rules; this enforces them, because a bad row
    here becomes part of the athlete's training history and feeds
    every future briefing."""
    if not isinstance(correction, dict):
        return None, "not a correction"

    raw_date = (correction.get("date") or "").strip()
    try:
        when = date.fromisoformat(raw_date)
    except ValueError:
        return None, f"unreadable date {raw_date!r}"
    if when > today:
        return None, f"{raw_date} is in the future"
    if when < today - timedelta(days=WINDOW_DAYS):
        return None, f"{raw_date} is more than {WINDOW_DAYS} days ago"

    session_type = (correction.get("type") or "").strip().lower()
    if session_type not in SESSION_TYPES:
        return None, f"unknown session type {session_type!r}"

    status = (correction.get("status") or "").strip().lower()
    if status not in CORRECTION_STATUSES:
        return None, f"unknown status {status!r}"

    duration = correction.get("duration_min")
    if duration is not None:
        try:
            duration = int(duration)
        except (TypeError, ValueError):
            duration = None
        else:
            # A session measured in days, or in negative time, is a
            # parse gone wrong rather than a real number.
            if not 0 < duration <= 600:
                duration = None

    return {
        "date": raw_date,
        "type": session_type,
        "status": status,
        "summary": (correction.get("summary") or "").strip() or None,
        "duration_min": duration,
    }, None


def apply_corrections(conn, corrections, today_iso):
    """Write the valid corrections to `sessions` and return
    ({"applied": [...], "rejected": [...]}).

    One row per date: a day already on record is updated in place --
    the whole point is to replace what the plan said with what
    happened -- and a day with nothing on record gets a new row. Both
    lists come back so the reply can name what was saved and admit
    what wasn't.
    """
    today = date.fromisoformat(today_iso)
    applied, rejected = [], []
    seen = {}

    for correction in corrections or []:
        clean, problem = _check(correction, today)
        if clean is None:
            rejected.append(problem)
            continue
        # Last mention of a date wins, so one message can't produce two
        # rows for one day.
        seen[clean["date"]] = clean

    for clean in sorted(seen.values(), key=lambda c: c["date"]):
        row = conn.execute(
            "SELECT id FROM sessions WHERE date = ? ORDER BY id LIMIT 1",
            (clean["date"],),
        ).fetchone()
        if row is None:
            conn.execute(
                "INSERT INTO sessions "
                "(date, type, status, actual_summary, duration_min, source) "
                "VALUES (?, ?, ?, ?, ?, 'manual')",
                (clean["date"], clean["type"], clean["status"],
                 clean["summary"], clean["duration_min"]),
            )
        else:
            # duration_min only when one was given: a correction that
            # says nothing about length shouldn't erase a length that
            # was already recorded.
            conn.execute(
                "UPDATE sessions SET type = ?, status = ?, actual_summary = ?, "
                "duration_min = COALESCE(?, duration_min), source = 'manual' "
                "WHERE id = ?",
                (clean["type"], clean["status"], clean["summary"],
                 clean["duration_min"], row["id"]),
            )
        applied.append(clean)

    if applied:
        conn.commit()
    return {"applied": applied, "rejected": rejected}


def update_sessions_from_message(conn, message, today_iso):
    """The whole path in one call, for coach.py: extract, check, write.
    Returns the same dict as apply_corrections()."""
    corrections = parse_corrections(conn, message, today_iso)
    if not corrections:
        return {"applied": [], "rejected": []}
    return apply_corrections(conn, corrections, today_iso)

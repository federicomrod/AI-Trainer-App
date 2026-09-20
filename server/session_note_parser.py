"""
session_note_parser.py — when a chat message references a specific
*other* day's session by name ("Tuesday's run", "the pull day on the
9th"), pulls out which date and what was said about it, so the note
attaches to that session's own `notes` column instead of only ever
living in chat history. See prompts/session-note-parser.md for the gap
this closes and why it's a separate small model call, same shape as
lift_parser.py.
"""

from datetime import date
from pathlib import Path

import planner
import session_corrections
from providers import PlannerError

PROMPT_PATH = Path(__file__).parent.parent / "prompts" / "session-note-parser.md"

SCHEMA = {
    "type": "object",
    "properties": {
        "date": {"type": ["string", "null"]},
        "note": {"type": ["string", "null"]},
    },
    "required": ["date", "note"],
}

RECENT_SESSIONS_LIMIT = 14


def parse_session_note(conn, message, today_iso):
    """Best-effort: returns None on any failure or when the message
    doesn't clearly reference a specific other dated session, same as
    lift_parser.py returning an empty list -- never blocks the turn
    itself over this."""
    message = (message or "").strip()
    if not message:
        return None

    # Today included. It used to be `date < today`, which meant a
    # remark about today's session had nowhere correct to land and the
    # nearest older day of the same type was the only candidate --
    # exactly the mis-attribution this parser is supposed to avoid.
    rows = conn.execute(
        "SELECT date, type FROM sessions WHERE date <= ? ORDER BY date DESC LIMIT ?",
        (today_iso, RECENT_SESSIONS_LIMIT),
    ).fetchall()
    if not rows:
        return None

    context = "\n".join(f"{r['date']}: {r['type']}" for r in rows)
    user_content = f"TODAY: {today_iso}\n\nRECENT SESSIONS:\n{context}\n\nMESSAGE:\n{message}"

    try:
        provider = planner.active_provider()
        result = provider.get_structured(PROMPT_PATH.read_text(), user_content, SCHEMA)
    except PlannerError:
        return None

    found_date, note = result.get("date"), result.get("note")
    if found_date and note:
        # Same rule as session_corrections: the athlete's own "today"
        # or "yesterday" outranks whatever date came back.
        found_date, _ = session_corrections.anchor_date(
            f"{message} {note}", found_date, date.fromisoformat(today_iso)
        )
    known_dates = {r["date"] for r in rows}
    if not found_date or not note or found_date not in known_dates:
        return None
    return {"date": found_date, "note": note}

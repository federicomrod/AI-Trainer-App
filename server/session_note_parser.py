"""
session_note_parser.py — when a chat message references a specific
*other* day's session by name ("Tuesday's run", "the pull day on the
9th"), pulls out which date and what was said about it, so the note
attaches to that session's own `notes` column instead of only ever
living in chat history. See prompts/session-note-parser.md for the gap
this closes and why it's a separate small model call, same shape as
lift_parser.py.
"""

from pathlib import Path

import planner
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

    rows = conn.execute(
        "SELECT date, type FROM sessions WHERE date < ? ORDER BY date DESC LIMIT ?",
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

    date, note = result.get("date"), result.get("note")
    known_dates = {r["date"] for r in rows}
    if not date or not note or date not in known_dates:
        return None
    return {"date": date, "note": note}

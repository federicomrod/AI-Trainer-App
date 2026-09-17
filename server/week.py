"""
week.py — the data behind the Week view: every session in the current
calendar week, each tagged with whether a coaching decision moved it
from what was originally scheduled, and why.

Sessions rows are never rewritten when a decision changes the plan
(see coach.py -- only status/actual_summary/notes get updated, by
log_session.py, when the athlete logs what really happened). So
"moved" isn't a column anywhere; it's reconstructed the same way
briefing.py's "recent decisions" section does it -- by scanning
assistant messages for plan_diff entries -- just shaped for a calendar
instead of prose.
"""

import json
from datetime import date, timedelta

WEEKDAY = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]


def get_week(conn, today=None):
    if today is None:
        today = date.today()
    week_start = today - timedelta(days=today.weekday())
    week_end = week_start + timedelta(days=6)

    rows = conn.execute(
        "SELECT * FROM sessions WHERE date >= ? AND date <= ? ORDER BY date ASC",
        (week_start.isoformat(), week_end.isoformat()),
    ).fetchall()

    diffs_by_date = _collect_diffs(conn, week_start, week_end)

    days = []
    for r in rows:
        diff = diffs_by_date.get(r["date"])
        days.append({
            "date": r["date"],
            "weekday": WEEKDAY[date.fromisoformat(r["date"]).weekday()],
            "is_today": r["date"] == today.isoformat(),
            "type": r["type"],
            "status": r["status"],
            "planned_summary": r["planned_summary"],
            "actual_summary": r["actual_summary"],
            "duration_min": r["duration_min"],
            "moved_to": diff["to"] if diff else None,
            "moved_reason": diff["reason"] if diff else None,
        })
    return days


def _collect_diffs(conn, week_start, week_end):
    """The most recent plan_diff entry per date, scanning every
    assistant message rather than a fixed lookback window -- a
    decision made any time before this week should still show up
    against it. Later messages overwrite earlier ones for the same
    date, since a later decision supersedes an earlier one."""
    rows = conn.execute(
        "SELECT content FROM messages WHERE role = 'assistant' ORDER BY id ASC"
    ).fetchall()
    result = {}
    start_iso, end_iso = week_start.isoformat(), week_end.isoformat()
    for r in rows:
        try:
            decision = json.loads(r["content"])
        except (json.JSONDecodeError, TypeError):
            continue
        for change in decision.get("plan_diff") or []:
            d = change.get("date")
            if d and start_iso <= d <= end_iso:
                result[d] = {"to": change.get("to"), "reason": change.get("reason")}
    return result

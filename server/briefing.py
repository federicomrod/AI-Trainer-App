"""
briefing.py — turns the database into the plain-text briefing the coach
reads before making a decision.

This is deliberately just string-building: read some rows, format them
into readable lines, join them into sections. No cleverness. Per
CLAUDE.md, the briefing is where the quality of this whole project
lives — a good plain-text summary of a real training history is
something ChatGPT literally cannot produce, because it has no database.
Getting this right matters more than any prompt wording later.

Sections, in order, matching what CLAUDE.md requires the briefing to
contain: goals & priority, last 14 days, this week's plan, current
state (soreness/energy), tracked exercises, events, coach memory.
"""

import json
from datetime import date, timedelta

from db import get_connection

LOOKBACK_DAYS = 14
EVENT_WINDOW_PAST = 7
EVENT_WINDOW_FUTURE = 14
RECENT_LIFTS_PER_EXERCISE = 3
RECENT_DECISIONS_LIMIT = 5

WEEKDAY = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]


def _parse_date(s):
    return date.fromisoformat(s)


def _fmt_date(s):
    dt = _parse_date(s)
    return f"{s} ({WEEKDAY[dt.weekday()]})"


# ---------------------------------------------------------------------
# Section builders. Each one takes a connection (and sometimes `today`)
# and returns a block of text. build_briefing() below just concatenates
# them in order.
# ---------------------------------------------------------------------

def section_profile(conn):
    row = conn.execute("SELECT * FROM profile WHERE id = 1").fetchone()
    if row is None:
        return "PROFILE\n(no profile set up yet)\n"

    goals = json.loads(row["goals_json"])
    preferred = json.loads(row["preferred_exercises_json"] or "[]")
    disliked = json.loads(row["disliked_exercises_json"] or "[]")

    lines = ["PROFILE"]
    lines.append("Goals, in priority order:")
    for i, g in enumerate(goals, 1):
        lines.append(f"  {i}. {g}")
    lines.append(f"Availability: {row['weekly_availability']}")
    lines.append(f"Typical session length: {row['typical_session_length_min']} min")
    lines.append(f"Equipment: {row['equipment']}")
    if preferred:
        lines.append(f"Preferred exercises: {', '.join(preferred)}")
    if disliked:
        lines.append(f"Disliked/avoid: {', '.join(disliked)}")
    if row["injuries"]:
        lines.append(f"Injuries/limitations: {row['injuries']}")
    lines.append(f"Experience level: {row['experience_level']}")
    return "\n".join(lines)


def section_last_14_days(conn, today):
    since = (today - timedelta(days=LOOKBACK_DAYS)).isoformat()
    until = (today - timedelta(days=1)).isoformat()
    rows = conn.execute(
        "SELECT * FROM sessions WHERE date >= ? AND date <= ? "
        "ORDER BY date ASC",
        (since, until),
    ).fetchall()

    lines = [f"LAST {LOOKBACK_DAYS} DAYS (planned vs. actual)"]
    if not rows:
        lines.append("(no sessions logged)")
        return "\n".join(lines)

    for r in rows:
        head = f"{_fmt_date(r['date'])}  {r['type']:<9} {r['status']:<8}"
        if r["status"] == "planned":
            body = f"planned: {r['planned_summary']}"
        elif r["status"] == "skipped":
            body = f"planned: {r['planned_summary']} -> skipped"
            if r["notes"]:
                body += f" ({r['notes']})"
        else:
            body = f"actual: {r['actual_summary'] or '(rest day, nothing to log)'}"
            extras = []
            if r["duration_min"]:
                extras.append(f"{r['duration_min']} min")
            if r["rpe"]:
                extras.append(f"RPE {r['rpe']}")
            if extras:
                body += f"  [{', '.join(extras)}]"
            if r["notes"]:
                body += f"\n           note: {r['notes']}"
        lines.append(f"{head} {body}")
    return "\n".join(lines)


def section_this_week(conn, today):
    week_start = today - timedelta(days=today.weekday())  # Monday
    week_end = week_start + timedelta(days=6)              # Sunday
    rows = conn.execute(
        "SELECT * FROM sessions WHERE date >= ? AND date <= ? "
        "AND status = 'planned' ORDER BY date ASC",
        (week_start.isoformat(), week_end.isoformat()),
    ).fetchall()

    lines = [f"THIS WEEK'S PLAN ({week_start.isoformat()} to {week_end.isoformat()})"]
    if not rows:
        lines.append("(nothing planned)")
        return "\n".join(lines)
    for r in rows:
        marker = " <- today" if r["date"] == today.isoformat() else ""
        lines.append(f"{_fmt_date(r['date'])}  {r['type']:<9} {r['planned_summary']}{marker}")
    return "\n".join(lines)


def section_current_state(conn, today):
    row = conn.execute(
        "SELECT * FROM checkins WHERE date <= ? ORDER BY date DESC LIMIT 1",
        (today.isoformat(),),
    ).fetchone()

    lines = ["CURRENT STATE"]
    if row is None:
        lines.append("(no check-in logged)")
        return "\n".join(lines)

    soreness = json.loads(row["soreness_json"] or "{}")
    soreness_str = ", ".join(f"{region}={level}" for region, level in soreness.items()) or "none reported"
    lines.append(f"Most recent check-in: {_fmt_date(row['date'])}")
    lines.append(f"Sleep: {row['sleep']}   Energy: {row['energy']}/5")
    lines.append(f"Soreness: {soreness_str}")
    lines.append(f"Pain flag: {'YES' if row['pain_flag'] else 'no'}")
    if row["note"]:
        lines.append(f"Note: {row['note']}")
    return "\n".join(lines)


def section_tracked_exercises(conn, today):
    """Tracking is emergent: whatever has rows in `lifts` is tracked,
    listed by most-recently-logged first. No profile field to read, no
    cap — and an exercise that's gone quiet just quietly stops
    appearing near the top, which is exactly the point: the coach
    should notice it's stale by the date, not be told to chase it."""
    exercises = conn.execute(
        "SELECT exercise_name, MAX(date) AS last_date FROM lifts "
        "WHERE date <= ? GROUP BY exercise_name ORDER BY last_date DESC",
        (today.isoformat(),),
    ).fetchall()

    lines = ["TRACKED EXERCISES (emergent — anything with logged numbers; "
             "most recent first)"]
    if not exercises:
        lines.append("(nothing logged with real numbers yet)")
        return "\n".join(lines)

    for ex in exercises:
        name = ex["exercise_name"]
        rows = conn.execute(
            "SELECT date, weight, reps, sets, note FROM lifts "
            "WHERE exercise_name = ? AND date <= ? "
            "ORDER BY date DESC LIMIT ?",
            (name, today.isoformat(), RECENT_LIFTS_PER_EXERCISE),
        ).fetchall()
        lines.append(f"{name}:")
        for r in rows:
            parts = []
            if r["weight"] is not None:
                w = r["weight"]
                w_str = str(int(w)) if w == int(w) else str(w)
                parts.append(f"{w_str}kg")
            if r["sets"] is not None and r["reps"] is not None:
                parts.append(f"{r['sets']} x {r['reps']}")
            elif r["reps"] is not None:
                parts.append(f"x{r['reps']}")
            detail = ", ".join(parts)
            if r["note"]:
                detail += f" ({r['note']})"
            lines.append(f"  {r['date']}: {detail}")
    return "\n".join(lines)


def section_recent_decisions(conn, today):
    """Plan changes the coach already made, and why — pulled from
    assistant messages, whose content IS the decision JSON (that's the
    single source of truth per the core loop: decide, validate, save,
    render). This exists so the coach doesn't contradict a call it
    already made a few days ago."""
    since = (today - timedelta(days=LOOKBACK_DAYS)).isoformat()
    rows = conn.execute(
        "SELECT content FROM messages WHERE role = 'assistant' "
        "AND date(timestamp) >= ? ORDER BY timestamp DESC",
        (since,),
    ).fetchall()

    diffs = []
    for r in rows:
        try:
            decision = json.loads(r["content"])
        except (json.JSONDecodeError, TypeError):
            continue
        for change in decision.get("plan_diff") or []:
            diffs.append(change)
        if len(diffs) >= RECENT_DECISIONS_LIMIT:
            break

    lines = ["RECENT DECISIONS (plan changes already made, and why)"]
    if not diffs:
        lines.append("(no recent plan changes)")
        return "\n".join(lines)
    for change in diffs[:RECENT_DECISIONS_LIMIT]:
        lines.append(f"{change.get('date')}: {change.get('from')} -> "
                      f"{change.get('to')} — {change.get('reason')}")
    return "\n".join(lines)


def section_events(conn, today):
    since = (today - timedelta(days=EVENT_WINDOW_PAST)).isoformat()
    until = (today + timedelta(days=EVENT_WINDOW_FUTURE)).isoformat()
    rows = conn.execute(
        "SELECT * FROM events WHERE end_date >= ? AND start_date <= ? "
        "ORDER BY start_date ASC",
        (since, until),
    ).fetchall()

    lines = ["EVENTS (recent and upcoming)"]
    if not rows:
        lines.append("(none)")
        return "\n".join(lines)
    for r in rows:
        span = r["start_date"] if r["start_date"] == r["end_date"] \
            else f"{r['start_date']} to {r['end_date']}"
        lines.append(f"{span}  [{r['type']}]  {r['note']}")
        if r["effect_on_availability"]:
            lines.append(f"  effect: {r['effect_on_availability']}")
    return "\n".join(lines)


def section_memory(conn):
    rows = conn.execute("SELECT * FROM memory ORDER BY date_added ASC").fetchall()
    lines = ["COACH MEMORY"]
    if not rows:
        lines.append("(nothing learned yet)")
        return "\n".join(lines)
    for r in rows:
        lines.append(f"- {r['text']} (added {r['date_added']})")
    return "\n".join(lines)


def build_briefing(conn, today=None):
    """Assemble the full plain-text briefing. `today` defaults to the
    real calendar date; pass a date explicitly to test other days."""
    if today is None:
        today = date.today()

    sections = [
        f"BRIEFING — {_fmt_date(today.isoformat())}",
        section_profile(conn),
        section_last_14_days(conn, today),
        section_this_week(conn, today),
        section_recent_decisions(conn, today),
        section_current_state(conn, today),
        section_tracked_exercises(conn, today),
        section_events(conn, today),
        section_memory(conn),
    ]
    return "\n\n".join(sections)


if __name__ == "__main__":
    conn = get_connection()
    print(build_briefing(conn))

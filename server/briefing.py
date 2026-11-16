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


def section_today(conn, today):
    """What is true about *today*, stated once, at the top.

    This section did not exist, and its absence was the root of a
    whole family of problems. LAST 14 DAYS stops at yesterday and
    THIS WEEK'S PLAN lists only `planned` rows, so a session already
    logged today appeared nowhere at all: the coach could only propose
    one, and would cheerfully re-plan a day the athlete had already
    trained. With nothing here to anchor to, "today" in a message had
    no date attached to it either, and the nearest same-type day in
    the last-14-days window was the only thing it could match.

    So: today's real date, what's on record for it, and the numbers
    logged against it -- spelled out rather than left to be inferred
    from a list of other days.
    """
    iso = today.isoformat()
    lines = [f"TODAY — {_fmt_date(iso)}"]
    lines.append(
        f'Any mention of "today", "this morning", "just did", or no date at '
        f"all means {iso}, and never another day that happens to be the same "
        f"kind of session."
    )

    row = conn.execute(
        "SELECT * FROM sessions WHERE date = ? ORDER BY id LIMIT 1", (iso,)
    ).fetchone()
    if row is None:
        lines.append("Nothing on record for today yet — nothing planned, "
                     "nothing logged.")
    elif row["status"] in ("done", "partial", "unplanned"):
        summary = row["actual_summary"] or "(no detail given)"
        extras = []
        if row["duration_min"]:
            extras.append(f"{row['duration_min']} min")
        if row["rpe"]:
            extras.append(f"RPE {row['rpe']}")
        suffix = f"  [{', '.join(extras)}]" if extras else ""
        lines.append(
            f"ALREADY TRAINED TODAY — logged as {row['status']}: "
            f"{row['type']} — {summary}{suffix}"
        )
        lines.append(
            "Today is finished. You are reviewing it with them, not "
            "planning it. Do not propose or re-explain today's session as "
            "something still to come."
        )
        if row["notes"]:
            lines.append(f"Note on today: {row['notes']}")
    elif row["status"] == "skipped":
        lines.append(f"Today was planned as {row['type']} and is marked "
                     f"skipped: {row['planned_summary'] or '(no detail)'}")
    else:
        lines.append(f"Planned for today: {row['type']} — "
                     f"{row['planned_summary'] or '(no detail yet)'} "
                     f"(not logged yet)")

    lifts = conn.execute(
        "SELECT exercise_name, weight, reps, sets, note FROM lifts "
        "WHERE date = ? ORDER BY id", (iso,)
    ).fetchall()
    if lifts:
        lines.append("Numbers already logged today (do not ask for these "
                     "again):")
        for lift in lifts:
            lines.append(f"  {_fmt_lift(lift)}")
    return "\n".join(lines)


def _fmt_lift(row):
    """"Back Squat 100kg 3 x 5 (felt heavy)" from a lifts row."""
    parts = []
    if row["weight"] is not None:
        weight = row["weight"]
        parts.append(f"{int(weight) if weight == int(weight) else weight}kg")
    if row["sets"] is not None and row["reps"] is not None:
        parts.append(f"{row['sets']} x {row['reps']}")
    elif row["reps"] is not None:
        parts.append(f"x{row['reps']}")
    detail = " ".join(parts)
    text = f"{row['exercise_name']} {detail}".strip()
    if row["note"]:
        text += f" ({row['note']})"
    return text


def section_last_14_days(conn, today):
    since = (today - timedelta(days=LOOKBACK_DAYS)).isoformat()
    until = (today - timedelta(days=1)).isoformat()
    rows = conn.execute(
        "SELECT * FROM sessions WHERE date >= ? AND date <= ? "
        "ORDER BY date ASC",
        (since, until),
    ).fetchall()

    lines = [f"LAST {LOOKBACK_DAYS} DAYS (planned vs. actual; up to "
             f"yesterday — today is in its own section above)"]
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


LIFTING_TYPES = ("push", "pull", "legs")
DONE_STATUSES = ("done", "partial", "unplanned")
DETAIL_TYPES = ("push", "pull", "legs", "ride", "intervals", "run", "swim")


def section_last_of_each_type(conn, today):
    """The most recent session of each type, in full, however long ago.

    LAST 14 DAYS shows what happened recently but a rolling Push / Pull
    / Legs athlete asks "what did I do last pull day?" and expects the
    exercises, not a date. Also states the one fact a rolling split
    runs on -- which lifting day was completed last -- and leaves what
    comes next to the coach: it knows the athlete's own rules.
    """
    until = (today - timedelta(days=1)).isoformat()
    lines = ["LAST SESSION OF EACH TYPE (full detail, completed sessions "
             "only; use to keep progression recognisable)"]
    found = False
    last_lifting = None
    for kind in DETAIL_TYPES:
        row = conn.execute(
            "SELECT * FROM sessions WHERE type = ? AND date <= ? AND status IN "
            "('done', 'partial', 'unplanned') ORDER BY date DESC LIMIT 1",
            (kind, until),
        ).fetchone()
        if row is None:
            continue
        found = True
        if kind in LIFTING_TYPES and (last_lifting is None
                                      or row["date"] > last_lifting["date"]):
            last_lifting = row
        extras = []
        if row["duration_min"]:
            extras.append(f"{row['duration_min']} min")
        if row["rpe"]:
            extras.append(f"RPE {row['rpe']}")
        suffix = f"  [{', '.join(extras)}]" if extras else ""
        lines.append(f"{kind} — {_fmt_date(row['date'])} ({row['status']}): "
                     f"{row['actual_summary'] or '(no detail given)'}{suffix}")
        if row["notes"]:
            lines.append(f"  note: {row['notes']}")
        lifts = conn.execute(
            "SELECT exercise_name, weight, reps, sets, note FROM lifts "
            "WHERE date = ? ORDER BY id", (row["date"],)
        ).fetchall()
        for lift in lifts:
            lines.append(f"  logged: {_fmt_lift(lift)}")
    if not found:
        lines.append("(no completed sessions on record)")
    if last_lifting is not None:
        lines.append(f"Last completed lifting day: {last_lifting['type']} on "
                     f"{_fmt_date(last_lifting['date'])}.")
    return "\n".join(lines)


def _kg(value):
    return f"{int(value) if value == int(value) else value} kg"


def _lift_label(row):
    """"80 kg x 3 sets" / "80 kg x 8 reps" from a lifts row, whichever
    parts exist."""
    parts = []
    if row["weight"] is not None:
        parts.append(_kg(row["weight"]))
    if row["sets"] is not None and row["reps"] is not None:
        parts.append(f"{row['sets']} x {row['reps']}")
    elif row["sets"] is not None:
        parts.append(f"{row['sets']} sets")
    elif row["reps"] is not None:
        parts.append(f"x{row['reps']}")
    return " ".join(parts) or "(no numbers)"


def progress_for_exercise(rows):
    """One line of arithmetic about one exercise, done in code so the
    coach quotes changes instead of inventing them. `rows` are lifts
    rows newest first, one per date. Returns None with fewer than one
    row."""
    if not rows:
        return None
    latest = rows[0]
    line = f"{latest['exercise_name']}: {_lift_label(latest)} on {latest['date']}"
    if len(rows) == 1:
        return line + " (first number logged, nothing to compare yet)"
    previous = rows[1]
    line += f"; previous {_lift_label(previous)} on {previous['date']}"
    if latest["weight"] is not None and previous["weight"] is not None:
        change = round(latest["weight"] - previous["weight"], 2)
        if change == 0:
            line += " (same weight"
        else:
            line += f" ({'+' if change > 0 else ''}{_kg(change)}"
        if latest["reps"] is not None and previous["reps"] is not None:
            reps = latest["reps"] - previous["reps"]
            if reps:
                line += f", {'+' if reps > 0 else ''}{reps} reps"
        line += ")"
    first = rows[-1]
    if len(rows) > 2 and latest["weight"] is not None and first["weight"] is not None:
        total = round(latest["weight"] - first["weight"], 2)
        line += (f". Since first logged ({first['date']}, {_kg(first['weight'])}): "
                 f"{'+' if total >= 0 else ''}{_kg(total)}")
    return line


def section_progress(conn, today):
    """Computed changes, so a debrief can say "up 5 kg" because it is
    true. Covers tracked lifts (latest vs previous vs first) and how
    much training actually happened in each of the last four weeks."""
    iso = today.isoformat()
    names = conn.execute(
        "SELECT exercise_name, MAX(date) AS last_date FROM lifts "
        "WHERE date <= ? GROUP BY exercise_name ORDER BY last_date DESC",
        (iso,),
    ).fetchall()

    lines = ["PROGRESS (computed in code from logged numbers; quote these, "
             "never invent a change that is not listed)"]
    if not names:
        lines.append("(no lifts logged with numbers, so there are no "
                     "changes to quote)")
    for n in names:
        rows = conn.execute(
            "SELECT * FROM lifts WHERE exercise_name = ? AND date <= ? "
            "ORDER BY date DESC, id DESC", (n["exercise_name"], iso),
        ).fetchall()
        per_date, seen = [], set()
        for r in rows:
            if r["date"] not in seen:
                seen.add(r["date"])
                per_date.append(r)
        text = progress_for_exercise(per_date)
        if text:
            lines.append(f"- {text}")

    lines.append("Training load by week (completed sessions only):")
    week_start = today - timedelta(days=today.weekday())
    for back in range(4, -1, -1):
        start = week_start - timedelta(days=7 * back)
        end = start + timedelta(days=6)
        rows = conn.execute(
            "SELECT type, duration_min FROM sessions WHERE date >= ? AND date <= ? "
            "AND date <= ? AND status IN ('done','partial','unplanned') "
            "AND type != 'rest'", (start.isoformat(), end.isoformat(), iso),
        ).fetchall()
        lifts = sum(1 for r in rows if r["type"] in LIFTING_TYPES)
        minutes = sum(r["duration_min"] or 0 for r in rows)
        label = "this week so far" if back == 0 else f"week of {start.isoformat()}"
        lines.append(f"  {label}: {len(rows)} sessions ({lifts} lifting, "
                     f"{len(rows) - lifts} other), {minutes} min where durations "
                     f"were logged")
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
        section_today(conn, today),
        section_profile(conn),
        section_last_14_days(conn, today),
        section_last_of_each_type(conn, today),
        section_progress(conn, today),
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

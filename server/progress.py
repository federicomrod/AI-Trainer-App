"""
progress.py — real trend data for the Progress view, straight out of
lifts and sessions. No scores, no streaks, no invented metrics
(CLAUDE.md's non-goals rule out gamification and "a readiness score
presented as physiological fact" -- the same spirit applies here): just
what's actually in the database, shaped for a couple of plain charts.
"""

from datetime import date, timedelta

WEEKS_OF_HISTORY = 8


def get_progress(conn, today=None):
    if today is None:
        today = date.today()
    return {
        "lifts": _lift_series(conn),
        "weekly_sessions": _weekly_session_counts(conn, today),
        "stats": _stats(conn, today),
    }


def _stats(conn, today):
    """Emergent KPIs -- the same principle as tracked exercises: a
    metric only appears once there's a real logged number behind it,
    nothing computed or estimated. No pace-at-a-distance metric here:
    the schema has no distance/pace field anywhere (sessions only has
    duration_min), so there's no real data to compute it from yet --
    that's not an oversight, it's the same rule applied honestly."""
    return {
        "lift_prs": _lift_prs(conn),
        "longest_ride_min": _longest_duration(conn, "ride"),
        "longest_swim_min": _longest_duration(conn, "swim"),
        "sessions_this_week": _sessions_this_week(conn, today),
    }


def _lift_prs(conn):
    """Max weight ever logged per tracked exercise. Emergent, same as
    everywhere else -- an exercise only appears once it has a real
    weight logged for it."""
    rows = conn.execute(
        "SELECT exercise_name, MAX(weight) AS max_weight FROM lifts "
        "WHERE weight IS NOT NULL GROUP BY exercise_name "
        "ORDER BY exercise_name ASC"
    ).fetchall()
    return [
        {"exercise_name": r["exercise_name"], "max_weight": r["max_weight"]}
        for r in rows
    ]


def _longest_duration(conn, session_type):
    """Longest single completed session of this type, by logged
    duration. None (and so hidden client-side) until at least one such
    session has a real duration logged."""
    row = conn.execute(
        "SELECT MAX(duration_min) AS max_duration FROM sessions "
        "WHERE type = ? AND status IN ('done', 'partial') "
        "AND duration_min IS NOT NULL",
        (session_type,),
    ).fetchone()
    return row["max_duration"] if row else None


def _sessions_this_week(conn, today):
    """Plain count of completed sessions in the current Mon-Sun week --
    not a streak, nothing scored, just today's number from the same
    query _weekly_session_counts() already runs for the chart."""
    week_start = today - timedelta(days=today.weekday())
    week_end = week_start + timedelta(days=6)
    row = conn.execute(
        "SELECT COUNT(*) AS n FROM sessions WHERE date >= ? AND date <= ? "
        "AND status IN ('done', 'partial')",
        (week_start.isoformat(), week_end.isoformat()),
    ).fetchone()
    return row["n"]


def _lift_series(conn):
    """Every emergent tracked exercise's full weight-over-time series,
    in chronological order. Same idea as briefing.py's TRACKED
    EXERCISES section -- just shaped as a full list for a chart
    instead of the most recent few lines of text."""
    names = conn.execute(
        "SELECT DISTINCT exercise_name FROM lifts ORDER BY exercise_name"
    ).fetchall()

    series = {}
    for row in names:
        name = row["exercise_name"]
        points = conn.execute(
            "SELECT date, weight FROM lifts WHERE exercise_name = ? "
            "AND weight IS NOT NULL ORDER BY date ASC",
            (name,),
        ).fetchall()
        series[name] = [{"date": p["date"], "weight": p["weight"]} for p in points]
    return series


def _weekly_session_counts(conn, today):
    """Completed (done/partial) sessions per Mon-Sun week, for the
    last WEEKS_OF_HISTORY weeks including the current one in
    progress. A plain count -- not a streak, not scored."""
    this_week_start = today - timedelta(days=today.weekday())
    counts = []
    for i in range(WEEKS_OF_HISTORY - 1, -1, -1):
        week_start = this_week_start - timedelta(weeks=i)
        week_end = week_start + timedelta(days=6)
        row = conn.execute(
            "SELECT COUNT(*) AS n FROM sessions WHERE date >= ? AND date <= ? "
            "AND status IN ('done', 'partial')",
            (week_start.isoformat(), week_end.isoformat()),
        ).fetchone()
        counts.append({"week_start": week_start.isoformat(), "count": row["n"]})
    return counts

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
    }


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

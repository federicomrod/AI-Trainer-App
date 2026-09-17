"""
healthkit_import.py -- turns HealthKit workouts into rows in
`sessions`. CLAUDE.md: HealthKit is read-only and is the one
integration that covers most watches, since Garmin and Whoop write
into HealthKit rather than exposing an API this app could call
directly.

Only workout types iOS reports unambiguously as one of CLAUDE.md's
session types are imported at all (run/ride/swim/intervals) --
strength workouts are skipped rather than guessed into push/pull/legs,
since Apple Health doesn't distinguish those and getting it wrong
would misrepresent what actually happened that day.

A date that already has a sessions row -- planned, or already logged
some other way -- is never touched. CLAUDE.md: "never silently merge
conflicting sources, keep both, use the right one for the question."
This table has one row per session, and the existing row is whatever
the plan or the athlete's own logging already said; importing only
fills genuine gaps (a ride or run that happened with nothing planned
that day) rather than adjudicating a conflict.
"""

HK_TYPE_MAP = {
    "running": "run",
    "cycling": "ride",
    "swimming": "swim",
    "highIntensityIntervalTraining": "intervals",
}


def import_workouts(conn, workouts):
    imported = 0
    skipped = 0
    for w in workouts:
        session_type = HK_TYPE_MAP.get(w["hk_type"])
        if session_type is None:
            skipped += 1
            continue

        existing = conn.execute(
            "SELECT id FROM sessions WHERE date = ?", (w["date"],)
        ).fetchone()
        if existing is not None:
            skipped += 1
            continue

        conn.execute(
            "INSERT INTO sessions "
            "(date, type, status, actual_summary, duration_min, source) "
            "VALUES (?, ?, 'unplanned', ?, ?, 'healthkit')",
            (w["date"], session_type, w.get("summary"), w.get("duration_min")),
        )
        imported += 1

    conn.commit()
    return {"imported": imported, "skipped": skipped}

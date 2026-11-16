"""
test_progress.py -- offline check (no model, no cost) that the
PROGRESS section does its arithmetic right.

    python3 test_progress.py
"""

import os
import tempfile
from datetime import date

tmp = tempfile.mkdtemp()
os.environ["HYBRID_COACH_DB_PATH"] = os.path.join(tmp, "t.db")

import briefing  # noqa: E402
import db  # noqa: E402

conn = db.get_connection()
db.init_db(conn)
today = date(2026, 11, 16)
for d, name, w, reps, sets in [
    ("2026-10-04", "Neutral pulldown", 60, 8, 3),
    ("2026-11-01", "Neutral pulldown", 70, 8, 3),
    ("2026-11-08", "Neutral pulldown", 80, 8, 3),
    ("2026-11-08", "Bench press", 90, 6, 3),
    ("2026-11-12", "Bench press", 90, 7, 3),
    ("2026-11-12", "Lateral raise", None, 15, 4),
]:
    conn.execute("INSERT INTO lifts (date, exercise_name, weight, reps, sets) "
                 "VALUES (?,?,?,?,?)", (d, name, w, reps, sets))
for d, t, mins in [("2026-11-10", "ride", 58), ("2026-11-11", "legs", None),
                   ("2026-11-12", "push", 45)]:
    conn.execute("INSERT INTO sessions (date, type, status, duration_min) "
                 "VALUES (?, ?, 'done', ?)", (d, t, mins))
conn.commit()

text = briefing.section_progress(conn, today)
print(text)
checks = [
    ("pulldown +10 vs previous", "+10 kg" in text),
    ("pulldown +20 since first", "Since first logged (2026-10-04, 60 kg): +20 kg" in text),
    ("bench same weight, +1 rep", "same weight, +1 reps" in text),
    ("no weight, no fake delta", "Lateral raise: 4 x 15" in text and "(first number logged" in text),
    ("week counts", "week of 2026-11-09: 3 sessions (2 lifting, 1 other), 103 min" in text),
]
failed = [name for name, ok in checks if not ok]
for name, ok in checks:
    print(("ok   " if ok else "FAIL ") + name)
raise SystemExit(1 if failed else 0)

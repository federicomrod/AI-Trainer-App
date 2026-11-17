"""
test_events.py -- offline checks (no model, no cost) for dated goals,
event phases and which event knowledge reaches the briefing.

    python3 test_events.py
"""

import json
import os
import tempfile
from datetime import date, timedelta

tmp = tempfile.mkdtemp()
os.environ["HYBRID_COACH_DB_PATH"] = os.path.join(tmp, "t.db")

import briefing  # noqa: E402
import db  # noqa: E402

today = date(2026, 11, 16)
checks = []

for days, phase in [(200, "base"), (85, "base"), (84, "build"), (29, "build"),
                    (28, "peak"), (15, "peak"), (14, "taper"), (8, "taper"),
                    (7, "race week"), (0, "race week"), (-1, "date has passed")]:
    checks.append((f"{days} days -> {phase}", briefing.event_phase(days) == phase))

goals = ["Hyrox Zurich on 2027-05-16, finish under 1:20",
         "Bench 100 kg for 8 reps", "Bad date 2027-13-45"]
found = briefing.dated_goals(goals, today)
checks.append(("one valid dated goal", len(found) == 1 and found[0][2] == 181))

conn = db.get_connection()
db.init_db(conn)
conn.execute(
    "INSERT INTO profile (id, goals_json, weekly_availability, "
    "typical_session_length_min, equipment, experience_level) "
    "VALUES (1, ?, 'x', 50, 'gym', 'advanced')", (json.dumps(goals),))
conn.commit()
text = briefing.build_briefing(conn, today)
checks += [
    ("days away in briefing", "181 days away (25 weeks, 6 days)" in text),
    ("phase in briefing", "Phase if this is a race: base" in text),
    ("hyrox knowledge included", "Eight rounds, each a 1 km run" in text),
    ("70.3 knowledge not included", "IRONMAN 70.3 (half-distance" not in text),
]

conn.execute("UPDATE profile SET goals_json = ?", (json.dumps(["Run a Hyrox"]),))
conn.commit()
text = briefing.build_briefing(conn, today)
checks.append(("undated event asks for the date", "NO DATE on record" in text))

conn.execute("UPDATE profile SET goals_json = ?", (json.dumps(["Build muscle"]),))
conn.commit()
text = briefing.build_briefing(conn, today)
checks += [("no event, no knowledge", "EVENT KNOWLEDGE" not in text),
           ("no dates says so", "(no goal has a date)" in text)]

for name, ok in checks:
    print(("ok   " if ok else "FAIL ") + name)
raise SystemExit(0 if all(ok for _, ok in checks) else 1)

"""
seed.py — wipes the database and loads one of the test fixtures from
server/fixtures/.

A fixture is a plain Python module describing a made-up two weeks of
training (see fixtures/messy_two_weeks.py and fixtures/calm_two_weeks.py).
This script's only job is generic: reset the tables, then insert
whatever the chosen fixture hands back. All the storytelling lives in
the fixture files, not here.

Usage:
    python3 seed.py            # default: messy_two_weeks
    python3 seed.py messy      # same as above
    python3 seed.py calm       # the uneventful-week fixture
"""

import importlib
import sys

from db import get_connection, init_db

FIXTURES = {
    "messy": "fixtures.messy_two_weeks",
    "calm": "fixtures.calm_two_weeks",
}
DEFAULT_FIXTURE = "messy"

TABLES_IN_DELETE_ORDER = (
    "profile", "sessions", "lifts", "checkins", "events", "memory",
    "messages",
)


def reset(conn):
    """Empty every table so re-seeding always starts from a known,
    clean state instead of piling up duplicates."""
    for table in TABLES_IN_DELETE_ORDER:
        conn.execute(f"DELETE FROM {table}")
    conn.commit()


def load_fixture(conn, fx):
    conn.execute(
        """INSERT INTO profile
           (id, goals_json, weekly_availability, typical_session_length_min,
            equipment, preferred_exercises_json, disliked_exercises_json,
            injuries, experience_level)
           VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?)""",
        fx.profile_row(),
    )
    conn.executemany(
        """INSERT INTO sessions
           (date, type, status, planned_summary, actual_summary,
            duration_min, rpe, notes, source)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        fx.session_rows(),
    )
    conn.executemany(
        """INSERT INTO lifts (date, exercise_name, weight, reps, sets, note)
           VALUES (?, ?, ?, ?, ?, ?)""",
        fx.lift_rows(),
    )
    conn.executemany(
        """INSERT INTO checkins
           (date, sleep, energy, soreness_json, pain_flag, note)
           VALUES (?, ?, ?, ?, ?, ?)""",
        fx.checkin_rows(),
    )
    conn.executemany(
        """INSERT INTO events
           (start_date, end_date, type, note, effect_on_availability)
           VALUES (?, ?, ?, ?, ?)""",
        fx.event_rows(),
    )
    conn.executemany(
        "INSERT INTO memory (date_added, text) VALUES (?, ?)",
        fx.memory_rows(),
    )
    conn.executemany(
        "INSERT INTO messages (role, content, timestamp) VALUES (?, ?, ?)",
        fx.message_rows(),
    )
    conn.commit()


def main():
    name = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_FIXTURE
    if name not in FIXTURES:
        print(f"Unknown fixture '{name}'. Choices: {', '.join(FIXTURES)}")
        sys.exit(1)

    fx = importlib.import_module(FIXTURES[name])
    conn = get_connection()
    init_db(conn)
    reset(conn)
    load_fixture(conn, fx)
    print(f"Seeded database with the '{name}' fixture "
          f"(anchored on today = {fx.TODAY.isoformat()}).")


if __name__ == "__main__":
    main()

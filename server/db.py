"""
db.py — creates and connects to the SQLite database.

Everything the coach knows lives in one file, hybrid_coach.db, sitting
next to this script. SQLite needs no server to run: it's just a file
that Python opens directly. That's the right amount of infrastructure
for one person testing on their own machine (M0). If this ever needs to
run for multiple people on a real server, swapping in Postgres later is
a small change, because we only ever talk to the database through the
functions in this file and briefing.py — never with raw SQL scattered
around the rest of the code.

Seven tables, matching CLAUDE.md exactly. Do not add an eighth without
checking CLAUDE.md first.
"""

import sqlite3
from pathlib import Path

DB_PATH = Path(__file__).parent / "hybrid_coach.db"

SCHEMA = """
-- One row: who the athlete is, what they want, how they train.
-- goals and preferred/disliked exercises are stored as JSON text (a
-- list encoded as a string) because SQLite has no native list type.
-- goals_json is in priority order: first = highest priority. That's
-- simpler than a separate priority number and just as clear to read.
-- No tracked-exercises field here on purpose: tracking is emergent,
-- see the `lifts` table below.
CREATE TABLE IF NOT EXISTS profile (
    id INTEGER PRIMARY KEY,
    goals_json TEXT NOT NULL,
    weekly_availability TEXT,
    typical_session_length_min INTEGER,
    equipment TEXT,
    preferred_exercises_json TEXT,
    disliked_exercises_json TEXT,
    injuries TEXT,
    experience_level TEXT
);

-- One row per session, whether it was planned, actually happened, or
-- both. This is the spine of the briefing: the last 14 days come
-- straight out of this table, and so does "this week's plan".
CREATE TABLE IF NOT EXISTS sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT NOT NULL,
    type TEXT NOT NULL CHECK (type IN
        ('push','pull','legs','ride','run','swim','intervals','rest')),
    status TEXT NOT NULL CHECK (status IN
        ('planned','done','partial','skipped','unplanned')),
    planned_summary TEXT,
    actual_summary TEXT,
    duration_min INTEGER,
    rpe REAL,
    notes TEXT,
    source TEXT CHECK (source IN
        ('manual','voice','healthkit','screenshot') OR source IS NULL)
);

-- The one exception to free-text, summary-level logging. A row here is
-- one real number for one exercise on one date. There's no separate
-- "tracked exercises" list anywhere: an exercise counts as tracked the
-- moment it has a row here, and stops mattering the moment it stops
-- getting them. The briefing reads this table directly; it never goes
-- hunting for numbers buried in session notes.
CREATE TABLE IF NOT EXISTS lifts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT NOT NULL,
    exercise_name TEXT NOT NULL,
    weight REAL,
    reps INTEGER,
    sets INTEGER,
    note TEXT
);

-- One row per daily check-in. soreness_json is a small JSON dict, e.g.
-- {"legs": "moderate", "shoulders": "low"} — free-form regions rather
-- than a fixed list, because which body part is sore changes week to
-- week and we don't want a rigid schema fighting real answers.
CREATE TABLE IF NOT EXISTS checkins (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT NOT NULL,
    sleep TEXT CHECK (sleep IN ('poor','normal','good') OR sleep IS NULL),
    energy INTEGER CHECK (energy BETWEEN 1 AND 5),
    soreness_json TEXT,
    pain_flag INTEGER NOT NULL DEFAULT 0 CHECK (pain_flag IN (0,1)),
    note TEXT
);

-- Anything outside normal training that changes what's realistic:
-- travel, a big social night, illness, an unplanned big walk.
CREATE TABLE IF NOT EXISTS events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    start_date TEXT NOT NULL,
    end_date TEXT NOT NULL,
    type TEXT NOT NULL CHECK (type IN
        ('travel','social','illness','big_walk','other')),
    note TEXT,
    effect_on_availability TEXT
);

-- Plain-text facts the coach has learned over time, one per row.
-- e.g. "prefers hip thrust over back squat".
CREATE TABLE IF NOT EXISTS memory (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date_added TEXT NOT NULL,
    text TEXT NOT NULL
);

-- The conversation itself: every message in or out, in order.
CREATE TABLE IF NOT EXISTS messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    role TEXT NOT NULL CHECK (role IN ('user','assistant','system')),
    content TEXT NOT NULL,
    timestamp TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S','now'))
);
"""


def get_connection(db_path=DB_PATH):
    """Open (or create) the database file and return a connection.

    row_factory = sqlite3.Row means rows come back as dict-like objects
    (row["date"] instead of row[0]) — much less error-prone to read.
    """
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    return conn


def init_db(conn):
    """Create the six tables if they don't already exist. Safe to call
    every time the app starts — it never touches existing data."""
    conn.executescript(SCHEMA)
    conn.commit()


if __name__ == "__main__":
    # Running "python3 server/db.py" directly just sets up the file.
    conn = get_connection()
    init_db(conn)
    print(f"Database ready at {DB_PATH}")

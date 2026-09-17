"""
checkin.py — save today's check-in (sleep, energy, soreness by region,
an optional note). One check-in per calendar day: submitting again the
same day updates that day's row instead of adding a duplicate, so
briefing.py's "most recent check-in" query never has to guess between
same-day rows with no reliable tiebreaker.
"""

import json
from datetime import date


def save_checkin(conn, sleep, energy, soreness, note, today=None):
    if today is None:
        today = date.today()
    today_iso = today.isoformat()
    soreness_json = json.dumps(soreness or {})

    existing = conn.execute(
        "SELECT id FROM checkins WHERE date = ?", (today_iso,)
    ).fetchone()

    if existing:
        conn.execute(
            "UPDATE checkins SET sleep = ?, energy = ?, soreness_json = ?, "
            "note = ? WHERE id = ?",
            (sleep, energy, soreness_json, note, existing["id"]),
        )
        checkin_id = existing["id"]
    else:
        cur = conn.execute(
            "INSERT INTO checkins (date, sleep, energy, soreness_json, "
            "pain_flag, note) VALUES (?, ?, ?, ?, 0, ?)",
            (today_iso, sleep, energy, soreness_json, note),
        )
        checkin_id = cur.lastrowid
    conn.commit()

    return {
        "id": checkin_id,
        "date": today_iso,
        "sleep": sleep,
        "energy": energy,
        "soreness": soreness or {},
        "note": note,
    }

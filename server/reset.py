"""
reset.py — empties the database completely, so the coach is reasoning
about your real training instead of a made-up fixture.

seed.py loads one of the invented two-week stories in fixtures/, which
is right for testing the coaching logic and wrong for actually using
the app: every session, check-in and lift in there is fiction, so
nothing the coach says about it means anything. This wipes all seven
tables and stops there — no profile, no sessions, no history. The app
then shows onboarding on next launch (see server/onboarding.py) and
everything from that point on is yours.

Destructive and not undoable, so it asks first unless you pass --yes.

Usage:
    python3 reset.py           # asks for confirmation
    python3 reset.py --yes     # no prompt
"""

import sys

from db import TABLES, get_connection, init_db, wipe


def counts(conn):
    """How many rows are about to be destroyed, per table -- shown
    before asking, so the confirmation is an informed one rather than
    a blind y/n."""
    return {
        table: conn.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
        for table in TABLES
    }


def main():
    assume_yes = "--yes" in sys.argv[1:] or "-y" in sys.argv[1:]

    conn = get_connection()
    init_db(conn)  # so this works on a database that doesn't exist yet

    before = counts(conn)
    total = sum(before.values())
    if total == 0:
        print("Database is already empty — nothing to do.")
        return

    print("This will permanently delete:")
    for table, n in before.items():
        if n:
            print(f"  {n:>5}  {table}")

    if not assume_yes:
        answer = input("\nWipe the database? Type 'yes' to confirm: ")
        if answer.strip().lower() != "yes":
            print("Cancelled — nothing was deleted.")
            return

    wipe(conn)
    print(f"\nDeleted {total} rows. The database is now empty.")
    print("Open the app and it'll walk you through setting up your profile.")


if __name__ == "__main__":
    main()

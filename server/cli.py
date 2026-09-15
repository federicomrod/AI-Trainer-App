"""
cli.py — type a message, see the briefing, the raw decision JSON, and
the rendered coach reply.

Usage:
    python3 cli.py                        # no message -- just "what's today"
    python3 cli.py "legs are wrecked"     # a real message

Runs against whatever is currently seeded in hybrid_coach.db -- use
seed.py first (messy or calm) to set up a scenario to test against.

This is a thin terminal front end over coach.run_turn(), which is the
one place the actual core loop lives. server/api.py is the other front
end over that same function, for the iOS app.
"""

import json
import sys

import coach
from db import get_connection

BAR = "=" * 70


def heading(title):
    print(BAR)
    print(title)
    print(BAR)


def main():
    message = " ".join(sys.argv[1:]).strip()
    conn = get_connection()

    result = coach.run_turn(conn, message)

    heading("BRIEFING")
    print(result.briefing)
    print()

    if result.error == "planner_error":
        heading("PLANNER ERROR — no decision produced, nothing saved")
        print(result.error_detail)
        sys.exit(1)

    if result.safety_flagged:
        heading("SAFETY CHECK: flagged — skipping the model call entirely")

    heading("RAW DECISION JSON")
    print(json.dumps(result.decision, indent=2))
    print()

    if result.error == "validation_error":
        heading("VALIDATION FAILED — decision rejected, nothing saved, "
                "nothing rendered")
        print(result.error_detail)
        sys.exit(1)

    heading("RENDERED COACH REPLY")
    print(result.reply)


if __name__ == "__main__":
    main()

"""
cli.py — type a message, see the briefing, the raw decision JSON, and
the rendered coach reply. This is the whole M0 core loop end to end.

Usage:
    python3 cli.py                        # no message -- just "what's today"
    python3 cli.py "legs are wrecked"     # a real message

Runs against whatever is currently seeded in hybrid_coach.db -- use
seed.py first (messy or calm) to set up a scenario to test against.

Order of operations, matching CLAUDE.md's core loop:
    1. Assemble the briefing from the database.
    2. Hard safety pre-check on the raw message -- BEFORE anything
       else runs. If it trips, the model is never called.
    3. Otherwise, the one model call.
    4. Hard validation of what came back (shape, then the duration
       cap against today's actual available time).
    5. Save the accepted exchange, then render it.
"""

import json
import sys

import planner
import render
import safety
import validation
from briefing import build_briefing
from db import get_connection

BAR = "=" * 70


def heading(title):
    print(BAR)
    print(title)
    print(BAR)


def save_message(conn, role, content):
    conn.execute(
        "INSERT INTO messages (role, content) VALUES (?, ?)", (role, content)
    )
    conn.commit()


def fabricated_safety_decision():
    """A schema-shaped decision for the safety pre-check path. Nothing
    here is model output -- the model was never called -- so `why` and
    `specialist_notes` stay empty. The fixed text from
    prompts/safety-response.md is what actually gets shown; this dict
    exists so the exchange has the same shape in messages.content as a
    normal decision, for the recent-decisions briefing section later."""
    return {
        "decision": "REST",
        "today": {"type": "rest", "duration_min": 0, "exercises": [],
                   "intensity_note": ""},
        "why": "",
        "plan_diff": [],
        "specialist_notes": [],
        "memory_to_add": [],
        "question": None,
        "safety_flag": ("pre-check flagged possible injury/illness "
                         "language in the message; the model was not "
                         "called"),
    }


def main():
    message = " ".join(sys.argv[1:]).strip()
    conn = get_connection()

    briefing_text = build_briefing(conn)
    heading("BRIEFING")
    print(briefing_text)
    print()

    if message:
        save_message(conn, "user", message)

    # --- Hard safety pre-check. Runs before anything else, and skips
    # the model call entirely if it trips. ---
    if safety.check_message(message):
        heading("SAFETY CHECK: flagged — skipping the model call entirely")
        decision = fabricated_safety_decision()
        reply_text = safety.safety_response_text()
        save_message(conn, "assistant", json.dumps(decision))

        heading("RAW DECISION JSON")
        print(json.dumps(decision, indent=2))
        print()
        heading("RENDERED COACH REPLY")
        print(reply_text)
        return

    # --- The one model call. ---
    try:
        decision = planner.get_decision(briefing_text, message)
    except planner.PlannerError as e:
        heading("PLANNER ERROR — no decision produced, nothing saved")
        print(str(e))
        sys.exit(1)

    heading("RAW DECISION JSON")
    print(json.dumps(decision, indent=2))
    print()

    # --- Hard validation, after the call. ---
    try:
        validation.validate_shape(decision)
        available_min, basis = validation.get_available_minutes(conn, message)
        validation.validate_duration(decision, available_min, basis)
    except validation.ValidationError as e:
        heading("VALIDATION FAILED — decision rejected, nothing saved, "
                "nothing rendered")
        print(str(e))
        sys.exit(1)

    save_message(conn, "assistant", json.dumps(decision))

    heading("RENDERED COACH REPLY")
    print(render.render_reply(decision))


if __name__ == "__main__":
    main()

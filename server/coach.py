"""
coach.py — the one implementation of CLAUDE.md's core loop: assemble
the briefing, run the hard safety pre-check, make the one model call,
validate what comes back, save the accepted exchange, then render it.

cli.py (the terminal) and api.py (the HTTP server the iOS app talks to)
are both thin front ends over run_turn() below. Neither one re-does any
of this logic itself -- that would be two places the same rules could
quietly drift apart.
"""

import json
from dataclasses import dataclass
from typing import Optional

import planner
import render
import safety
import validation
from briefing import build_briefing


@dataclass
class TurnResult:
    briefing: str
    decision: Optional[dict]
    reply: Optional[str]
    safety_flagged: bool
    error: Optional[str] = None       # "planner_error" | "validation_error" | None
    error_detail: Optional[str] = None


def _fabricated_safety_decision():
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


def _save_message(conn, role, content):
    conn.execute(
        "INSERT INTO messages (role, content) VALUES (?, ?)", (role, content)
    )
    conn.commit()


def run_turn(conn, message):
    """Run one full turn of the core loop for `message` (may be empty
    -- "just tell me today"). Always returns a TurnResult; never
    raises. The caller decides how to display it."""
    message = (message or "").strip()
    briefing_text = build_briefing(conn)

    if message:
        _save_message(conn, "user", message)

    # --- Hard safety pre-check. Runs before anything else, and skips
    # the model call entirely if it trips. ---
    if safety.check_message(message):
        decision = _fabricated_safety_decision()
        reply_text = safety.safety_response_text()
        _save_message(conn, "assistant", json.dumps(decision))
        return TurnResult(
            briefing=briefing_text, decision=decision, reply=reply_text,
            safety_flagged=True,
        )

    # --- The one model call. ---
    try:
        decision = planner.get_decision(briefing_text, message)
    except planner.PlannerError as e:
        return TurnResult(
            briefing=briefing_text, decision=None, reply=None,
            safety_flagged=False, error="planner_error", error_detail=str(e),
        )

    # --- Hard validation, after the call. ---
    try:
        validation.validate_shape(decision)
        available_min, basis = validation.get_available_minutes(conn, message)
        validation.validate_duration(decision, available_min, basis)
    except validation.ValidationError as e:
        return TurnResult(
            briefing=briefing_text, decision=decision, reply=None,
            safety_flagged=False, error="validation_error", error_detail=str(e),
        )

    _save_message(conn, "assistant", json.dumps(decision))

    return TurnResult(
        briefing=briefing_text, decision=decision,
        reply=render.render_reply(decision), safety_flagged=False,
    )

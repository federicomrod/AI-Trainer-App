"""
lift_parser.py — pulls tracked-lift numbers (exercise, weight, reps,
sets) out of free text, so the athlete can just say what they did
instead of filling in a field per exercise. CLAUDE.md's logging
philosophy is explicit: default input is a summary or a voice note,
not a form -- structured entry is a fallback, not the primary path.

One small, separate model call from the main planner call in
planner.py -- extracting numbers out of a sentence isn't "deciding
what to train," and giving it its own focused prompt
(prompts/lift-parser.md) keeps that prompt free to change without
touching planner.md's much bigger job. Reuses the same provider
abstraction (server/providers/) and the same HYBRID_COACH_PROVIDER
config as the planner, via planner.active_provider(), rather than
inventing a second one.
"""

from pathlib import Path

import planner
from providers import PlannerError

PROMPT_PATH = Path(__file__).parent.parent / "prompts" / "lift-parser.md"

LIFT_PARSE_SCHEMA = {
    "type": "object",
    "properties": {
        "lifts": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "exercise_name": {"type": "string"},
                    "weight": {"type": ["number", "null"]},
                    "reps": {"type": ["integer", "null"]},
                    "sets": {"type": ["integer", "null"]},
                    "note": {"type": ["string", "null"]},
                },
                "required": ["exercise_name", "weight", "reps", "sets", "note"],
            },
        },
    },
    "required": ["lifts"],
}


def parse_lifts(conn, text):
    """Best-effort extraction: on any failure, returns an empty list
    rather than raising. A parsing hiccup should never block saving
    the session log itself -- whatever the athlete typed into the
    manual fields, if anything, still gets saved either way.

    Passes the athlete's already-tracked exercise names along with the
    text, so "did squats" resolves to their own established name (e.g.
    "Back Squat") instead of a fresh generic one that would split that
    exercise's progress into two separate series -- see
    prompts/lift-parser.md."""
    text = (text or "").strip()
    if not text:
        return []

    known_names = [
        row["exercise_name"]
        for row in conn.execute("SELECT DISTINCT exercise_name FROM lifts")
    ]
    user_content = (
        f"ALREADY-TRACKED EXERCISE NAMES: "
        f"{', '.join(known_names) if known_names else '(none yet)'}\n\n"
        f"TEXT:\n{text}"
    )

    try:
        provider = planner.active_provider()
        result = provider.get_structured(
            PROMPT_PATH.read_text(), user_content, LIFT_PARSE_SCHEMA
        )
    except PlannerError:
        return []

    return result.get("lifts") or []

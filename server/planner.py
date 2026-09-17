"""
planner.py — the one call to the model that turns a briefing plus a
new message into a decision.

How the coach reasons lives in prompts/planner.md and
prompts/coach-voice.md, not here. This file loads those, builds the
one request, and hands off to whichever provider module
HYBRID_COACH_PROVIDER names (server/providers/) — switching between
OpenAI and Anthropic is a config change, never a code change. It does
not retry and does not patch a bad response by calling the model
again — if something is wrong, PlannerError is raised and the caller
decides what to do. Silently retrying would mean the "decision" shown
to the user might not be what the model actually said on the call that
mattered.
"""

import os
from pathlib import Path

from dotenv import load_dotenv

from providers import PlannerError, anthropic_provider, openai_provider

load_dotenv()  # picks up *_API_KEY from server/.env if present

PROMPTS_DIR = Path(__file__).parent.parent / "prompts"
PLANNER_PROMPT_PATH = PROMPTS_DIR / "planner.md"
COACH_VOICE_PATH = PROMPTS_DIR / "coach-voice.md"

# The one setting that decides which model answers the planner call.
# Set HYBRID_COACH_PROVIDER=anthropic in server/.env to switch — no
# code edits needed. Each provider has its own default model, which
# HYBRID_COACH_MODEL does not override (see OPENAI_MODEL /
# ANTHROPIC_MODEL in each provider module) so flipping providers can't
# accidentally send the wrong model name to the wrong API.
DEFAULT_PROVIDER = "openai"
PROVIDERS = {
    "openai": openai_provider,
    "anthropic": anthropic_provider,
}

# Mirrors the schema in CLAUDE.md exactly. This is plumbing (the JSON
# shape), not reasoning -- the reasoning that fills these fields in
# lives entirely in prompts/planner.md. Shared across every provider;
# openai_provider.py adds one OpenAI-only technicality on top of a copy
# of this rather than baking it in here.
DECISION_SCHEMA = {
    "type": "object",
    "properties": {
        "decision": {
            "type": "string",
            "enum": ["KEEP", "MODIFY", "REST"],
        },
        "today": {
            "type": "object",
            "properties": {
                "type": {"type": "string"},
                "duration_min": {"type": "integer"},
                "exercises": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "properties": {
                            "name": {"type": "string"},
                            "sets": {"type": "integer"},
                            "reps": {"type": "string"},
                            "note": {"type": ["string", "null"]},
                        },
                        "required": ["name", "sets", "reps", "note"],
                    },
                },
                "intensity_note": {"type": "string"},
            },
            "required": ["type", "duration_min", "exercises", "intensity_note"],
        },
        "why": {"type": "string"},
        "plan_diff": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "date": {"type": "string"},
                    "from": {"type": "string"},
                    "to": {"type": "string"},
                    "reason": {"type": "string"},
                },
                "required": ["date", "from", "to", "reason"],
            },
        },
        "specialist_notes": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "coach": {
                        "type": "string",
                        "enum": ["strength", "endurance", "recovery"],
                    },
                    "text": {"type": "string"},
                },
                "required": ["coach", "text"],
            },
        },
        "memory_to_add": {"type": "array", "items": {"type": "string"}},
        "question": {"type": ["string", "null"]},
        "safety_flag": {"type": ["string", "null"]},
    },
    "required": [
        "decision", "today", "why", "plan_diff", "specialist_notes",
        "memory_to_add", "question", "safety_flag",
    ],
}


def _load_system_prompt():
    planner_prompt = PLANNER_PROMPT_PATH.read_text()
    coach_voice = COACH_VOICE_PATH.read_text()
    return (
        f"{planner_prompt}\n\n"
        f"---\n\n"
        f"# prompts/coach-voice.md (register and tone reference)\n\n"
        f"{coach_voice}"
    )


def active_provider():
    """Whichever provider module HYBRID_COACH_PROVIDER names -- shared
    by this file's one decision call and lift_parser.py's smaller
    extraction call, so both switch providers together with the same
    one config value."""
    name = os.environ.get("HYBRID_COACH_PROVIDER", DEFAULT_PROVIDER).strip().lower()
    provider = PROVIDERS.get(name)
    if provider is None:
        raise PlannerError(
            f"Unknown HYBRID_COACH_PROVIDER '{name}'. Choices: "
            f"{', '.join(PROVIDERS)}"
        )
    return provider


def get_decision(briefing_text, message_text, image_base64=None):
    """Make the one model call, through whichever provider is
    configured. `image_base64` is a screenshot the athlete attached
    (CLAUDE.md: "send the image to the model directly" -- no separate
    vision step). Returns the decision as a plain dict. Raises
    PlannerError on anything unexpected -- no retries."""
    provider = active_provider()

    user_content = (
        f"BRIEFING:\n\n{briefing_text}\n\n"
        f"NEW MESSAGE FROM ATHLETE:\n"
        f"{message_text if message_text else '(no message -- just tell me today)'}"
    )

    return provider.get_structured(
        _load_system_prompt(), user_content, DECISION_SCHEMA,
        image_base64=image_base64,
    )

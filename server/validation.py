"""
validation.py — hard rules enforced in code after the model call,
never patched by silently retrying or silently editing the model's
answer.

Two things happen here:
1. validate_shape() — a light sanity check that the response actually
   has the fields CLAUDE.md's schema requires. The model call forces a
   matching JSON schema already (see planner.py), so this mostly
   catches the unusual case where something still comes back wrong.
2. validate_duration() — the real hard rule the user asked for:
   today's session can never be longer than the athlete's actual
   available time. If it is, this REJECTS the decision. It does not
   shrink the exercise list to fit and it does not call the model
   again — either of those would be a silent change to what the model
   actually said, and CLAUDE.md's whole approach depends on knowing
   the model's raw output was honest.
"""

import re


class ValidationError(Exception):
    """Raised when a decision fails a hard rule. The caller's job is
    to stop and show this to the user -- not to retry or patch."""


REQUIRED_TOP_LEVEL = [
    "decision", "today", "why", "reasons", "plan_diff", "specialist_notes",
    "memory_to_add", "question", "safety_flag",
]
VALID_DECISIONS = {"KEEP", "MODIFY", "REST"}


def validate_shape(decision):
    if not isinstance(decision, dict):
        raise ValidationError("Decision is not a JSON object.")
    missing = [k for k in REQUIRED_TOP_LEVEL if k not in decision]
    if missing:
        raise ValidationError(f"Decision is missing required field(s): {missing}")
    if decision["decision"] not in VALID_DECISIONS:
        raise ValidationError(
            f"'decision' is {decision['decision']!r}, expected one of "
            f"{sorted(VALID_DECISIONS)}"
        )
    if not isinstance(decision.get("today"), dict):
        raise ValidationError("'today' must be an object.")
    if "duration_min" not in decision["today"]:
        raise ValidationError("'today.duration_min' is required.")


# --- Available time -----------------------------------------------

# Looked for in the athlete's own message, in order. First match wins.
_MINUTE_PATTERNS = [
    (re.compile(r"\bhalf an hour\b", re.IGNORECASE), lambda m: 30),
    (re.compile(r"\ban hour and a half\b", re.IGNORECASE), lambda m: 90),
    (re.compile(r"\ban hour\b", re.IGNORECASE), lambda m: 60),
    (re.compile(r"\b(\d+)\s*(?:minutes|minute|mins|min)\b", re.IGNORECASE),
     lambda m: int(m.group(1))),
    (re.compile(r"\b(\d+)\s*(?:hours|hour|hrs|hr)\b", re.IGNORECASE),
     lambda m: int(m.group(1)) * 60),
]


def extract_stated_minutes(text):
    """Look for an explicit statement of available time in the
    message, e.g. "only have 40 minutes". Returns None if nothing is
    found. Simple pattern matching, not language understanding -- it
    will miss unusual phrasing, and that's an accepted limitation for
    M0."""
    if not text:
        return None
    for pattern, extract in _MINUTE_PATTERNS:
        m = pattern.search(text)
        if m:
            return extract(m)
    return None


def get_available_minutes(conn, message_text):
    """Today's available time: whatever the athlete stated in this
    message, else the profile's typical session length. This does NOT
    look at events (e.g. today's travel) to shrink automatically --
    "no gym access" isn't the same claim as "no time", and conflating
    them is judgement the model should make from the briefing, not a
    hard rule in code."""
    stated = extract_stated_minutes(message_text)
    if stated is not None:
        return stated, "stated in the message"
    row = conn.execute(
        "SELECT typical_session_length_min FROM profile WHERE id = 1"
    ).fetchone()
    default = row["typical_session_length_min"] if row else None
    return default, "profile's typical session length"


def validate_duration(decision, available_min, basis):
    """Raise if today's plan is longer than what's actually available.
    `available_min` of None means there was nothing to check against
    (no profile, nothing stated) -- in that case this is a no-op."""
    if available_min is None:
        return
    duration = decision.get("today", {}).get("duration_min")
    if duration is not None and duration > available_min:
        raise ValidationError(
            f"Rejected: today's plan calls for {duration} min, but only "
            f"{available_min} min is available ({basis}). The decision "
            f"was not shrunk to fit and the model was not re-prompted -- "
            f"that would silently change what it actually said."
        )

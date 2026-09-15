"""
safety.py — the hard safety check that runs BEFORE the model is ever
called.

Per prompts/coach-voice.md: stopping on red-flag symptoms is enforced
in code, not left to a model's judgement. A model can be talked out of
a rule under the right phrasing, or just miss it on an off day; a
keyword check either matches or it doesn't.

This is a phrase check, not real language understanding. It will have
false negatives (real problems described in words that aren't on this
list) and occasional false positives (ordinary training talk that
happens to match). Between those two failure modes, a false positive
just costs one unnecessary "go see someone" message — a false negative
could mean the coach programs through a real injury. So the list stays
a little wide rather than a little narrow. This is a floor, not a
diagnosis.
"""

import re
from pathlib import Path

SAFETY_RESPONSE_PATH = Path(__file__).parent.parent / "prompts" / "safety-response.md"

# Checked case-insensitively against the raw message. Grouped by
# category only for readability -- every match is treated the same.
_PATTERNS = [
    # chest
    r"\bchest (pain|hurts?|tight|tightness|pressure)\b",
    r"\bpain in (my|the) chest\b",
    # dizziness / fainting
    r"\bdizz(y|iness)\b",
    r"\blight[- ]?headed\b",
    r"\bfeel(?:ing)? faint\b",
    r"\bpassed out\b",
    r"\bfainted\b",
    # sharp / joint pain, distinct from ordinary soreness
    r"\bsharp pain\b",
    r"\bshooting pain\b",
    r"\bstabbing pain\b",
    r"\bjoint pain\b",
    r"\bsomething (popped|snapped)\b",
    r"\bheard a pop\b",
    r"\bcan'?t (put weight|bear weight) on\b",
    r"\bcan'?t (straighten|bend) (my|it)\b",
    # illness
    r"\bfever\b",
    r"\bvomit(ing)?\b",
    r"\bthrowing up\b",
    r"\bcan'?t breathe\b",
    r"\bshortness of breath\b",
    r"\b(think|might) (i'?ve |i )?(broke|tore|torn|fractured)\b",
]

_COMPILED = [re.compile(p, re.IGNORECASE) for p in _PATTERNS]


def check_message(text):
    """True if the message contains a red-flag phrase. No ML, no
    model call -- nothing that could itself be talked out of flagging
    something."""
    if not text:
        return False
    return any(p.search(text) for p in _COMPILED)


def safety_response_text():
    """The fixed response used verbatim when check_message() is True.
    Lives in prompts/safety-response.md, not here, so the wording can
    be edited without touching code."""
    raw = SAFETY_RESPONSE_PATH.read_text()
    return raw.split("---", 1)[1].strip()

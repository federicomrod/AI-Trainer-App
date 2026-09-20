"""
scenarios.py — the frozen scenarios themselves.

One entry per real bug. A scenario is: what the database contains,
what the athlete says, and what must be true afterwards. Checks are
about behaviour (what was written, whether a question was asked), never
about wording -- the model's phrasing is allowed to vary, its actions
are not.
"""

import json
from dataclasses import dataclass, field
from datetime import date, timedelta
from typing import Callable, Dict, List, Optional


@dataclass
class Scenario:
    name: str
    #: Why this exists. Printed with a failure.
    about: str
    message: str
    profile: Dict = field(default_factory=dict)
    #: (days_ago, type, status, summary) rows written before the turn.
    sessions: List[tuple] = field(default_factory=list)
    #: (role, content) rows written before the turn -- for scenarios
    #: where the message only makes sense as a reply.
    messages: List[tuple] = field(default_factory=list)
    #: name -> check(result, conn, today) -> None when it passes, or a
    #: string saying what was wrong.
    checks: Dict[str, Callable] = field(default_factory=dict)


def _question_turn(question, unresolved=()):
    """A previous assistant turn that asked something. Stored the way
    coach.py stores one: the decision JSON, not the rendered text,
    including the `_applied_updates` marker that records which days it
    asked about."""
    return json.dumps({
        "decision": "KEEP",
        "today": {"type": "rest", "duration_min": 0, "exercises": [],
                  "intensity_note": ""},
        "why": "Logged what I could from that.",
        "reasons": [],
        "plan_diff": [],
        "specialist_notes": [],
        "memory_to_add": [],
        "question": question,
        "safety_flag": None,
        "_applied_updates": {
            "applied": [],
            "rejected": [],
            "unresolved": [
                {"date": day, "heard": heard, "options": ["swim", "pull"]}
                for day, heard in unresolved
            ],
        },
    })


DEFAULT_PROFILE = {
    "goals": ["Stay strong but build endurance"],
    "weekly_availability": "5-6 days a week",
    "typical_session_length_min": 60,
    "equipment": "Full gym, road bike, pool",
    "preferred_exercises": [],
    "disliked_exercises": [],
    "injuries": None,
    "experience_level": "Advanced",
}


# --- small helpers the checks are written in ------------------------

def _last_tuesday(today):
    """The most recent Tuesday before today."""
    offset = (today.weekday() - 1) % 7 or 7
    return today - timedelta(days=offset)


def _row(conn, day):
    return conn.execute(
        "SELECT type, status, actual_summary FROM sessions WHERE date = ?",
        (day.isoformat(),),
    ).fetchone()


def _asked_about(result, day):
    """Did the reply actually put a question to the athlete about this
    day? Looks for the day's name, not for any particular sentence."""
    decision = result.decision or {}
    question = (decision.get("question") or "") + " " + (result.saved_updates or "")
    return day.strftime("%a").lower() in question.lower() and "?" in question


def _updates(result):
    return (result.decision or {}).get("_applied_updates") or {}


# --- the scenarios --------------------------------------------------

def _tuesday_not_written(result, conn, today):
    tuesday = _last_tuesday(today)
    row = _row(conn, tuesday)
    if row is not None:
        return (f"Tuesday was written as {row['type']!r} despite being "
                f"ambiguous; nothing should have been saved for it")
    return None


def _asks_about_tuesday(result, conn, today):
    tuesday = _last_tuesday(today)
    if not _asked_about(result, tuesday):
        return ("no question was put to the athlete about Tuesday; "
                f"question={(result.decision or {}).get('question')!r}")
    return None


def _offers_both_types(result, conn, today):
    unresolved = _updates(result).get("unresolved") or []
    tuesday = _last_tuesday(today).isoformat()
    entry = next((u for u in unresolved if u["date"] == tuesday), None)
    if entry is None:
        return "Tuesday isn't in the unresolved list"
    options = set(entry.get("options") or [])
    if not {"swim", "pull"} <= options:
        return f"the question offers {sorted(options)}, not swim and pull"
    return None


def _other_days_still_saved(result, conn, today):
    """An ambiguous day must not hold up the days that were clear."""
    monday = _last_tuesday(today) - timedelta(days=1)
    row = _row(conn, monday)
    if row is None:
        return "Monday wasn't saved; one unclear day shouldn't block the rest"
    if row["type"] != "push":
        return f"Monday was saved as {row['type']!r}, expected 'push'"
    return None


def _tuesday_saved_as(expected):
    def check(result, conn, today):
        tuesday = _last_tuesday(today)
        row = _row(conn, tuesday)
        if row is None:
            return f"Tuesday wasn't saved at all; expected {expected!r}"
        if row["type"] != expected:
            return f"Tuesday was saved as {row['type']!r}, expected {expected!r}"
        return None
    return check


def _no_question(result, conn, today):
    if (result.decision or {}).get("question"):
        return (f"asked a question when the answer was clear: "
                f"{result.decision['question']!r}")
    return None


SCENARIOS = [
    Scenario(
        name="ambiguous_swim_or_pull",
        about=("A voice note saying 'pull' transcribes as 'the pool'. Both "
               "are valid session types, so a guess is invisible once saved."),
        message=("Quick correction: Monday I did push, and Tuesday was the "
                 "pool."),
        profile=DEFAULT_PROFILE,
        checks={
            "Tuesday is not written": _tuesday_not_written,
            "the reply asks about Tuesday": _asks_about_tuesday,
            "the question offers swim or pull": _offers_both_types,
            "Monday is still saved": _other_days_still_saved,
        },
    ),
    Scenario(
        name="settled_by_detail",
        about=("'40 lengths' settles it. Asking about a day that is "
               "obviously a swim would be pedantic."),
        message="Quick correction: Tuesday was the pool, 40 lengths easy.",
        profile=DEFAULT_PROFILE,
        checks={
            "Tuesday is saved as a swim": _tuesday_saved_as("swim"),
            "no question is asked": _no_question,
        },
    ),
    Scenario(
        name="answer_resolves_the_question",
        about=("The athlete answers the question. That answer has to land "
               "on the right day -- it carries no date of its own."),
        message="It was pull.",
        profile=DEFAULT_PROFILE,
        messages=[
            ("user", "Quick correction: Monday I did push, and Tuesday was the pool."),
            ("assistant", _question_turn(
                'Tue: I heard "Tuesday was the pool" -- was that Swim or '
                "Pull? I haven't saved that day yet.",
                unresolved=[(_last_tuesday(date.today()).isoformat(),
                             "Tuesday was the pool")],
            )),
        ],
        checks={
            "Tuesday is saved as pull": _tuesday_saved_as("pull"),
        },
    ),
]

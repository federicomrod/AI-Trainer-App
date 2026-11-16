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
    #: (days_ago, exercise_name, weight, reps, sets) rows in `lifts`.
    lifts: List[tuple] = field(default_factory=list)
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


# --- "today" is a date, not a session type --------------------------

def _today_row(conn, today):
    return _row(conn, today)


def _today_is_written(result, conn, today):
    row = _today_row(conn, today)
    if row is None:
        return ("nothing was written for today; the session the athlete "
                "said they just finished has to land on today's date")
    if row["type"] != "push":
        return f"today was written as {row['type']!r}, expected 'push'"
    if row["status"] not in ("done", "partial", "unplanned"):
        return f"today's status is {row['status']!r}, expected it to be done"
    return None


def _old_push_day_untouched(result, conn, today):
    """The trap: an older day of the same type, sitting right there."""
    older = today - timedelta(days=5)
    row = _row(conn, older)
    if row is None:
        return "the older push day disappeared entirely"
    if row["actual_summary"] != "push - bench 80kg 3x8":
        return (f"the older push day was overwritten with "
                f"{row['actual_summary']!r} -- 'today' was matched onto it")
    return None


def _todays_numbers_stored(result, conn, today):
    rows = conn.execute(
        "SELECT exercise_name, weight FROM lifts WHERE date = ?",
        (today.isoformat(),),
    ).fetchall()
    if not rows:
        return ("no numbers were stored for today; the exercise detail in "
                "the message was kept only as free text")
    if not any(r["weight"] == 82.5 for r in rows):
        return (f"stored {[(r['exercise_name'], r['weight']) for r in rows]}, "
                f"expected the 82.5kg the athlete gave")
    return None


def _keeps_the_finished_session(result, conn, today):
    decision = result.decision or {}
    if decision.get("decision") != "KEEP":
        return (f"decision is {decision.get('decision')!r}; a day that's "
                f"already been trained isn't something to MODIFY or REST")
    kind = (decision.get("today") or {}).get("type", "")
    if "push" not in kind.lower():
        return f"today came back as {kind!r}, not the push that was logged"
    return None


def _does_not_ask(result, conn, today):
    question = (result.decision or {}).get("question")
    if question:
        return f"asked for something it already had: {question!r}"
    return None


def _no_second_row_for_today(result, conn, today):
    n = conn.execute(
        "SELECT COUNT(*) AS n FROM sessions WHERE date = ?",
        (today.isoformat(),),
    ).fetchone()["n"]
    if n != 1:
        return f"{n} rows for today; a review must not create another one"
    return None


def _numbers_reach_the_coach(result, conn, today):
    if "82.5" not in (result.briefing or ""):
        return ("today's logged numbers aren't in the briefing, so the coach "
                "has no way to know it already has them")
    return None


SCENARIOS += [
    Scenario(
        name="today_is_a_date_not_a_type",
        about=("'Today's push' has to land on today, even with an older "
               "push day sitting in the same window to be matched onto."),
        message="Just finished today's push - bench 82.5 for 3 sets of 8.",
        profile=DEFAULT_PROFILE,
        sessions=[(5, "push", "done", "push - bench 80kg 3x8")],
        checks={
            "today is written": _today_is_written,
            "last week's push is untouched": _old_push_day_untouched,
            "the numbers given are stored": _todays_numbers_stored,
        },
    ),
    Scenario(
        name="already_trained_is_reviewed",
        about=("Opening the app after training must not produce a proposal "
               "for a session that already happened."),
        message="",
        profile=DEFAULT_PROFILE,
        sessions=[(0, "push", "done", "bench 82.5kg 3x8, incline db 30s 3x10")],
        checks={
            "the finished session is kept": _keeps_the_finished_session,
            "no second row for today": _no_second_row_for_today,
        },
    ),
    Scenario(
        name="detail_is_not_re_asked",
        about=("Numbers given once are in the database, so the coach has "
               "them and never asks for them again."),
        message="How did that compare to last time?",
        profile=DEFAULT_PROFILE,
        sessions=[(0, "push", "done", "bench 82.5kg 3x8")],
        lifts=[(0, "Bench Press", 82.5, 8, 3), (7, "Bench Press", 80.0, 8, 3)],
        checks={
            "the numbers are in the briefing": _numbers_reach_the_coach,
            "nothing is asked again": _does_not_ask,
        },
    ),
]


# --- the conversation scenarios -------------------------------------
# Written from Federico's own coaching history (2026-11-16): the things
# the ChatGPT chat did that this app did not. Checks are still about
# behaviour -- what the reply contains, whether the plan was touched --
# never exact wording.

FEDERICO_PROFILE = {
    "goals": ["Aesthetic hypertrophy (lateral delts, upper chest, triceps, back)",
              "Cycling FTP and VO2max"],
    "weekly_availability": "5-6 sessions a week, mornings",
    "typical_session_length_min": 50,
    "equipment": "Commercial gym with Smith machine, Hammer Strength, hack squat",
    "preferred_exercises": ["Bulgarian split squats", "chest-supported T-bar row"],
    "disliked_exercises": ["traditional seated cable row"],
    "injuries": ("Low-back pain from a seated cable row on 2026-10-12. Prefer "
                 "chest-supported rows; avoid heavy unsupported hinging."),
    "experience_level": "Advanced, 10+ years lifting",
}


def _assistant_turn(reply):
    """A previous coach turn as coach.py saves it: the decision JSON."""
    return json.dumps({
        "decision": "KEEP",
        "today": {"type": "legs", "duration_min": 50, "exercises": [],
                  "intensity_note": ""},
        "why": "Legs today.",
        "reply": reply,
        "reasons": [],
        "plan_diff": [],
        "specialist_notes": [],
        "memory_to_add": [],
        "question": None,
        "safety_flag": None,
    })


def _reply_text(result):
    text = ((result.reply or "") + " " +
            " ".join(e.get("name", "") for e in
                     ((result.decision or {}).get("today") or {}).get("exercises", []))
            ).lower()
    # The model often writes typographic hyphens ("T-bar" with a
    # non-breaking hyphen). Same word to a person, different characters
    # to a string match, so fold them to a plain hyphen first.
    for dash in "\u2010\u2011\u2012\u2013\u2014\u2212":
        text = text.replace(dash, "-")
    return text


def _mentions(*words):
    def check(result, conn, today):
        text = _reply_text(result)
        missing = [w for w in words if w.lower() not in text]
        if missing:
            return f"reply never mentions {missing}; got: {result.reply!r}"
        return None
    return check


def _plan_untouched(result, conn, today):
    decision = result.decision or {}
    if decision.get("plan_diff"):
        return f"a question changed the plan: {decision['plan_diff']}"
    if decision.get("decision") != "KEEP":
        return (f"decision is {decision.get('decision')!r}; just answering "
                f"a question should be KEEP")
    return None


def _excludes(*words):
    def check(result, conn, today):
        exercises = ((result.decision or {}).get("today") or {}).get("exercises", [])
        names = " | ".join(e.get("name", "") for e in exercises).lower()
        hit = [w for w in words if w.lower() in names]
        if hit:
            return f"prescribed {hit} in {names!r}"
        return None
    return check


def _answers_at_length(minimum_chars):
    def check(result, conn, today):
        n = len((result.reply or "").strip())
        if n < minimum_chars:
            return (f"reply is {n} characters; a requested routine needs "
                    f"the whole session")
        return None
    return check


SCENARIOS += [
    Scenario(
        name="recalls_last_pull_day",
        about=("ChatGPT remembered what he did last pull day and answered "
               "specifically. The coach has to name the exercises, not a "
               "date."),
        message="What did I do on my last pull day?",
        profile=FEDERICO_PROFILE,
        sessions=[(3, "pull", "done",
                   "Neutral pulldown 4 sets, supinated pulldown 3 sets, "
                   "chest-supported T-bar row 3 sets with a double drop, "
                   "reverse cable fly 5x15, EZ curl and hammer curl "
                   "superset, incline DB curls."),
                  (6, "push", "done", "Incline press, shoulder press, lateral raises")],
        checks={
            "names the real exercises": _mentions("pulldown", "t-bar"),
            "the plan is not touched": _plan_untouched,
        },
    ),
    Scenario(
        name="follows_the_thread",
        about=("'Swap that for belt squat' only makes sense with the "
               "routine in the previous message. No memory of the chat, "
               "no answer."),
        message="Swap the hack squat for belt squat, same sets.",
        profile=FEDERICO_PROFILE,
        messages=[
            ("user", "Give me legs for today"),
            ("assistant", _assistant_turn(
                "Legs, about 50 minutes: Smith squat 4 x 6-8, seated leg "
                "curl 4 x 8-12, hack squat 4 x 8-10, Bulgarian split squat "
                "3 x 8-10 per leg, hip thrust 3 x 8-12, leg extension "
                "3 x 12-15.")),
        ],
        checks={
            "belt squat is in": _mentions("belt squat"),
            "nothing is asked again": _does_not_ask,
        },
    ),
    Scenario(
        name="keeps_the_favourites",
        about=("He asked never to lose Bulgarian split squats without "
               "talking about it first."),
        message="Give me today's legs, 50 minutes.",
        profile=FEDERICO_PROFILE,
        sessions=[(5, "legs", "done", "Smith squats, curls, Bulgarians, hip thrusts")],
        checks={
            "Bulgarians are in": _mentions("bulgarian"),
            "the whole session is given": _answers_at_length(300),
        },
    ),
    Scenario(
        name="protects_the_back",
        about=("Back pain on a seated cable row. A pull session must not "
               "bring that exact movement back."),
        message="Build me a pull session for tomorrow.",
        profile=FEDERICO_PROFILE,
        sessions=[(3, "push", "done", "Incline press, shoulder press")],
        checks={
            "no seated cable row": _excludes("seated cable row", "seated row"),
            "the whole session is given": _answers_at_length(300),
        },
    ),
]


# --- the routine as data (feeds the swipeable rows in the app) -------

def _routine_is_structured(min_items):
    def check(result, conn, today):
        items = ((result.decision or {}).get("today") or {}).get("exercises") or []
        if len(items) < min_items:
            return (f"only {len(items)} rows in today.exercises; the app "
                    f"builds the workout from that list")
        missing = [i.get("name") for i in items if not i.get("rest_sec")]
        if len(missing) > len(items) // 2:
            return f"most rows have no rest_sec: {missing}"
        return None
    return check


def _has_superset(result, conn, today):
    items = ((result.decision or {}).get("today") or {}).get("exercises") or []
    groups = [i.get("superset_group") for i in items if i.get("superset_group")]
    if len(groups) < 2:
        return "the biceps superset has no shared superset_group"
    return None


def _interval_blocks(result, conn, today):
    items = ((result.decision or {}).get("today") or {}).get("exercises") or []
    if len(items) < 3:
        return (f"{len(items)} rows; an interval session needs a warm-up, "
                f"the work block and a cooldown")
    if not any("w" in (i.get("target") or "").lower() for i in items):
        return "no power target on any block"
    return None


SCENARIOS += [
    Scenario(
        name="routine_is_rows",
        about=("The app turns today.exercises into swipeable rows, so a "
               "pull session has to arrive as a real list with rests, "
               "not only as text."),
        message="Build me a pull session, 50 minutes.",
        profile=FEDERICO_PROFILE,
        sessions=[(3, "push", "done", "Incline press, shoulder press")],
        checks={
            "a full list of rows": _routine_is_structured(5),
            "the curl superset is grouped": _has_superset,
        },
    ),
    Scenario(
        name="intervals_are_blocks",
        about=("An interval ride is warm-up, work blocks and cooldown, "
               "each a swipeable row, with the power target on the work."),
        message="Give me the bike intervals: 4 x 4 minutes at 180 W.",
        profile=FEDERICO_PROFILE,
        sessions=[(2, "legs", "done", "Smith squats, curls, hack squat")],
        checks={"warm-up, work, cooldown": _interval_blocks},
    ),
]


# --- the debrief ------------------------------------------------------

def _debrief_uses_the_numbers(result, conn, today):
    debrief = (result.decision or {}).get("debrief")
    if not debrief:
        return "no debrief came back for a session that was just logged"
    lines = " ".join(debrief.get("vs_last") or [])
    if "80" not in lines or "10" not in lines:
        return (f"vs_last doesn't quote 80 kg and the +10 kg change from "
                f"PROGRESS: {debrief.get('vs_last')}")
    return None


def _debrief_has_every_part(result, conn, today):
    debrief = (result.decision or {}).get("debrief") or {}
    if not (debrief.get("meaning") or "").strip():
        return "debrief has no 'meaning'"
    if not (debrief.get("next") or "").strip():
        return "debrief has no 'next'"
    return None


def _no_generic_advice(result, conn, today):
    debrief = (result.decision or {}).get("debrief") or {}
    text = ((result.reply or "") + " " +
            (debrief.get("fuel_or_rest") or "")).lower()
    for phrase in ("eat more carbs", "rest more", "great job", "stronger than expected"):
        if phrase in text:
            return f"generic filler in the reply: {phrase!r}"
    return None


def _no_debrief_for_a_question(result, conn, today):
    if (result.decision or {}).get("debrief"):
        return "a plain question got a debrief card"
    return None


SCENARIOS += [
    Scenario(
        name="debrief_quotes_real_numbers",
        about=("After a logged session the coach must compare with last "
               "time using the numbers the code computed, not a feeling."),
        message="Just finished pull. Neutral pulldown 80 kg for 3 sets of 8, then T-bar row.",
        profile=FEDERICO_PROFILE,
        sessions=[(2, "push", "done", "Incline press, shoulder press")],
        lifts=[(0, "Neutral pulldown", 80.0, 8, 3), (8, "Neutral pulldown", 70.0, 8, 3)],
        checks={
            "quotes 80 kg and +10": _debrief_uses_the_numbers,
            "meaning and next are filled": _debrief_has_every_part,
            "no generic filler": _no_generic_advice,
        },
    ),
    Scenario(
        name="no_debrief_for_a_question",
        about="A question about the plan is not a finished session.",
        message="What's on for Thursday?",
        profile=FEDERICO_PROFILE,
        sessions=[(3, "pull", "done", "Pulldowns, T-bar row")],
        checks={"no debrief card": _no_debrief_for_a_question},
    ),
]


# --- event goals -------------------------------------------------------
# Dates are relative to the day the evals run, so the phase is stable.

def _goal_in(days):
    return (date.today() + timedelta(days=days)).isoformat()


def _event_profile(days, event="Hyrox Zurich"):
    profile = dict(FEDERICO_PROFILE)
    profile["goals"] = [
        f"{event} on {_goal_in(days)}, finish in the top 25% of my division",
        "Aesthetic hypertrophy (lateral delts, upper chest, back)",
    ]
    return profile


def _knows_the_event(result, conn, today):
    text = _reply_text(result)
    needed = ["run", "sled"]
    missing = [w for w in needed if w not in text]
    if missing:
        return f"never mentions {missing}; got: {result.reply!r}"
    return None


def _names_the_phase(*words):
    def check(result, conn, today):
        text = _reply_text(result)
        if not any(w in text for w in words):
            return f"never mentions any of {list(words)}; got: {result.reply!r}"
        return None
    return check


def _no_invented_percentile_time(result, conn, today):
    import re
    text = result.reply or ""
    # A clock time such as 1:12 or 1:08:30 presented as the top-25% cut-off.
    if re.search(r"top\s*25.{0,60}\b\d:\d{2}", text, re.IGNORECASE | re.DOTALL):
        return ("states a specific top-25% time, which is UNVERIFIED in the "
                f"event notes: {text!r}")
    return None


def _total_sets_at_most(limit):
    def check(result, conn, today):
        items = ((result.decision or {}).get("today") or {}).get("exercises") or []
        total = sum(i.get("sets") or 0 for i in items)
        if total > limit:
            return f"{total} sets prescribed in a taper; expected {limit} or fewer"
        return None
    return check


def _asks_for_the_date(result, conn, today):
    if not (result.decision or {}).get("question"):
        return "an event with no date on record, and the coach didn't ask for it"
    return None


SCENARIOS += [
    Scenario(
        name="event_plan_far_out",
        about=("Hyrox in about 16 weeks. The coach has to explain what the "
               "event asks, name the phase, and plan toward it, without "
               "making up a percentile time."),
        message="I want to do a Hyrox. How should I train for it?",
        profile=_event_profile(112),
        sessions=[(2, "push", "done", "Incline press, shoulder press")],
        checks={
            "knows the format": _knows_the_event,
            "names the phase": _names_the_phase("base", "weeks"),
            "no invented top-25% time": _no_invented_percentile_time,
        },
    ),
    Scenario(
        name="event_taper",
        about=("Hyrox in 10 days is a taper: cut volume, nothing new, no "
               "heavy legs. A normal 22-set session is wrong."),
        message="Give me today's session.",
        profile=_event_profile(10),
        sessions=[(3, "legs", "done", "Smith squats, hack squat, Bulgarians")],
        checks={
            "calls it a taper": _names_the_phase("taper"),
            "volume is cut": _total_sets_at_most(14),
        },
    ),
    Scenario(
        name="event_without_a_date",
        about="A named event with no date on record: ask for the date once.",
        message="Give me today's session.",
        profile={**FEDERICO_PROFILE, "goals": ["Run a Hyrox", "Aesthetic hypertrophy"]},
        sessions=[(3, "legs", "done", "Smith squats, hack squat")],
        checks={"asks for the date": _asks_for_the_date},
    ),
]

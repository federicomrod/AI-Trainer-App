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
from datetime import date
from typing import Optional

import planner
import render
import safety
import session_corrections
import session_note_parser
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
    segments: list = None             # [{"speaker": ..., "text": ...}, ...]
    # What this turn wrote to `sessions` from the message, in words --
    # "Updated Mon (Push), Tue (Swim)." or None. Carried separately as
    # well as inside the decision because the write happens before the
    # model call: if the call then fails, the athlete still has to be
    # told what was saved. A silent write is the bug this replaced.
    saved_updates: Optional[str] = None

    def __post_init__(self):
        if self.segments is None:
            self.segments = []


def _fabricated_safety_decision():
    """A schema-shaped decision for the safety pre-check path. Nothing
    here is model output -- the model was never called -- so `why` and
    `specialist_notes` stay empty. The fixed text from
    prompts/safety-response.md is what actually gets shown; this dict
    exists so the exchange has the same shape in messages.content as a
    normal decision, for the recent-decisions briefing section later.

    `_precheck_only` isn't part of CLAUDE.md's decision schema -- it's
    an internal marker so reply_text_for() can tell this dict apart
    from a real decision when reconstructing chat history later,
    without guessing from `why` being empty."""
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
        "_precheck_only": True,
    }


def reply_text_for(decision):
    """The reply text for a decision dict, whether it's fresh off the
    model or read back out of messages.content later (chat history).
    One place that knows the mapping, so a past turn renders exactly
    the same way it did live."""
    if decision.get("_precheck_only"):
        return safety.safety_response_text()
    return render.render_reply(decision)


def segments_for(decision):
    """The same reply as reply_text_for(), split by speaker -- see
    render.render_segments(). Kept as a parallel function rather than
    changing reply_text_for()'s return shape, since reply_text_for()
    is also cli.py's plain-text path and nothing there needs to
    change."""
    if decision.get("_precheck_only"):
        return [{"speaker": render.HEAD_COACH, "text": safety.safety_response_text()}]
    return render.render_segments(decision)


def _save_message(conn, role, content):
    conn.execute(
        "INSERT INTO messages (role, content) VALUES (?, ?)", (role, content)
    )
    conn.commit()


def _attach_session_note(conn, message):
    """If this message clearly refers to a specific *other* day's
    session, write a short note onto that session's own `notes` column
    -- a real schema field that, before this, nothing ever wrote to.
    Without this, mentioning "Tuesday's run felt off" in chat was only
    ever visible by scrolling chat history; now Week view's day detail
    can show it directly. Best-effort: see session_note_parser.py."""
    found = session_note_parser.parse_session_note(conn, message, date.today().isoformat())
    if found is None:
        return
    conn.execute(
        "UPDATE sessions SET notes = ? WHERE date = ?",
        (found["note"], found["date"]),
    )
    conn.commit()


def _last_assistant_decision_today(conn):
    """The most recently saved assistant decision from today, if any
    -- used to tell a genuinely new call apart from the athlete just
    reopening the app with nothing new to say."""
    row = conn.execute(
        "SELECT content FROM messages WHERE role = 'assistant' "
        "AND date(timestamp) = date('now') ORDER BY id DESC LIMIT 1"
    ).fetchone()
    if row is None:
        return None
    try:
        return json.loads(row["content"])
    except (json.JSONDecodeError, TypeError):
        return None


SESSION_TYPES = ["push", "pull", "legs", "ride", "run", "swim", "intervals", "rest"]


def _canonical_type(type_str):
    """`today.type` isn't constrained to CLAUDE.md's fixed vocabulary
    at the schema level, so the model sometimes writes "swim" and
    sometimes "swim -- easy aerobic" for the identical call. Match on
    whichever canonical word appears, so that cosmetic phrasing doesn't
    defeat the same-call check below."""
    lowered = (type_str or "").lower()
    for canonical in SESSION_TYPES:
        if canonical in lowered:
            return canonical
    return lowered


def _same_call(a, b):
    """True when two decisions amount to the same call for today --
    same decision, same session, no plan changes on either side. Not
    a byte-for-byte compare: `why` is free prose from the model and
    varies every time even when nothing about the actual call did."""
    if a.get("decision") != b.get("decision"):
        return False
    if (a.get("plan_diff") or []) or (b.get("plan_diff") or []):
        return False
    a_today, b_today = a.get("today") or {}, b.get("today") or {}
    return (
        _canonical_type(a_today.get("type")) == _canonical_type(b_today.get("type"))
        and a_today.get("duration_min") == b_today.get("duration_min")
    )


def run_turn(conn, message, image_base64=None):
    """Run one full turn of the core loop for `message` (may be empty
    -- "just tell me today") and an optional screenshot
    (CLAUDE.md: "send the image to the model directly"). Always
    returns a TurnResult; never raises. The caller decides how to
    display it."""
    message = (message or "").strip()

    if message or image_base64:
        # The image itself isn't stored -- it's consumed by this one
        # call, same as CLAUDE.md's "send the image to the model
        # directly" implies no separate image store. Anything from it
        # worth keeping comes back through memory_to_add instead.
        _save_message(conn, "user", message or "(shared a screenshot)")

    # --- Hard safety pre-check. Runs before anything else, and skips
    # the model call entirely if it trips. ---
    if safety.check_message(message):
        decision = _fabricated_safety_decision()
        _save_message(conn, "assistant", json.dumps(decision))
        return TurnResult(
            briefing=build_briefing(conn), decision=decision,
            reply=reply_text_for(decision), safety_flagged=True,
            segments=segments_for(decision),
        )

    # --- What actually happened, before deciding what happens next. ---
    # Corrections to earlier days are written to `sessions` first, so
    # the briefing below is built from the athlete's real history
    # rather than the version the planner is about to be told is wrong.
    # Before this, a message correcting five days changed the planner's
    # answer for today and nothing else: nothing was saved, Week and
    # Progress stayed empty, and the same correction had to be repeated
    # tomorrow. See session_corrections.py.
    applied_updates = {"applied": [], "rejected": []}
    if message:
        applied_updates = session_corrections.update_sessions_from_message(
            conn, message, date.today().isoformat()
        )
        _attach_session_note(conn, message)

    saved_updates = render.saved_updates_text(
        {"_applied_updates": applied_updates}
    )

    briefing_text = build_briefing(conn)

    # --- The one model call. ---
    try:
        decision = planner.get_decision(briefing_text, message, image_base64=image_base64)
    except planner.PlannerError as e:
        return TurnResult(
            briefing=briefing_text, decision=None, reply=None,
            safety_flagged=False, error="planner_error", error_detail=str(e),
            saved_updates=saved_updates,
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
            saved_updates=saved_updates,
        )

    # A silent check (no new message, no screenshot -- Today's own
    # "just tell me today" load) that lands on the same call already
    # shown today isn't a new exchange, it's the athlete reopening the
    # app. Per coach-voice.md ("never repeat... only today changed"),
    # that gets the existing line again, not a fresh near-duplicate
    # message stacked into the conversation every time the screen
    # loads. A real message or screenshot always gets a genuine saved
    # reply, even when the call itself doesn't change.
    if not message and not image_base64:
        last = _last_assistant_decision_today(conn)
        if last is not None and _same_call(decision, last):
            return TurnResult(
                briefing=briefing_text, decision=last,
                reply=reply_text_for(last), safety_flagged=False,
                segments=segments_for(last),
            )

    # Saved inside the decision so chat history renders the same
    # confirmation later -- same internal-marker convention as
    # `_precheck_only`. render.saved_updates_text() turns it into the
    # "Updated Mon (Push), Tue (Swim)" line.
    if applied_updates["applied"] or applied_updates["rejected"]:
        decision["_applied_updates"] = applied_updates

    _save_message(conn, "assistant", json.dumps(decision))

    return TurnResult(
        briefing=briefing_text, decision=decision,
        reply=reply_text_for(decision), safety_flagged=False,
        segments=segments_for(decision), saved_updates=saved_updates,
    )

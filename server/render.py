"""
render.py — turns a validated decision dict into the text the athlete
actually sees.

The *wording* of `why` and each `specialist_notes[].text` was already
written in the coach's voice by the one model call in planner.py,
which is given prompts/coach-voice.md as part of its prompt. This file
does not call the model again — it only assembles those already-voiced
fields into the final layout, and enforces the one hard structural
rule from coach-voice.md as a safety net in case the model doesn't:
never more than two specialists in one message.
"""

from datetime import date

MAX_SPECIALISTS = 2

# The voice that reports what was written to the database, as distinct
# from the coach's own words. See saved_updates_text().
LOG = "log"

COACH_LABELS = {
    "strength": "Strength",
    "endurance": "Endurance",
    "recovery": "Recovery",
}


def _day_label(iso_date):
    """"2026-09-14" -> "Mon". Falls back to the raw date rather than
    raising: this is display text, not a calculation."""
    try:
        return date.fromisoformat(iso_date).strftime("%a")
    except (ValueError, TypeError):
        return iso_date


def saved_updates_text(decision):
    """One line naming every past day this turn actually wrote to the
    sessions table, or None if it wrote none.

    `_applied_updates` is put there by coach.py (see
    session_corrections.py) and is not part of CLAUDE.md's decision
    schema -- same convention as `_precheck_only`, an internal marker
    saved alongside the decision so chat history renders identically
    later. Shown because the alternative is what used to happen: the
    coach sounded like it had taken the correction on board and
    nothing was saved, with no way for the athlete to tell.
    """
    updates = decision.get("_applied_updates") or {}
    applied = updates.get("applied") or []
    rejected = updates.get("rejected") or []
    parts = []
    for entry in applied:
        detail = (entry.get("type") or "").capitalize()
        if entry.get("duration_min"):
            detail += f", {entry['duration_min']} min"
        if entry.get("status") and entry["status"] != "done":
            detail += f", {entry['status']}"
        parts.append(f"{_day_label(entry.get('date'))} ({detail})")

    lines = []
    if parts:
        lines.append("Updated " + ", ".join(parts) + ".")
    if rejected:
        # Named, not swallowed: an athlete who said something about a
        # day should never have to guess whether it landed.
        lines.append(
            "Couldn't save: " + "; ".join(rejected)
            + ". Tell me again with the day and what you did."
        )
    return "\n".join(lines) or None


def unresolved_question(updates):
    """The question to put to the athlete about days that were read
    but not written, or None when there are none.

    Deliberately quotes their own words back: the whole reason a day
    ends up here is that the transcript may not be what they said, so
    "I heard 'the pool'" is the part that lets them spot it.
    """
    unresolved = (updates or {}).get("unresolved") or []
    if not unresolved:
        return None
    lines = []
    for entry in unresolved:
        options = [o.capitalize() for o in entry.get("options") or []]
        choice = " or ".join(options) if options else "which session it was"
        heard = entry.get("heard")
        quoted = f' I heard "{heard}" --' if heard else ""
        lines.append(
            f"{_day_label(entry.get('date'))}:{quoted} was that {choice}?"
        )
    lead = ("I haven't saved that day yet." if len(lines) == 1
            else "I haven't saved those days yet.")
    return "\n".join(lines) + " " + lead


def render_reply(decision):
    """Return the plain-text coach reply for an already-validated
    decision (the safety pre-check path in cli.py never reaches this —
    it renders the fixed prompts/safety-response.md text directly)."""
    # plan_diff is deliberately not here. It's structured data -- dates,
    # session types, an arrow -- and printing it produced lines like
    # "2026-09-20: Unplanned -> Endurance ride — …" in the athlete's
    # chat. The Week view shows plan changes properly; in conversation
    # the coach says so in `why`, in words. (cli.py prints the full
    # decision JSON separately, so the diff is still visible there.)
    lines = []
    # First, because it's the answer to "did that get saved?" -- and
    # a fact, not an opinion.
    saved = saved_updates_text(decision)
    if saved:
        lines.append(saved + "\n")
    lines.append(decision.get("why", "").strip())

    notes = decision.get("specialist_notes") or []
    if len(notes) > MAX_SPECIALISTS:
        notes = notes[:MAX_SPECIALISTS]

    for note in notes:
        text = (note.get("text") or "").strip()
        if not text:
            continue
        label = COACH_LABELS.get(note.get("coach", ""), note.get("coach", "Coach"))
        # Plain "Label:", not Markdown bold: the app shows this string
        # as-is, so ** would appear literally.
        lines.append(f"\n{label}: {text}")

    if decision.get("question"):
        lines.append(f"\n{decision['question']}")

    return "\n".join(l for l in lines if l)


HEAD_COACH = "head_coach"


def render_segments(decision):
    """Same content as render_reply(), split into one segment per
    speaker instead of flattened into a single string with inline
    **Label:** markers. Lets the UI show each voice as its own message
    -- a real specialist chiming in should look like someone else
    speaking, not a bold heading in the middle of Head Coach's own
    paragraph. render_reply() stays as the plain-text form (cli.py,
    and anything else that just wants one block of text); this is an
    additional view of the same decision, not a replacement."""
    segments = []

    saved = saved_updates_text(decision)
    if saved:
        segments.append({"speaker": LOG, "text": saved})

    # Only `why` -- no plan_diff lines. See render_reply().
    head_text = decision.get("why", "").strip()
    if head_text:
        segments.append({"speaker": HEAD_COACH, "text": head_text})

    notes = decision.get("specialist_notes") or []
    if len(notes) > MAX_SPECIALISTS:
        notes = notes[:MAX_SPECIALISTS]
    for note in notes:
        text = (note.get("text") or "").strip()
        if not text:
            continue
        segments.append({"speaker": note.get("coach") or "coach", "text": text})

    if decision.get("question"):
        segments.append({"speaker": HEAD_COACH, "text": decision["question"]})

    return segments

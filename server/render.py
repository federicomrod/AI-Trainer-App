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

MAX_SPECIALISTS = 2

COACH_LABELS = {
    "strength": "Strength",
    "endurance": "Endurance",
    "recovery": "Recovery",
}


def render_reply(decision):
    """Return the plain-text coach reply for an already-validated
    decision (the safety pre-check path in cli.py never reaches this —
    it renders the fixed prompts/safety-response.md text directly)."""
    lines = [decision.get("why", "").strip()]

    notes = decision.get("specialist_notes") or []
    if len(notes) > MAX_SPECIALISTS:
        notes = notes[:MAX_SPECIALISTS]

    for note in notes:
        text = (note.get("text") or "").strip()
        if not text:
            continue
        label = COACH_LABELS.get(note.get("coach", ""), note.get("coach", "Coach"))
        lines.append(f"\n**{label}:** {text}")

    if decision.get("question"):
        lines.append(f"\n{decision['question']}")

    return "\n".join(l for l in lines if l)

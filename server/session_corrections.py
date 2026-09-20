"""
session_corrections.py — when a message says what actually happened on
earlier days, write it to the `sessions` table.

This is the path that was missing. The planner call reads a message
like "Monday push, Tuesday the pool, Wednesday pull instead of rest"
and quite correctly uses it for today's decision, but CLAUDE.md's
decision schema has nowhere to record five earlier days, so nothing
was ever saved: Week and Progress stayed empty, and the correction had
to be repeated every day. A bigger prompt can't fix that -- there was
no code that wrote the rows.

So: one small extraction call (same shape as lift_parser.py and
session_note_parser.py, prompt in prompts/session-corrections.md),
then every row it returns is checked here and applied in plain SQL.
What was actually written comes back to the caller, which is what lets
the coach's reply name the days instead of claiming something
unverifiable. Anything rejected is reported too -- a correction that
quietly vanishes is the bug this file exists to fix.

Nothing is written on a shaky read. A voice note saying "pull" comes
back from transcription as "the pool" often enough that it happened on
the first real week of use, and `swim` is a perfectly valid session
type, so the enum alone never catches it -- the row was saved, wrong,
in silence. Now a day is only written when the reading is confident;
anything ambiguous is asked about instead. See _confidence_problem().

No eighth table: this writes to `sessions`, the same table logging and
planning already use.
"""

import json
import re
from datetime import date, timedelta
from pathlib import Path

import planner
from providers import PlannerError

PROMPT_PATH = Path(__file__).parent.parent / "prompts" / "session-corrections.md"

# CLAUDE.md's session types, and the sessions.type CHECK constraint.
SESSION_TYPES = ("push", "pull", "legs", "ride", "run", "swim",
                 "intervals", "rest")

# A correction describes something that already happened, so
# 'planned' -- valid in the table, for a future day -- is not accepted
# here.
CORRECTION_STATUSES = ("done", "partial", "skipped", "unplanned")

# How far back a correction may reach. Two weeks is what the briefing
# shows and what someone can actually remember day by day; a date
# outside it is far likelier to be a mis-parse than a real memory.
WINDOW_DAYS = 14

SCHEMA = {
    "type": "object",
    "properties": {
        "corrections": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "date": {"type": "string"},
                    "type": {"type": "string", "enum": list(SESSION_TYPES)},
                    "status": {"type": "string", "enum": list(CORRECTION_STATUSES)},
                    "summary": {"type": "string"},
                    "duration_min": {"type": ["integer", "null"]},
                    # How sure the reading of *this day* is. Only
                    # "high" is written; see _confidence_problem().
                    "confidence": {
                        "type": "string",
                        "enum": ["high", "medium", "low"],
                    },
                    # The other session type this could be, when the
                    # wording could honestly be read two ways.
                    "alternative": {
                        "type": ["string", "null"],
                        "enum": list(SESSION_TYPES) + [None],
                    },
                    # The athlete's own words about this day, quoted
                    # back when asking them to confirm it.
                    "heard": {"type": "string"},
                },
                "required": ["date", "type", "status", "summary",
                             "duration_min", "confidence", "alternative",
                             "heard"],
            },
        }
    },
    "required": ["corrections"],
}


# Sound-alikes that transcription genuinely confuses, and the words
# that settle each one. Kept in code rather than left to the model's
# judgement: this is the exact failure that saved a strength day as a
# swim, and a deterministic rule is testable (see evals/).
#
# "pull" and "pool" are the pair that actually bit. Either word, on its
# own, is not enough to write a day -- but "40 lengths" or "3x10 lat
# pulldown" settles it immediately, and so does naming both ("pull, not
# the pool").
_POOL = re.compile(r"\bpool\b", re.IGNORECASE)
_PULL = re.compile(r"\bpull(s|ed|ing)?\b", re.IGNORECASE)
_SWIM_EVIDENCE = re.compile(
    r"\b(swim\w*|swam|swum|length|lengths|lap|laps|lane|freestyle|crawl|"
    r"stroke|front\s+crawl|breaststroke|goggles|\d+\s*m\b)\b",
    re.IGNORECASE,
)
_PULL_EVIDENCE = re.compile(
    r"\b(rep|reps|set|sets|kg|lbs?|lat|lats|row|rows|rowing|chin|chins|"
    r"chin-?ups?|pull-?ups?|pulldowns?|curl|curls|deadlift\w*|barbell|"
    r"dumbbell|cable|back)\b",
    re.IGNORECASE,
)


def _sounds_ambiguous(text):
    """True when the words for a day rest on "pull"/"pool" alone.

    Exactly one of the two appears (naming both means the athlete is
    drawing the distinction themselves) and nothing else in the
    sentence says which kind of session it was.
    """
    if not text:
        return False
    mentions_pool = bool(_POOL.search(text))
    mentions_pull = bool(_PULL.search(text))
    if mentions_pool == mentions_pull:  # neither, or both
        return False
    return not (_SWIM_EVIDENCE.search(text) or _PULL_EVIDENCE.search(text))


def _confidence_problem(clean, correction):
    """Why this day shouldn't be written yet, or None to write it.

    Two gates. The model's own `confidence`, and the sound-alike rule
    above, which catches the case the model has no way to see: the
    transcript reads perfectly well, it just isn't what was said.
    """
    text = " ".join(
        part for part in (correction.get("heard"), clean.get("summary")) if part
    )
    if clean["type"] in ("swim", "pull") and _sounds_ambiguous(text):
        return ("swim", "pull")

    confidence = (correction.get("confidence") or "high").strip().lower()
    if confidence != "high":
        alternative = (correction.get("alternative") or "").strip().lower()
        if alternative in SESSION_TYPES and alternative != clean["type"]:
            return (clean["type"], alternative)
        return (clean["type"], None)
    return None


def _recent_days(conn, today):
    """The window the model may correct, each with whatever is already
    on record. Given as explicit dates *with* weekday names so day
    names never have to be worked out from arithmetic."""
    rows = {
        r["date"]: r
        for r in conn.execute(
            "SELECT date, type, status, actual_summary FROM sessions "
            "WHERE date >= ? AND date <= ? ORDER BY date",
            ((today - timedelta(days=WINDOW_DAYS)).isoformat(), today.isoformat()),
        ).fetchall()
    }
    lines = []
    for offset in range(WINDOW_DAYS, -1, -1):
        day = today - timedelta(days=offset)
        iso = day.isoformat()
        label = f"{iso} ({day.strftime('%a')})"
        row = rows.get(iso)
        if row is None:
            lines.append(f"{label}: nothing on record")
        else:
            detail = row["actual_summary"] or row["type"]
            lines.append(f"{label}: {row['type']} / {row['status']} — {detail}")
    return lines


CONVERSATION_LINES = 4


def _recent_conversation(conn):
    """The last few turns, so an answer to a question makes sense on
    its own. Without this, "it was pull" -- the reply to the coach
    asking which session Tuesday was -- carries no date and nothing
    can be done with it."""
    rows = conn.execute(
        "SELECT role, content FROM messages ORDER BY id DESC LIMIT ?",
        (CONVERSATION_LINES,),
    ).fetchall()
    lines = []
    for row in reversed(rows):
        text = row["content"] or ""
        if row["role"] == "assistant":
            # Stored as the decision JSON; the athlete saw `why` and
            # `question`, and those are the parts that give a bare
            # answer its meaning.
            try:
                decision = json.loads(text)
            except (json.JSONDecodeError, TypeError):
                continue
            text = " ".join(
                part for part in (decision.get("why"), decision.get("question"))
                if part
            )
        if text.strip():
            lines.append(f"{row['role']}: {text.strip()}")
    return "\n".join(lines) or "(nothing yet)"


def parse_corrections(conn, message, today_iso):
    """Ask the model which past days this message states something
    definite about. Best-effort: returns [] on any failure, exactly
    like lift_parser.py, so this never takes the turn down with it."""
    message = (message or "").strip()
    if not message:
        return []

    today = date.fromisoformat(today_iso)
    user_content = (
        f"TODAY: {today_iso} ({today.strftime('%A')})\n\n"
        f"RECENT DAYS (what's on record now):\n" + "\n".join(_recent_days(conn, today))
        + f"\n\nLAST FEW MESSAGES:\n{_recent_conversation(conn)}"
        + f"\n\nMESSAGE:\n{message}"
    )

    try:
        provider = planner.active_provider()
        result = provider.get_structured(PROMPT_PATH.read_text(), user_content, SCHEMA)
    except PlannerError:
        return []
    corrections = result.get("corrections")
    return corrections if isinstance(corrections, list) else []


def _check(correction, today):
    """Either a clean correction or a reason it can't be applied. The
    model is told the rules; this enforces them, because a bad row
    here becomes part of the athlete's training history and feeds
    every future briefing."""
    if not isinstance(correction, dict):
        return None, "not a correction"

    raw_date = (correction.get("date") or "").strip()
    try:
        when = date.fromisoformat(raw_date)
    except ValueError:
        return None, f"unreadable date {raw_date!r}"
    if when > today:
        return None, f"{raw_date} is in the future"
    if when < today - timedelta(days=WINDOW_DAYS):
        return None, f"{raw_date} is more than {WINDOW_DAYS} days ago"

    session_type = (correction.get("type") or "").strip().lower()
    if session_type not in SESSION_TYPES:
        return None, f"unknown session type {session_type!r}"

    status = (correction.get("status") or "").strip().lower()
    if status not in CORRECTION_STATUSES:
        return None, f"unknown status {status!r}"

    duration = correction.get("duration_min")
    if duration is not None:
        try:
            duration = int(duration)
        except (TypeError, ValueError):
            duration = None
        else:
            # A session measured in days, or in negative time, is a
            # parse gone wrong rather than a real number.
            if not 0 < duration <= 600:
                duration = None

    return {
        "date": raw_date,
        "type": session_type,
        "status": status,
        "summary": (correction.get("summary") or "").strip() or None,
        "duration_min": duration,
        "heard": (correction.get("heard") or "").strip() or None,
    }, None


def apply_corrections(conn, corrections, today_iso, already_asked=()):
    """Write the confident corrections to `sessions` and return
    ({"applied": [...], "rejected": [...], "unresolved": [...]}).

    One row per date: a day already on record is updated in place --
    the whole point is to replace what the plan said with what
    happened -- and a day with nothing on record gets a new row.

    A day whose reading isn't confident is *not* written. It comes
    back in "unresolved" instead, for the coach to ask about. All
    three lists come back so the reply can name what was saved, ask
    about what wasn't, and admit what couldn't be read at all.

    `already_asked` is the dates the previous turn asked about. This
    message is the answer, so those days are taken at their word and
    never questioned a second time -- without it, "it was pull" trips
    the same sound-alike rule that raised the question, and the coach
    asks the same thing forever. Caught by the eval scenario
    answer_resolves_the_question.
    """
    today = date.fromisoformat(today_iso)
    applied, rejected, unresolved = [], [], []
    seen = {}

    for correction in corrections or []:
        clean, problem = _check(correction, today)
        if clean is None:
            rejected.append(problem)
            continue
        options = (None if clean["date"] in already_asked
                   else _confidence_problem(clean, correction))
        if options is not None:
            unresolved.append({
                "date": clean["date"],
                "heard": clean["heard"] or clean["summary"],
                "options": [o for o in options if o],
            })
            continue
        # Last mention of a date wins, so one message can't produce two
        # rows for one day.
        seen[clean["date"]] = clean

    for clean in sorted(seen.values(), key=lambda c: c["date"]):
        row = conn.execute(
            "SELECT id FROM sessions WHERE date = ? ORDER BY id LIMIT 1",
            (clean["date"],),
        ).fetchone()
        if row is None:
            conn.execute(
                "INSERT INTO sessions "
                "(date, type, status, actual_summary, duration_min, source) "
                "VALUES (?, ?, ?, ?, ?, 'manual')",
                (clean["date"], clean["type"], clean["status"],
                 clean["summary"], clean["duration_min"]),
            )
        else:
            # duration_min only when one was given: a correction that
            # says nothing about length shouldn't erase a length that
            # was already recorded.
            conn.execute(
                "UPDATE sessions SET type = ?, status = ?, actual_summary = ?, "
                "duration_min = COALESCE(?, duration_min), source = 'manual' "
                "WHERE id = ?",
                (clean["type"], clean["status"], clean["summary"],
                 clean["duration_min"], row["id"]),
            )
        applied.append(clean)

    if applied:
        conn.commit()
    unresolved.sort(key=lambda u: u["date"])
    return {"applied": applied, "rejected": rejected, "unresolved": unresolved}


def dates_already_asked(conn):
    """The days the last reply asked the athlete to confirm."""
    row = conn.execute(
        "SELECT content FROM messages WHERE role = 'assistant' "
        "ORDER BY id DESC LIMIT 1"
    ).fetchone()
    if row is None:
        return set()
    try:
        decision = json.loads(row["content"])
    except (json.JSONDecodeError, TypeError):
        return set()
    unresolved = (decision.get("_applied_updates") or {}).get("unresolved") or []
    return {entry.get("date") for entry in unresolved if entry.get("date")}


def update_sessions_from_message(conn, message, today_iso):
    """The whole path in one call, for coach.py: extract, check, write.
    Returns the same dict as apply_corrections()."""
    already_asked = dates_already_asked(conn)
    corrections = parse_corrections(conn, message, today_iso)
    if not corrections:
        return {"applied": [], "rejected": [], "unresolved": []}
    return apply_corrections(conn, corrections, today_iso, already_asked)

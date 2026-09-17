"""
api.py — the local HTTP server the iOS app talks to.

CLAUDE.md's tech decisions are explicit that the app can't hold API
keys, so something has to sit between the phone and OpenAI/Anthropic.
This is that something, and it is intentionally the thinnest possible
wrapper: every real decision (briefing, safety, the model call,
validation, rendering) still lives in coach.py and the modules it
calls. This file is routing and JSON shaping only.

Run it with:
    server/.venv/bin/uvicorn api:app --reload --host 0.0.0.0 --port 8000

--host 0.0.0.0 makes it reachable from a physical iPhone on the same
Wi-Fi, at http://<your-mac's-LAN-IP>:8000. The Simulator can also just
use http://127.0.0.1:8000, which is what the app defaults to.

No auth, no HTTPS. This is a single-user local dev server for one
person's own phone on their own network — revisit before it's anything
more than that.
"""

import json
from datetime import date as date_type
from typing import Dict, List, Literal, Optional

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

import checkin as checkin_module
import coach
import healthkit_import
import log_session
import progress as progress_module
import week as week_module
from briefing import build_briefing
from db import get_connection

app = FastAPI(title="Hybrid Coach")


class TurnRequest(BaseModel):
    message: str = ""
    image_base64: Optional[str] = None


class MessageSegment(BaseModel):
    speaker: str
    text: str


class TurnResponse(BaseModel):
    briefing: str
    decision: Optional[dict]
    reply: Optional[str]
    safety_flagged: bool
    error: Optional[str]
    error_detail: Optional[str]
    segments: List[MessageSegment] = []


class ChatMessage(BaseModel):
    id: int
    role: str
    text: str
    timestamp: str
    segments: List[MessageSegment] = []


class CheckInRequest(BaseModel):
    sleep: Literal["poor", "normal", "good"]
    energy: int = Field(ge=1, le=5)
    soreness: Dict[str, str] = {}
    note: Optional[str] = None


class CheckInResponse(BaseModel):
    id: int
    date: str
    sleep: str
    energy: int
    soreness: Dict[str, str]
    note: Optional[str]


class RelevantExercise(BaseModel):
    name: str
    last_date: Optional[str]
    last_weight: Optional[float]
    last_reps: Optional[int]
    last_sets: Optional[int]


class LogContextResponse(BaseModel):
    date: str
    type: str
    status: str
    planned_summary: Optional[str]
    relevant_exercises: List[RelevantExercise]


class LiftEntry(BaseModel):
    exercise_name: str
    weight: Optional[float] = None
    reps: Optional[int] = None
    sets: Optional[int] = None
    note: Optional[str] = None


class LogSessionRequest(BaseModel):
    date: Optional[str] = None  # defaults to today, server-side
    status: Literal["done", "partial", "skipped"]
    notes: Optional[str] = None
    lifts: List[LiftEntry] = []


class LogSessionResponse(BaseModel):
    date: str
    type: str
    status: str
    actual_summary: Optional[str]
    lifts_recorded: List[LiftEntry] = []


class GoalsResponse(BaseModel):
    goals: List[str]


class GoalsRequest(BaseModel):
    goals: List[str]


class LiftPoint(BaseModel):
    date: str
    weight: float


class WeeklySessionCount(BaseModel):
    week_start: str
    count: int


class LiftPR(BaseModel):
    exercise_name: str
    max_weight: float


class ProgressStats(BaseModel):
    lift_prs: List[LiftPR]
    longest_ride_min: Optional[int]
    longest_swim_min: Optional[int]
    sessions_this_week: int


class ProgressResponse(BaseModel):
    lifts: Dict[str, List[LiftPoint]]
    weekly_sessions: List[WeeklySessionCount]
    stats: ProgressStats


class HealthKitWorkout(BaseModel):
    date: str
    hk_type: str
    duration_min: Optional[int] = None
    summary: Optional[str] = None


class HealthKitImportRequest(BaseModel):
    workouts: List[HealthKitWorkout] = []


class HealthKitImportResponse(BaseModel):
    imported: int
    skipped: int


class WeekDay(BaseModel):
    date: str
    weekday: str
    is_today: bool
    type: str
    status: str
    planned_summary: Optional[str]
    actual_summary: Optional[str]
    duration_min: Optional[int]
    moved_to: Optional[str]
    moved_reason: Optional[str]


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/briefing")
def get_briefing():
    """Just the briefing, with no message and no model call -- useful
    for a screen that wants to show current state without asking the
    coach anything yet."""
    conn = get_connection()
    return {"briefing": build_briefing(conn)}


@app.get("/messages", response_model=List[ChatMessage])
def get_messages():
    """The whole conversation, for Coach chat. A user row's `content`
    is already display text; an assistant row's `content` is the
    decision JSON that was actually saved (see coach.py), so it's
    rendered here through the same reply_text_for() that a live turn
    uses -- a past message reads exactly the way it did when it was
    new. A row that somehow isn't valid JSON falls back to showing its
    raw content rather than dropping it silently."""
    conn = get_connection()
    rows = conn.execute(
        "SELECT id, role, content, timestamp FROM messages ORDER BY id ASC"
    ).fetchall()

    out = []
    for row in rows:
        text = row["content"]
        segments = []
        if row["role"] == "assistant":
            try:
                decision = json.loads(row["content"])
                text = coach.reply_text_for(decision)
                segments = coach.segments_for(decision)
            except (json.JSONDecodeError, TypeError):
                pass
        out.append(ChatMessage(
            id=row["id"], role=row["role"], text=text,
            timestamp=row["timestamp"], segments=segments,
        ))
    return out


@app.get("/week", response_model=List[WeekDay])
def get_week():
    """The current calendar week (Mon-Sun), every session tagged with
    whether a decision moved it and why. See week.py."""
    conn = get_connection()
    return week_module.get_week(conn)


@app.post("/checkin", response_model=CheckInResponse)
def post_checkin(req: CheckInRequest):
    """Save (or update) today's check-in. See checkin.py."""
    conn = get_connection()
    return checkin_module.save_checkin(
        conn, req.sleep, req.energy, req.soreness, req.note
    )


@app.get("/log_context", response_model=LogContextResponse)
def get_log_context(date: Optional[str] = None):
    """What the logging screen needs: the scheduled type/summary for
    `date` (defaults to today) and which tracked exercises, if any,
    are worth prompting for. See log_session.py."""
    conn = get_connection()
    context = log_session.get_log_context(conn, date)
    if context is None:
        raise HTTPException(404, f"No session scheduled for {date or 'today'}")
    return context


@app.post("/log_session", response_model=LogSessionResponse)
def post_log_session(req: LogSessionRequest):
    """Record what actually happened: done/partial/skipped, optional
    notes, and any tracked-exercise numbers the athlete gave."""
    conn = get_connection()
    try:
        return log_session.save_log(
            conn, req.date or date_type.today().isoformat(),
            req.status, req.notes,
            [lift.model_dump() for lift in req.lifts],
        )
    except ValueError as e:
        raise HTTPException(404, str(e))


@app.get("/goals", response_model=GoalsResponse)
def get_goals():
    """Goals in priority order (list order = priority -- see
    CLAUDE.md's profile table: no separate priority field)."""
    conn = get_connection()
    row = conn.execute("SELECT goals_json FROM profile WHERE id = 1").fetchone()
    return {"goals": json.loads(row["goals_json"]) if row else []}


@app.put("/goals", response_model=GoalsResponse)
def put_goals(req: GoalsRequest):
    """Replace the goals list wholesale, in the given order. The
    client sends the full reordered/edited list rather than a
    move/insert/delete op -- simplest possible contract for a screen
    that's just "view and edit a list"."""
    conn = get_connection()
    conn.execute(
        "UPDATE profile SET goals_json = ? WHERE id = 1",
        (json.dumps(req.goals),),
    )
    conn.commit()
    return {"goals": req.goals}


@app.get("/progress", response_model=ProgressResponse)
def get_progress():
    """Real trend data, straight out of lifts and sessions -- no
    scores, no streaks. See progress.py."""
    conn = get_connection()
    return progress_module.get_progress(conn)


@app.post("/healthkit_import", response_model=HealthKitImportResponse)
def post_healthkit_import(req: HealthKitImportRequest):
    """Import recent Apple Health workouts (Garmin/Whoop/Watch, since
    those write into HealthKit rather than exposing their own API --
    see CLAUDE.md's tech decisions). See healthkit_import.py for what
    gets imported vs. skipped."""
    conn = get_connection()
    return healthkit_import.import_workouts(
        conn, [w.model_dump() for w in req.workouts]
    )


@app.post("/turn", response_model=TurnResponse)
def post_turn(req: TurnRequest):
    """The whole core loop for one message (may be empty)."""
    conn = get_connection()
    result = coach.run_turn(conn, req.message, image_base64=req.image_base64)
    return TurnResponse(
        briefing=result.briefing,
        decision=result.decision,
        reply=result.reply,
        safety_flagged=result.safety_flagged,
        error=result.error,
        error_detail=result.error_detail,
        segments=result.segments,
    )

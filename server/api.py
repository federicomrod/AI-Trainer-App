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
from typing import Dict, List, Literal, Optional

from fastapi import FastAPI
from pydantic import BaseModel, Field

import checkin as checkin_module
import coach
import week as week_module
from briefing import build_briefing
from db import get_connection

app = FastAPI(title="Hybrid Coach")


class TurnRequest(BaseModel):
    message: str = ""


class TurnResponse(BaseModel):
    briefing: str
    decision: Optional[dict]
    reply: Optional[str]
    safety_flagged: bool
    error: Optional[str]
    error_detail: Optional[str]


class ChatMessage(BaseModel):
    id: int
    role: str
    text: str
    timestamp: str


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
        if row["role"] == "assistant":
            try:
                text = coach.reply_text_for(json.loads(row["content"]))
            except (json.JSONDecodeError, TypeError):
                pass
        out.append(ChatMessage(
            id=row["id"], role=row["role"], text=text,
            timestamp=row["timestamp"],
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


@app.post("/turn", response_model=TurnResponse)
def post_turn(req: TurnRequest):
    """The whole core loop for one message (may be empty)."""
    conn = get_connection()
    result = coach.run_turn(conn, req.message)
    return TurnResponse(
        briefing=result.briefing,
        decision=result.decision,
        reply=result.reply,
        safety_flagged=result.safety_flagged,
        error=result.error,
        error_detail=result.error_detail,
    )

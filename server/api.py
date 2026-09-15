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

from typing import Optional

from fastapi import FastAPI
from pydantic import BaseModel

import coach
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

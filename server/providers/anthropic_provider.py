"""
anthropic_provider.py — the Anthropic (Claude) implementation of the
one planner call. Forces the decision JSON shape via tool use, so the
model can't hand back free text or a malformed shape.
"""

import os

import anthropic

from . import PlannerError

DEFAULT_MODEL = "claude-sonnet-5"
MAX_TOKENS = 2000


def get_decision(system_prompt, user_content, schema):
    model = os.environ.get("ANTHROPIC_MODEL", DEFAULT_MODEL)
    client = anthropic.Anthropic()  # reads ANTHROPIC_API_KEY

    try:
        response = client.messages.create(
            model=model,
            max_tokens=MAX_TOKENS,
            system=system_prompt,
            tools=[{
                "name": "submit_decision",
                "description": "Submit today's training decision.",
                "input_schema": schema,
            }],
            tool_choice={"type": "tool", "name": "submit_decision"},
            messages=[{"role": "user", "content": user_content}],
        )
    except anthropic.APIError as e:
        raise PlannerError(f"Anthropic call failed: {e}") from e

    for block in response.content:
        if block.type == "tool_use" and block.name == "submit_decision":
            return block.input

    raise PlannerError("Anthropic response had no submit_decision tool call.")

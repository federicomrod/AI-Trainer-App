"""
anthropic_provider.py — the Anthropic (Claude) implementation of the
one structured-output model call (see providers/__init__.py). Forces
the response into the caller's given JSON shape via tool use, so the
model can't hand back free text or a malformed shape.
"""

import os

import anthropic

from . import PlannerError

DEFAULT_MODEL = "claude-sonnet-5"
MAX_TOKENS = 2000


def get_structured(system_prompt, user_content, schema, image_base64=None):
    model = os.environ.get("ANTHROPIC_MODEL", DEFAULT_MODEL)
    client = anthropic.Anthropic()  # reads ANTHROPIC_API_KEY

    if image_base64:
        # Anthropic's own guidance: image block(s) before the text
        # they relate to.
        message_content = [
            {"type": "image",
             "source": {"type": "base64", "media_type": "image/jpeg",
                        "data": image_base64}},
            {"type": "text", "text": user_content},
        ]
    else:
        message_content = user_content

    try:
        response = client.messages.create(
            model=model,
            max_tokens=MAX_TOKENS,
            system=system_prompt,
            tools=[{
                "name": "submit_response",
                "description": "Submit the structured response.",
                "input_schema": schema,
            }],
            tool_choice={"type": "tool", "name": "submit_response"},
            messages=[{"role": "user", "content": message_content}],
        )
    except anthropic.APIError as e:
        raise PlannerError(f"Anthropic call failed: {e}") from e

    for block in response.content:
        if block.type == "tool_use" and block.name == "submit_response":
            return block.input

    raise PlannerError("Anthropic response had no submit_response tool call.")

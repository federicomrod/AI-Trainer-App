"""
openai_provider.py — the OpenAI implementation of the one structured-
output model call (see providers/__init__.py). Uses Structured Outputs
(response_format: json_schema, strict mode): the API itself guarantees
the response matches the given schema exactly, so there's no parsing
free text and no hoping the model formatted things right.

Strict mode has one requirement callers' schemas don't bother with,
since it's an OpenAI-specific technicality rather than part of any
particular schema's actual shape: every object node needs
"additionalProperties": false. _strict() adds that recursively on a
copy, rather than baking an OpenAI-only detail into every schema that
gets handed to this provider.
"""

import copy
import json
import os

import openai
from openai import OpenAI

from . import PlannerError

DEFAULT_MODEL = "gpt-5"


def _strict(schema):
    """Deep copy of `schema` with additionalProperties: false added to
    every object node, as OpenAI's strict structured-output mode
    requires."""
    schema = copy.deepcopy(schema)

    def walk(node):
        if isinstance(node, dict):
            if node.get("type") == "object":
                node["additionalProperties"] = False
            for value in node.values():
                walk(value)
        elif isinstance(node, list):
            for item in node:
                walk(item)

    walk(schema)
    return schema


def get_structured(system_prompt, user_content, schema, image_base64=None):
    model = os.environ.get("OPENAI_MODEL", DEFAULT_MODEL)
    client = OpenAI()  # reads OPENAI_API_KEY

    if image_base64:
        message_content = [
            {"type": "text", "text": user_content},
            {"type": "image_url",
             "image_url": {"url": f"data:image/jpeg;base64,{image_base64}"}},
        ]
    else:
        message_content = user_content

    try:
        response = client.chat.completions.create(
            model=model,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": message_content},
            ],
            response_format={
                "type": "json_schema",
                "json_schema": {
                    "name": "submit_response",
                    "schema": _strict(schema),
                    "strict": True,
                },
            },
            # gpt-5 is a reasoning model: reasoning tokens are billed out
            # of max_completion_tokens before any visible content is
            # written. At the old cap (2000) reasoning alone could burn
            # the whole budget and leave nothing for the JSON answer,
            # returning empty content with finish_reason "length". Low
            # effort keeps reasoning short for this task (a bounded
            # decision, not open-ended problem solving) and the larger
            # cap leaves room for a full decision even when effort runs
            # a bit long.
            reasoning_effort="low",
            max_completion_tokens=4000,
        )
    except openai.OpenAIError as e:
        raise PlannerError(f"OpenAI call failed: {e}") from e

    message = response.choices[0].message
    if getattr(message, "refusal", None):
        raise PlannerError(f"OpenAI refused the request: {message.refusal}")
    if not message.content:
        raise PlannerError("OpenAI response had no content.")

    try:
        return json.loads(message.content)
    except json.JSONDecodeError as e:
        raise PlannerError(f"OpenAI response was not valid JSON: {e}") from e

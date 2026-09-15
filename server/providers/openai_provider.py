"""
openai_provider.py — the OpenAI implementation of the one planner
call. Uses Structured Outputs (response_format: json_schema, strict
mode): the API itself guarantees the response matches the decision
schema exactly, so there's no parsing free text and no hoping the
model formatted things right.

Strict mode has one requirement the shared schema in planner.py
doesn't bother with, since it's an OpenAI-specific technicality rather
than part of the actual decision shape: every object node needs
"additionalProperties": false. _strict() adds that recursively on a
copy, rather than baking an OpenAI-only detail into the schema
planner.py hands to every provider.
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


def get_decision(system_prompt, user_content, schema):
    model = os.environ.get("OPENAI_MODEL", DEFAULT_MODEL)
    client = OpenAI()  # reads OPENAI_API_KEY

    try:
        response = client.chat.completions.create(
            model=model,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_content},
            ],
            response_format={
                "type": "json_schema",
                "json_schema": {
                    "name": "submit_decision",
                    "schema": _strict(schema),
                    "strict": True,
                },
            },
            max_completion_tokens=2000,
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

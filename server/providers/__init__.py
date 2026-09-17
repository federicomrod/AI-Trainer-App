"""
providers/ — one small module per model provider. Each exposes exactly
one function:

    get_structured(system_prompt: str, user_content: str, schema: dict,
                    image_base64: str | None = None) -> dict

which makes one structured-output model call -- forcing the response
into the shape of `schema` -- and returns it as a plain dict, raising
PlannerError on any failure. Every caller supplies its own prompt and
schema (planner.py's one decision call, lift_parser.py's smaller lift-
extraction call); this module has no opinion on what's being asked
for. planner.py picks which module to use from the
HYBRID_COACH_PROVIDER config value, so adding a third provider later
means adding a module here and one line in planner.py's PROVIDERS map
-- never touching the prompt-loading or validation code.
"""


class PlannerError(Exception):
    """The model call failed, or its response wasn't usable. Never
    caught-and-retried automatically by a provider or by planner.py."""

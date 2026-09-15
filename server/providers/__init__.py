"""
providers/ — one small module per model provider. Each exposes exactly
one function:

    get_decision(system_prompt: str, user_content: str, schema: dict) -> dict

which makes the one planner call and returns the decision as a plain
dict, raising PlannerError on any failure. planner.py picks which
module to use from the HYBRID_COACH_PROVIDER config value, so adding a
third provider later means adding a module here and one line in
planner.py's PROVIDERS map -- never touching the prompt-loading or
validation code.
"""


class PlannerError(Exception):
    """The model call failed, or its response wasn't usable. Never
    caught-and-retried automatically by a provider or by planner.py."""

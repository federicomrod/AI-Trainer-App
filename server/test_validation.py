"""
test_validation.py -- offline checks (no model, no cost) for reading
the athlete's stated time out of a message.

    python3 test_validation.py
"""

from validation import extract_stated_minutes

CASES = [
    # (message, expected minutes)
    ("only have 40 minutes", 40),
    ("I've got two hours", None),          # words, not digits: unsupported
    ("I have an hour", 60),
    ("half an hour today", 30),
    ("I have 40 minutes at lunch", 40),
    ("need to be out in 45 min", 45),
    ("1 hr max", 60),
    # Workout structure is not available time.
    ("Give me the bike intervals: 4 x 4 minutes at 180 W.", None),
    ("4x4min at 180 W", None),
    ("intervals of 4 minutes with 4 min rest", None),
    ("3 x 8 min at threshold, 2 min recovery", None),
    ("30 min easy, then 4 x 4 minutes at 180 W", 30),
    ("only 40 minutes, 4 x 4 min at 180 W", 40),
]

failed = 0
for text, expected in CASES:
    got = extract_stated_minutes(text)
    ok = got == expected
    failed += not ok
    print(f"{'ok  ' if ok else 'FAIL'}  {text!r} -> {got} (expected {expected})")
raise SystemExit(1 if failed else 0)

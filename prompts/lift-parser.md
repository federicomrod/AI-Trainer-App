# Lift Parser Prompt

This is the prompt for the one small model call that pulls tracked-lift
numbers out of free text -- typed or, more often, voice-dictated
(CLAUDE.md: logging should default to a summary or a 20-second voice
note, not a form). It runs separately from the planner call in
planner.md: extracting numbers out of a sentence isn't "deciding what
to train," and giving it its own prompt keeps this one editable without
touching the much bigger planner prompt.

This is not a coach-voice prompt -- there's no reply to write, no
register to hold. Its only job is honest extraction.

---

You will be given the athlete's already-tracked exercise names (their
own established names for exercises they've logged real numbers for
before, if any) and one piece of free text: what they said or typed
after a workout, describing what they did. Extract every exercise they
mention a real number for -- weight, reps, and/or sets.

Rules:

- Only extract an exercise if the athlete actually stated a number for
  it (a weight, a rep count, or a set count). "Did some rows" with no
  number is not an entry. Never invent or estimate a number that
  wasn't said.
- One entry per exercise mentioned with a number, even if the text
  only gives partial numbers (e.g. "squatted 105 for a top set" — reps
  and sets are null, weight is 105). Leave any number that wasn't
  stated as `null` rather than guessing.
- If the exercise clearly matches one of the athlete's already-tracked
  names, use that exact name -- "did squats" should become "Back
  Squat" if that's already their tracked name for it, not a fresh
  generic "Squat". This is what keeps one exercise's progress in one
  continuous line instead of splitting into two. Only when nothing
  already-tracked matches, use the exercise name roughly as the
  athlete said it, cleaned up to a normal short form ("db bench" ->
  "DB Bench"). Never rename it to a genuinely different exercise.
- Weight is in kilograms. If the athlete gives pounds ("225 lbs",
  "225#"), convert to kg (divide by 2.2046) and round to the nearest
  0.5kg -- this app's tracked numbers are kg throughout, and mixing
  units would make progress charts meaningless.
- `note` is anything short and relevant the athlete said about that
  specific lift ("felt heavy", "last rep was grindy") -- null if
  nothing exercise-specific was said. General session comments that
  aren't about one exercise don't belong here.
- If nothing in the text has an actual number attached to an exercise,
  return an empty list. That's a completely normal result — most
  session notes ("felt good", "skipped leg press, knee felt off") have
  no numbers to extract at all.

Return the list of entries found, nothing else. No commentary.

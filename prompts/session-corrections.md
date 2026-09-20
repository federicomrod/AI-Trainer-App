# Session Corrections Prompt

A small, separate extraction call in the same shape as
prompts/lift-parser.md and prompts/session-note-parser.md. It is not
deciding what to train — it only reads what the athlete says they
already did and turns it into rows for the `sessions` table.

The gap this closes: telling the coach "Monday was push, Tuesday the
pool, Wednesday pull instead of rest" used to change nothing. The
planner read it, used it for today's decision, and said something
agreeable — but nothing was ever written down, so Week and Progress
stayed empty and the same correction had to be repeated the next day.
The planner call can't fix this: its job is today's decision, and
CLAUDE.md's decision schema has nowhere to put "and here is what
actually happened on five earlier days".

What comes back here is applied to the `sessions` table in code
(server/session_corrections.py), and the coach's reply then names
exactly which days were written. Nothing is ever saved silently.

---

You will be given today's date, a dated list of the recent past days
with whatever is already on record for each, and one new message from
the athlete.

Return one entry for every past day the message says something
definite about. For each entry:

- **date** — the exact ISO date from the list. Work out day names
  against that list ("Tuesday" is the most recent past Tuesday), and
  never invent a date that isn't on it.
- **type** — exactly one of: `push`, `pull`, `legs`, `ride`, `run`,
  `swim`, `intervals`, `rest`. Map their words onto this vocabulary:
  "the pool" is `swim`, "turbo"/"bike"/"spin" is `ride`, "track
  session"/"threshold efforts" is `intervals`, "upper" is `push` or
  `pull` by what they describe, "nothing"/"off day" is `rest`.
- **status** — `done` if they did it, `partial` if they cut it short,
  `skipped` if it was planned and didn't happen. Use `unplanned` only
  when they say it wasn't on the plan at all.
- **summary** — one short line in their own terms ("pool, 40 min
  easy", "pull, felt strong"). This is what shows on the day in Week
  view. Keep any number they mention (distance, time, load).
- **duration_min** — minutes, if they said or clearly implied it.
  `null` otherwise. Never estimate a duration they didn't give.
- **heard** — the athlete's own words about this day, quoted from the
  message ("Tuesday was the pool"). Not your paraphrase: this is what
  gets read back to them if the day needs confirming.
- **confidence** — `high` only when the words can't reasonably mean a
  different session type. `medium` or `low` otherwise. A day below
  `high` is **not saved**; the athlete is asked about it instead, so
  being unsure costs them one question and being wrong costs them a
  false entry in their training history.
- **alternative** — the other type it could be when confidence isn't
  high, else `null`.

### Most of this message arrived by voice

Assume every message may be a transcription, and that transcription
gets words wrong in ways that still read perfectly.

The one that has already happened here: **"pull" comes back as "the
pool"**. Both are real session types — `pull` is the gym day, `swim`
is the pool — so a confident guess writes the wrong session into
someone's history with nothing to show it was a guess.

- "Tuesday was the pool" — ambiguous. `swim`, `alternative: pull`,
  confidence `low`.
- "Tuesday was pull" — equally ambiguous the other way. `pull`,
  `alternative: swim`, confidence `low`.
- "Tuesday the pool, 40 lengths" — settled. `swim`, confidence `high`.
- "Tuesday pull, 3x10 lat pulldown" — settled. `pull`, `high`.
- "Tuesday was pull, not the pool" — they drew the distinction
  themselves. `pull`, `high`.

The same care applies to anything else that could be two types: "ride"
and "run" in a noisy recording, "press" meaning a push day or one
exercise inside another session. Corroborating detail — distance,
lengths, reps, a bike, a lane — is what makes a reading `high`.

When an earlier message shows the coach asked which session a day was,
and this message answers it ("it was pull", "the second one"), that
answer *is* the confirmation: return that day with confidence `high`.

Rules:

- **Only days that have already happened, including today.** A future
  intention ("I'll ride Saturday") is planning, not a correction —
  leave it out entirely; the planner handles that.
- **Never guess between two valid types.** Half a session type is not
  a session type. Mark it and let the athlete settle it.
- **Only definite statements.** "Tuesday was the pool" is definite.
  "I might have swum Tuesday", "usually I swim Tuesdays", or a
  question about Tuesday is not. When in doubt, leave it out: a wrong
  row in someone's training history is worse than a missing one.
- **One entry per date.** If the message mentions a day twice, merge
  it into a single entry.
- **A correction wins over what's already on record.** If the list
  shows Wednesday as `rest` and they say Wednesday was pull, return
  Wednesday as `pull` — that's the whole point of this call.
- Return an empty list when the message says nothing definite about
  any past day. That is the common case.

Return only the list. No commentary.

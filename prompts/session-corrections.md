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

Rules:

- **Only days that have already happened, including today.** A future
  intention ("I'll ride Saturday") is planning, not a correction —
  leave it out entirely; the planner handles that.
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

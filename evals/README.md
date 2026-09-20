# Evals

Frozen scenarios: a known database, a known message, and what the
coach must do about it. Each one is a bug that actually happened, kept
so it can't come back quietly.

These make real model calls, so they cost money and take a few seconds
each. They're not run automatically — run them when you change a
prompt or anything in the path between a message and the database.

```bash
server/.venv/bin/python evals/run.py            # everything
server/.venv/bin/python evals/run.py ambiguous  # just matching names
```

Each scenario sets up its own throwaway database, so nothing here ever
touches the real one.

A scenario checks *behaviour*, never wording: "Tuesday wasn't written
and the reply asks about it", not "the reply says these exact words".
The model's phrasing changes run to run; what it does must not.

## Scenarios

- **ambiguous_swim_or_pull** — "Tuesday was the pool" with nothing to
  settle it. `pull` (a gym day) is transcribed as "the pool" often
  enough that it happened in the first week of real use, and `swim` is
  a perfectly valid session type, so a confident guess saved the wrong
  session in silence. Tuesday must not be written, and the reply must
  ask.
- **settled_by_detail** — the same sentence plus "40 lengths". Now it
  is a swim, and asking would be pedantic. It must be saved without a
  question.
- **today_is_a_date_not_a_type** — "today's push" with an older push
  day sitting in the same window. Today's date gets the session; the
  older day is left alone; the numbers given are stored as numbers.
- **already_trained_is_reviewed** — opening the app after training.
  The coach must review the finished session, not propose one.
- **detail_is_not_re_asked** — numbers given once are in the briefing,
  so nothing is asked for twice.
- **answer_resolves_the_question** — the athlete answers that question
  with "it was pull". That must now be saved as `pull`.

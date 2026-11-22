# Brief: show routines and plans as cards in Coach chat

The server now sends structure next to the chat text (branch
`structured-replies`). The iOS app must draw it. Do not change the server.

## What the server sends
- `GET /messages` rows (`ChatMessage`) and `POST /turn` (`TurnResponse`) gain:
  - `cards`: array of "workout" and/or "week" (empty most of the time)
  - `workout` (messages only): the decision's `today` object
    (`type`, `duration_min`, `exercises[]`, `intensity_note`). On a live
    turn, take it from `decision.today` when `cards` contains "workout".
  - `week_plan`: array of `{date (ISO), title, kind (gym|cardio|rest|other),
    detail (nullable), optional (bool)}`
- The reply text no longer contains lists or markdown. It is 1-3 plain sentences.
- All new fields are optional: old history rows have none. Decode with defaults.

## What to build (ChatView.swift, Models.swift, a new ChatCards.swift)
1. Decode the fields above (`cards` default `[]`).
2. Under an assistant bubble, when `cards` has "workout": a **table card**
   (same dark card style as Theme): header = type + "~N min" + intensity
   note; one row per exercise: name (left), `sets x reps` (right, bold), and
   a second smaller line with rest ("90 s rest"), then technique/note. Join
   rows that share `superset_group`. Last line: total working sets.
3. When `cards` has "week": a **week card**: one row per day, a date block
   on the left (MON / 23), title and detail in the middle, a small pill on the
   right: "Gym" (blue), "Cardio" (lime), "Rest" (grey), "Optional" if
   `optional`. Rows separated by thin lines.
4. Tapping the workout card's header opens the existing Workout screen
   (same as Start workout on Today) when it is for today.
5. Keep the bubble text above the card; cards are wider than the bubble
   (full chat width) so the table breathes.
6. Dynamic Type must not break the rows (allow the name to wrap).

## Check in the Simulator
Ask: "I haven't trained yet. What's my session today? Legs, 50 minutes."
-> short text + a table of exercises. Ask: "What does my week look like
Tuesday to Friday?" -> short text + week card. Ask a plain question
("why legs today?") -> text only, no card. Reopen the Coach tab: the same
cards render from history. Screenshot each into docs/screens/.

# Overnight brief for Claude Code (run on the Mac, unattended)

You are working alone while the project owner sleeps. He is not a
developer. When he wakes he wants to open the app in the Xcode simulator
and see a modern, working version of the gym flow. Read CLAUDE.md,
docs/ui-notes.md and this file first, then work through the tasks in
order.

## Ground rules

- Work on a new branch `ios-modern-look`, created from
  `coach-conversation`. Never commit to `main`. Never force-push.
- The app must build before every commit:
  `xcodebuild -project ios/AI-Trainer/AI-Trainer.xcodeproj -scheme AI-Trainer -destination 'generic/platform=iOS Simulator' build`
  (adjust the project and scheme names to what is actually there). If a
  task cannot be made to build, `git stash` or revert it, write what
  happened in `OVERNIGHT-NOTES.md`, and move on to the next task.
- Commit after each finished task, with the usual Co-Authored-By line.
- Push the branch after each commit.
- Do not touch keys, `.env`, hosting, Railway, or anything paid. Do not
  add dependencies. Do not add an eighth database table. Do not add
  streaks, points, XP or an in-app feed (CLAUDE.md).
- Backend changes only where a task says so, and keep the server tests
  green: `server/.venv/bin/python server/test_validation.py`,
  `test_progress.py`, `test_events.py`.
- Never invent numbers in the UI. Show data that exists; where there is
  none, show an honest empty state.
- Prefer boring, obvious SwiftUI. Follow the patterns already in the
  files. No clever abstractions.
- If blocked for more than ~30 minutes on one task, stop that task, note
  it, and go to the next one.

## The look (from the approved mockup)

Near-black background `#09090B`, surfaces `#141417` / `#1C1C21` /
`#25252B`, text `#F4F4F6`, muted `#9A9AA5`. Accent (strength, done)
neon lime `#D4FF3A`; endurance blue `#6C8CFF`. Text on lime is `#0A0A0A`.
Inter-like bold type (use SF Pro, heavy weights, tight tracking). Large
radii (cards 24-28, rows 18, pills fully round). The old warm-charcoal
and orange theme in `Theme.swift` is being replaced.

## Tasks, in order

1. **Theme.** Rewrite `Theme.swift` with the tokens above and helpers
   for the card styles. Make every existing screen still build and look
   consistent (no orange left). Run the app in the simulator and save
   screenshots of each tab to `docs/screens/01-*.png`.
2. **Today screen.** Redesign `TodayView.swift`: small date label, big
   "Today", one hero card (session type icon, name, duration, one
   coaching line, chips for exercises and sets, a "Why this" button that
   opens the existing reasons, a full-width lime "Start workout"
   button). Below it a Goals card. Take goals from `GET /goals` and
   progress from `GET /progress` only as far as those return real
   values; otherwise list the goal text with no bar. Tapping a goal
   opens the existing goal editor (`GoalsView`) for now.
3. **Tab bar with a big centre mic.** Today, Week, [mic], Progress,
   Coach. The mic opens the existing voice input in the chat. Reuse
   `VoiceInputButton` and `SpeechRecognizer`; do not rewrite them.
4. **Workout screen** (opens from "Start workout"). The data is
   `today.exercises` in the `/turn` response; the new fields are
   `rest_sec`, `technique`, `intensity`, `superset_group`, `target` (all
   optional: decode them as optionals so old stored decisions still
   work). One wide low row per exercise; swipe left marks done (a lime
   check), swipe right skips; tapping a row expands it with weight and
   reps steppers and a "Log set" button. The weight stepper starts from
   the last logged weight for that exercise if there is one (find how
   `/log_context` or the lifts data exposes it; if nothing exposes it,
   start empty). Elapsed-time timer in the header, started by "Start
   workout". A rest countdown after "Log set", from `rest_sec`.
   Superset rows are visually joined. Finishing posts what was done
   through the existing `POST /log_session` (study `log_session.py` for
   the shape and what it stores in `lifts`); if it cannot carry
   per-exercise weights, extend it minimally and keep its tests green.
5. **Weekly card export.** Render a share card in the "bars" style
   (week label, session count, day dots, two goal bars if real data
   exists) with `ImageRenderer` at 1080x1920 and present the share
   sheet. Real numbers only. Put it on the Progress tab.
6. **Polish and verify.** Run the app in the simulator against a local
   server seeded with the real history:
   `cd server && .venv/bin/python seed.py federico && .venv/bin/uvicorn api:app --app-dir . --port 8000`
   and point the app at `http://localhost:8000` (the simulator can reach
   localhost; check `Config.swift`). Save a screenshot of every screen
   to `docs/screens/` and note what you could not verify.

## When you finish

Write `OVERNIGHT-NOTES.md` at the repo root: what was finished, what was
not and why, what to look at first, and any command the owner needs to
run. Keep it short and in plain language. Push everything.

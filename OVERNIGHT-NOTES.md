# Overnight notes (2026-11-16)

Branch: `ios-modern-look` (from `coach-conversation`, pushed). `main` untouched.

## What's done (all six tasks)

1. **New look.** Near-black, lime and blue throughout, heavy type, big
   rounded cards. No orange left.
2. **Today.** Date, big "Today", one card: session, minutes, the coach's
   short "why", exercise chips, **Why this**, and a lime **Start
   workout**. A Goals card underneath; tap it to edit goals.
3. **Tab bar with a big mic in the middle.** Tapping it jumps to Coach and
   starts recording. Tap again to stop, and it sends.
4. **Workout screen** (from Start workout). Swipe a row left = done
   (lime tick), right = skip. Tap a row for technique, kg and reps
   steppers and **Log set**. Logging a set starts the rest countdown.
   The timer at the top runs from when you pressed Start. **Finish
   workout** saves to today through the normal logging, with your
   weights, so next time the kg box starts from your last weight.
5. **Weekly card** on the Progress tab: a 1080x1920 picture for
   Instagram Stories, shared through the normal iPhone share sheet.
6. **Screenshots** of every main screen are in `docs/screens/` (the
   `06-*` ones are the latest).

## Look at first

- `docs/screens/06-today.png`, `06-workout.png`, `05-weekly-card.png`.
- Then open the app in the Simulator and do a real workout: Start,
  log a couple of sets, swipe, Finish.

## Things to know

- **The coach is slow.** One answer took 54 to 71 seconds here, and
  once it went past the app's 90-second limit, so Today showed the last
  saved answer with "The coach took too long". It's worth looking at the
  model or reasoning setting in `server/.env`. I didn't touch it (keys
  and paid settings are off limits).
- **Goals have no progress bars yet.** Your goals are plain sentences
  with no starting number, target or date the app can measure, so
  drawing a bar would mean inventing numbers. The card lists them in
  priority order instead.
- **A rest day counts as a session on the Progress tab.** Last week's
  Saturday rest is saved as "done", and `server/progress.py` counts it,
  so Progress says 6 sessions where you trained 5 times. The weekly
  card counts only the 5 workouts and shows the rest day as a moon.
  Fixing the server count is a one-line change; say if you want it.
- **One commit per task**, except that the workout screen was committed
  before Today, because Today's Start button needs it.
- **I re-seeded your local database** with `seed.py federico`, as the
  brief said. A copy of the database from before is in my temporary
  folder for this session (it gets cleared eventually). Your own server
  on port 8000 was already running; I left it alone and ran mine on
  port 8010.
- **Testing tools I added** (they change nothing in normal use):
  - Launching with `HYBRID_COACH_URL=http://localhost:8000` makes the
    app use only that server.
  - `-startTab 2` opens on a given tab.
  - In debug builds only, `-screenshotWorkout YES` opens a demo workout
    and saves the weekly card picture.

## Not verified (I can't tap the Simulator from the terminal)

- Swiping rows, tapping the steppers and the Finish button by hand. The
  same code ran through the debug options above, and I sent the exact
  Finish payload to the server, which saved it correctly, but no finger
  has done it yet.
- The mic: Apple's speech recognition doesn't run in the Simulator. Try
  it on the phone.
- The share sheet opening, and posting to Instagram.
- Superset rows drawn joined: tonight's session had no supersets, so I
  never saw one on screen.
- Sheets (check-in, log, goals, settings, day detail) only got the new
  colours. They weren't redesigned.
- The Coach tab has no big title, same as before tonight.

## To run it yourself

```
cd server && .venv/bin/python seed.py federico && .venv/bin/uvicorn api:app --app-dir . --port 8000
```

Then run the app from Xcode. To make the Simulator use this local
server, not the deployed one, add `HYBRID_COACH_URL` =
`http://localhost:8000` under Product > Scheme > Edit Scheme > Run >
Arguments > Environment Variables.

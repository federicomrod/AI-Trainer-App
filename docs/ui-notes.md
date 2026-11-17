# UI notes

Decisions from the project owner, 2026-11-16. Read before building any
screen.

## Feel

Modern, warm, native iPhone. References: Whoop, Flighty, Revolut. Not
"the notes app". Swipe and tap, little typing. A big central mic.

## Today is home, chat is a drawer

One card for today: session, duration, a tappable "why", a Start
button. The chat sits beneath it.

## The workout is a list of horizontal cards

Each exercise is a wide, low rectangle (almost the full screen width),
not a tall square card. One row = one item in `today.exercises`.

- **Swipe left** marks it done. Another swipe action skips it. Same
  gesture as swiping an email.
- Cardio uses the same rows: warm-up, each interval, cooldown. Swipe
  when an interval is finished.
- Tapping a row opens its detail: technique, rest timer, weight.
- Weight is prefilled from last time and nudged with a stepper, so
  logging is just training.
- Long-press: swap (machine taken), make shorter. The coach re-plans.
- Rest timer starts by itself after a set, from `rest_sec`.
- Supersets (`superset_group`) are visibly joined.

## Goals

A progress bar per goal with checkpoints (Revolut/Duolingo feel, no
streaks). Earned milestone badges only. A shareable weekly card for
Instagram Stories. See CLAUDE.md, "Goals, progress and sharing".

## The product is the loop around the workout

Decided 2026-11-16. The app is mostly used before and after training,
not during it. The value is: log it (voice, screenshot, text, or a swipe
in the gym), get a coach debrief, see progress. Strava and Garmin
Connect record; they do not coach, and they do not remember last week.

- **Cardio is after the fact.** The watch records; the app takes the
  Garmin or Strava screenshot (or HealthKit), shows the numbers in the
  modern card, and the coach comments. No live cardio screen in v1: the
  watch is already doing that job, and a second app must not compete
  with trainer control.
- **Gym is the one live exception**, because swiping an exercise done
  and nudging the weight is faster than typing, and it is where the
  precise numbers come from.
- **The debrief is the hero.** After every logged session the coach
  says: how it compared with last time, in numbers; what it means for
  the next days; the one plan change if there is one; fuel or rest only
  when it matters. No "stronger than expected" without a number, no
  generic advice (more carbs, rest more), no praise for logging.
- Progress views (goal bars, "+7.5 kg", gauge, line) are built from the
  same logged numbers, so the debrief and the weekly card never disagree.

## Later

Running logged after the fact. Tribes and group scheduling (v2).

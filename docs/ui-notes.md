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

## Later

Running logged after the fact. Tribes and group scheduling (v2).

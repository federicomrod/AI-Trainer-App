# Hybrid Coach — Project Bible

Read this file at the start of every session. It defines what we are
building and how. When something here conflicts with a request in chat,
say so rather than silently picking one.

---

## What this is

An iPhone app for gym-goers who are adding cycling, running and swimming
without losing strength.

It is **not** a workout generator. It is a companion that knows your
history, proposes today's session, and quietly reshuffles the week every
time real life gets in the way.

The one-sentence contract:

> Given the athlete's goals, what they actually did, how they feel, and
> what their week looks like, recommend the best next session, make the
> smallest necessary change to the existing plan, explain why, and
> remember what happened.

## Who it is for (v1)

One persona only. A trained gym-goer, 28–45, lifts 3–4x/week, wants to
add endurance without shrinking. Busy job, travel, social life,
inconsistent weeks. Knows what a RDL is. Does not want to be taught how
to train — wants help fitting it all together.

Do not add features for beginners, weight-loss users, or racing
athletes. Not yet.

## The core loop

```
what actually happened  ->  athlete state  ->  today's decision
        ^                                            |
        |                                            v
   post-workout input   <-   session done   <-   session + reason
```

Everything in the app serves this loop. If a feature doesn't, it waits.

## How the decision gets made (v1)

There is no physiology engine in v1. The flow is:

1. Assemble a **briefing**: a plain-text summary of the athlete built
   fresh from the database on every request.
2. Send it to the model in **one call** with the planner prompt.
3. Get back **structured JSON** (schema below).
4. Validate against hard rules in code.
5. Save, then render.

**The briefing is where quality lives.** Most of the work on this
project is making the briefing good, not making the prompt clever. The
briefing is also the reason ChatGPT can't do this — it has no database.

Briefing must contain: goals and their rough priority, last 14 days of
sessions (planned vs actual), this week's plan, recent coaching
decisions and why they were made, current soreness and energy, tracked
exercises with recent numbers, coach memory lines, and any context
events (travel, illness, big social weekend).

## Data model — seven tables. Do not add an eighth without asking.

**profile** — goals, goal priorities, weekly availability, typical
session length, equipment/gym, preferred and disliked exercises,
injuries, experience level

**sessions** — one row per session, planned and completed in the same
table. `status` is one of: planned, done, partial, skipped, unplanned.
Fields: date, type (push/pull/legs/ride/run/swim/intervals/rest),
planned_summary, actual_summary, duration_min, rpe, notes, source
(manual/voice/healthkit/screenshot)

**lifts** — date, exercise_name, weight, reps, sets, note. The one
exception to summary-level logging: precise numbers, for whichever
exercises the athlete is actually chasing. Tracking is emergent —
logging a number for an exercise is what tracks it. No 1–3 cap, nothing
to configure first. The coach asks for numbers only on exercises that
already have rows here, and never chases one that's gone quiet.
Everything else stays free text in sessions.actual_summary.

**checkins** — date, sleep (poor/normal/good), energy 1–5, soreness by
region, pain_flag, free note

**events** — date range, type (travel/social/illness/big_walk/other),
note, effect on availability

**memory** — plain text lines the coach has learned. One fact per row,
with date added. Example: "prefers hip thrust over back squat", "runs
poorly within 48h of heavy legs"

**messages** — the conversation, with role and timestamp

Every metric carries `source` and whether it was measured, imported or
self-reported. Never silently merge conflicting sources (treadmill vs
watch) — keep both, use the right one for the question.

## Decision output schema

```json
{
  "decision": "KEEP | MODIFY | REST",
  "today": {
    "type": "upper_push",
    "duration_min": 60,
    "exercises": [
      {"name": "Incline DB press", "sets": 4, "reps": "8-12", "note": "leave 2 in reserve"}
    ],
    "intensity_note": "heavier than last week on press"
  },
  "why": "one or two sentences, plain language, grounded in the briefing",
  "plan_diff": [
    {"date": "2026-09-16", "from": "legs", "to": "upper_push", "reason": "weekend leg load"}
  ],
  "specialist_notes": [
    {"coach": "endurance", "text": "..."}
  ],
  "memory_to_add": ["..."],
  "question": null,
  "safety_flag": null
}
```

`specialist_notes` is usually empty. `question` is null unless the
missing information would actually change the decision — never ask just
to seem thorough.

## Prescription style

Sets and rep **ranges**, not exact loads: "4 x 8-12", "3 x 10-15".
The athlete picks the weight. Only give a specific number when it comes
from their own tracked history ("you did 82.5 for 8 last time").

## Logging philosophy

Default logging is a summary, not a set-by-set record. Acceptable input
is "did it", "did it but swapped leg press for hack squat", "skipped,
was out for drinks", or a 20-second voice note.

**Tracked exercises** are the exception, stored in their own `lifts`
table. Tracking is emergent, not configured: logging a real number for
an exercise is what tracks it, no cap and nothing to set up first. For
those exercises only, the coach asks for numbers and stores them
properly so progression is visible. An exercise that's gone quiet is
never chased — silence there is just silence, same as everywhere else.

Never make the athlete feel behind for not logging in detail.

## Non-goals for v1

No calorie tracking or weight-loss programming. No social feed. No
exercise video library. No multi-agent debate. No readiness score
presented as physiological fact. No Android. No Strava (their API terms
prohibit AI use — do not integrate). No gamification. No streaks.

## Tech decisions

- Backend required (API keys can't live in the app). Keep it to one
  deployable. Postgres or SQLite to start.
- Voice input: Apple on-device speech recognition. Free, instant, no
  upload.
- Screenshots: send the image to the model directly.
- Notifications v1: local notifications scheduled when the plan is
  generated. No push infrastructure.
- HealthKit: read-only, request the minimum categories. Garmin and Oura
  write into HealthKit, so this one integration covers most watches.
- Coach prompts live in `/prompts` as editable markdown. Never hardcode
  coach language in application code.

## Repo layout

```
docs/      reference material, product spec
prompts/   coach personality and planner prompts (editable, not code)
server/    backend
ios/       Xcode project
evals/     frozen test scenarios
```

## How to work with me

The person running this project is not a developer. So:

- Explain each step in plain language as you go. No jargon without a
  one-line translation.
- Build the backend with a command-line way to test it **before** any
  iPhone UI. Being able to type a message and see the decision in the
  terminal is worth more than a screen.
- Work one milestone at a time. Stop and show results.
- When a decision has a real trade-off, say what it is and recommend
  one. Don't present five options.
- Prefer boring, obvious code over clever code.

## Milestones

- **M0** backend only: schema, briefing assembler, one planner call,
  structured output, CLI to test it
- **M1** SwiftUI app: Today screen, Coach chat, voice input
- **M2** HealthKit read, check-in, post-workout logging, Week view with
  visible plan diffs
- **M3** screenshots, morning/evening notifications, coach memory
- **M4** daily personal use, collect annoyances, freeze eval scenarios
- **M5** TestFlight to 5–8 people who match the persona

# Product Spec --- Adaptive Fitness Companion

## Purpose

This is the lean MVP product specification for the fitness companion. It
is based on the actual coaching interaction patterns from the Fitness
project and is intended to guide implementation in Claude Code.

The product is **not primarily a workout generator**. It is a companion
that understands what the athlete has actually been doing, what they are
trying to achieve, how they currently feel, and what real life has
changed --- then gives a clear recommendation for what to do next.

The MVP should optimize for **using the product quickly with real
training**, not for building a large physiological or multi-agent engine
upfront.

## Core product principle

**Given the athlete's goals, recent training, current recovery,
preferences, and real-life constraints, recommend the best next training
action, make only the changes that are necessary, and explain why.**

The reference user is a busy recreational athlete pursuing overlapping
goals such as strength, athletic aesthetics, cycling, running, aerobic
fitness, and recovery. The product must generalize to each user's own
goals.

------------------------------------------------------------------------

## How the user naturally interacts

The product should be designed around these inputs rather than forcing
the user into a rigid form.

## 3.1 Pre-training input

Typical pre-session information has included:

-   "What is next?" based on the recent sequence of push / legs / pull /
    endurance work.
-   Current soreness, especially leg soreness after strength work or
    cycling.
-   Whether the previous day included a ride, run, intervals, gym
    session, or unusually high walking volume.
-   What exercises the athlete is considering.
-   How much time is available.
-   Whether a run or ride might be added after lifting.
-   Equipment or gym context.
-   Recent travel and accumulated physical activity.
-   Desired emphasis for the session, e.g. hamstrings, athletic
    aesthetics, chest, endurance.
-   A proposed workout that the coach is expected to critique rather
    than blindly accept.

Example interaction pattern:

> "I think legs are next. I was thinking back extensions, RDLs, bridges,
> hip thrust or leg press, then lighter squats and leg curls. Am I
> missing anything?"

The correct product behavior is not merely to return exercises. It
should:

1.  recover the recent training context;
2.  assess whether legs really are the best choice;
3.  evaluate the proposed exercise selection;
4.  preserve useful user preferences;
5.  adjust order, volume, intensity, or exercise choice;
6.  explain important changes;
7.  relate today's session to upcoming endurance work.

## 3.2 During-training input

The user may provide live or near-live information such as:

-   actual load used;
-   repetitions achieved;
-   RPE / RIR;
-   whether a movement feels unusually difficult;
-   pain or discomfort;
-   treadmill speed or interval details;
-   whether the planned workout needs to be shortened;
-   a screenshot from a machine, wearable, or fitness app.

The companion should be able to modify the remainder of the session
without treating the whole plan as invalid.

Example:

> Planned set feels much harder than expected.

Desired behavior:

> Reduce the next set or remove a lower-priority accessory, preserve the
> key stimulus, and record that today's readiness was below expectation.

## 3.3 Post-training input

Post-session information has included both structured and unstructured
data:

-   screenshots of workout statistics;
-   distance;
-   duration;
-   pace or speed;
-   heart rate;
-   interval structure;
-   subjective difficulty;
-   soreness;
-   what food and fluids were consumed;
-   whether the session differed from the plan;
-   how the legs felt afterward;
-   whether another session is planned the following day.

The system should convert this into athlete-state updates.

The user should not have to manually translate:

> "65 km in around 2h26, average HR around 152, two bottles, banana and
> a Clif Bar, legs are very sore"

into separate database fields before receiving coaching.

The companion should parse what it can, identify uncertainty where
relevant, and immediately answer the practical question: **what does
this change?**

## 3.4 Life-context input

This has been especially important.

Examples include:

-   business or leisure travel;
-   unusually high walking volume while visiting a city;
-   social plans;
-   a long ride occurring unexpectedly;
-   limited gym access;
-   a desire to train the next morning despite accumulated activity;
-   work-week scheduling constraints.

A representative example from the project was the athlete completing a
Saturday morning leg session and then accumulating roughly 50,000 steps
over the weekend while visiting Milan. By Monday, the useful question
was not "what comes after legs in a PPL split?" It was "given the actual
weekend load, what is the best session now?"

The app must therefore distinguish **planned training load** from
**actual total physical load**.

------------------------------------------------------------------------

## Pre-workout UX

The "Today" experience is the heart of the app.

A useful screen should answer within seconds:

1.  What am I doing?
2.  Why this?
3.  How hard?
4.  What changed from the plan?
5.  What do I need to tell the app before I start?

Example:

    TODAY
    Push - chest emphasis
    ~65 min

    Why today
    Your legs accumulated high load over the weekend.
    Upper-body training preserves the strength plan without
    compromising lower-body recovery.

    Key work
    1. Bench press ...
    2. Incline press ...
    3. ...

    Optional
    20-30 min easy aerobic work if legs feel <= 3/10 sore.

    Changed
    Leg work moved from today to Tuesday.

The user should be able to respond naturally:

> "Actually my legs feel fine and I only have 45 minutes."

The app should recompute rather than forcing the user to edit multiple
fields.

------------------------------------------------------------------------

## Recovery is contextual, not a single score

The existing interaction has repeatedly involved questions such as:

-   Can I train legs tomorrow after a long ride?
-   Can I do an easy run with severe DOMS?
-   Is easy cycling useful for recovery?
-   Should recovery tools such as compression or massage be used after
    intervals or leg day?

The app should not reduce this to a mysterious 0-100 readiness score.

Instead, maintain a multi-signal recovery state:

``` yaml
recovery:
  systemic:
    status: moderate
    confidence: medium
  quads:
    soreness: 6
    recent_load: high
  hamstrings:
    soreness: 3
    recent_load: moderate
  sleep:
    deviation_from_baseline: -8%
  hrv:
    deviation_from_baseline: -10%
    predictive_confidence_for_user: low
```

Then explain the decision in human terms.

Subjective soreness and perceived fatigue are first-class data.

------------------------------------------------------------------------

## Communication style

The existing relationship works because the user can talk to the coach
like a knowledgeable training partner.

The app should be:

-   direct;
-   concise by default;
-   specific;
-   willing to challenge the user's proposal;
-   willing to say "yes, that's fine";
-   aware of previous decisions;
-   practical rather than academic;
-   capable of deeper explanation on request.

Avoid:

-   generic motivational filler;
-   excessive praise;
-   repeating the entire weekly plan when only today's decision changed;
-   pretending every biometric fluctuation is meaningful;
-   unexplained plan changes;
-   false precision;
-   lecturing the user for non-compliance.

A missed session is data, not a moral failure.

------------------------------------------------------------------------

## The companion relationship

The emotional quality to preserve is **continuity**.

The user should feel:

> "This system knows what I have been doing and I don't need to start
> from zero every morning."

The coach should naturally ground advice in recent context:

-   "Given Saturday's leg session and the walking load this weekend..."
-   "Your last hard lower-body stimulus was..."
-   "We moved intervals because..."
-   "You wanted more hamstring emphasis, so..."
-   "Since the ride was harder than planned..."
-   "You have not run much recently, so keep this first return
    conservative."

This must come from remembered user context, not fake personalization.

A missed session, spontaneous ride, travel day, bad night of sleep, or
unusually active weekend should be treated as new information. The user
should never feel punished for deviating from the plan.

------------------------------------------------------------------------

## Reference scenarios --- initial test suite

The MVP should be instrumented from the first commit.

Create frozen scenarios based on real coaching situations.

Examples:

### Scenario A - weekend load

-   Saturday leg workout.
-   50,000 weekend steps while traveling.
-   Monday asks whether push or legs is next.

Expected properties: - recognizes total lower-body load; - does not
blindly follow rotation; - likely favors upper body; - preserves future
lower-body work; - explains why.

### Scenario B - long ride before planned legs

-   \~65 km ride.
-   substantial leg soreness.
-   leg day planned tomorrow.
-   user also considers easy run.

Expected properties: - recognizes cycling load; - distinguishes active
recovery from additional training; - adjusts leg training based on
soreness/recovery; - avoids stacking unnecessary lower-body stress.

### Scenario C - proposed hamstring session

User proposes: - back extensions; - RDLs; - bridges; - hip thrust/leg
press; - squats; - leg curls.

Expected properties: - evaluates redundancy; - creates sensible
ordering; - maintains hamstring emphasis; - balances hinge/knee-dominant
work; - does not add volume merely to appear helpful.

### Scenario D - 4 x 4 treadmill intervals

User supplies treadmill details and screenshots after the session.

Expected properties: - stores actual interval prescription; -
distinguishes machine vs wearable data if different; - updates endurance
load; - considers next lower-body session.

### Scenario E - severe DOMS

User wants to run/cycle two days after hard legs.

Expected properties: - differentiates easy movement from
high-impact/intense work; - asks about pain vs normal soreness if
needed; - does not automatically prescribe total rest; - does not push
hard training through concerning symptoms.

For every scenario score:

-   safety;
-   constraint adherence;
-   goal alignment;
-   plan stability;
-   interference logic;
-   use of history;
-   personalization;
-   explanation accuracy;
-   unnecessary questions;
-   latency/cost.

------------------------------------------------------------------------

## Coaching-staff UX without multi-agent dependency

The user may benefit from seeing multiple perspectives.

Example:

    TODAY'S CALL: PUSH

    Strength
    Good opportunity to progress upper-body work.

    Endurance
    No conflict with tomorrow's lower-body recovery.

    Recovery
    Leg load remains elevated after the weekend.

    Head Coach
    Push today. Reassess legs tomorrow.

This can be generated from one underlying decision object.

Do not make five models debate merely to render this UI.

Only introduce a specialist model later if evals show a measurable
weakness that domain specialization improves.

------------------------------------------------------------------------

## Notification philosophy

Notifications should be useful decisions, not engagement spam.

Good:

> "Tomorrow's leg session was reduced because today's ride was harder
> than planned."

> "You have a hard cycling session tomorrow. If you're training tonight,
> upper body is the better fit."

Bad:

> "Time to crush your goals!"

Potential future calendar integration should let the app understand
travel, meetings, and available training windows, but it should request
only the access needed and should never schedule over real commitments
without explicit user control.

------------------------------------------------------------------------

## What success should feel like

After several weeks the user should be able to open the app Monday
morning and think:

> "It knows what I did this weekend, knows what I'm trying to achieve,
> and already has the right next move."

After an unexpected workout:

> "I don't need to manually repair my program."

Before a session:

> "I understand why I'm doing this today."

After a bad week:

> "The plan recovered without punishing me or pretending the missed
> sessions never happened."

After months:

> "It has learned how I respond, not just what generic sports-science
> guidelines say."

That is the desired product experience.

------------------------------------------------------------------------

## MVP interaction loop

Keep the first implementation simple:

``` text
User opens app / messages coach
        |
        v
App knows recent training + current plan
        |
        v
User adds today's context
("legs sore", "only 45 min", "rode 80 km yesterday",
 "traveling Thursday", etc.)
        |
        v
Coach recommends today's action
        |
        v
User trains
        |
        v
User logs/imports what actually happened
+ quick subjective feedback
        |
        v
Coach adjusts what matters next
```

The user should be able to provide context in natural language. Do not
require them to complete a long readiness questionnaire before getting
an answer.

------------------------------------------------------------------------

## MVP screens

### 1. Today

This is the primary screen.

Show:

-   today's recommended session;
-   approximate duration;
-   key exercises or endurance structure;
-   a short **Why today** explanation;
-   what changed from the prior plan, if anything;
-   optional addition such as easy aerobic work when appropriate;
-   one obvious way to tell the coach something has changed.

The user should be able to type:

> "Actually my legs feel fine and I only have 45 minutes."

and receive an updated recommendation.

### 2. Coach

A natural conversation interface grounded in recent training context.

Example prompts:

-   "What is next?"
-   "Can I run after this?"
-   "My hamstrings are still destroyed."
-   "I missed yesterday. What now?"
-   "I'm doing a 100 km ride Saturday."
-   "I was thinking RDLs, hip thrusts and leg curls today. Does that
    make sense?"

The coach should answer the practical question first.

### 3. Week

A lightweight view of planned and completed sessions.

It should make changes understandable, not expose a complex planning
engine.

The important distinction is:

-   planned;
-   completed;
-   moved/adjusted.

### 4. Post-workout check-in

Keep this extremely short.

Capture what is not already known:

-   completed / modified / skipped;
-   subjective difficulty;
-   soreness or pain;
-   optional free-text note.

If workout data can be imported, do not ask the user to re-enter it.

------------------------------------------------------------------------

## Inputs the MVP must tolerate

The real coaching relationship is messy. The app must work with:

-   natural-language descriptions;
-   incomplete workout details;
-   screenshots or imported workout data when available;
-   subjective soreness;
-   unexpected rides/runs;
-   unusual walking volume;
-   travel;
-   limited time;
-   equipment changes;
-   planned workouts that the user wants the coach to critique;
-   conflicting device/machine metrics.

The MVP does not need perfect automatic parsing of every input on day
one. It does need a graceful way for the coach to use these inputs
without forcing the user into rigid logging.

------------------------------------------------------------------------

## Plan behavior

The plan is a **living forecast, not a contract**.

When reality changes, prefer the smallest sensible adjustment.

Example:

> A long ride was harder than planned.

Good behavior:

> Keep tomorrow upper-body. Move or reduce the next lower-body session
> if needed. Preserve the important interval session later in the week.

Bad behavior:

> Regenerate the entire next four weeks.

The product should protect continuity.

------------------------------------------------------------------------

## What not to build yet

For the first usable version, do **not** build:

-   five autonomous specialist agents debating each decision;
-   a detailed per-muscle recovery engine;
-   individualized interference coefficients;
-   a large scoring/optimization pipeline;
-   a complex 20+ entity athlete database before the UX works;
-   proprietary readiness scoring;
-   social features;
-   gamification;
-   meal-photo calorie estimation;
-   aggressive dieting features;
-   generic AI coach avatars;
-   constant automatic replanning.

Start with enough stored context to make the reference scenarios work
reliably.

------------------------------------------------------------------------

## First build target

The first version is successful if it can support this workflow:

1.  User has a simple weekly training plan and goals.
2.  App knows the last several completed sessions.
3.  User opens **Today**.
4.  App recommends the next session and explains why.
5.  User adds new context in natural language.
6.  App can modify the recommendation.
7.  User records what actually happened.
8.  The next recommendation reflects that information.
9.  The five reference scenarios below continue to pass.

Do not delay this loop in order to build sophisticated infrastructure.

------------------------------------------------------------------------

## Build-time test suite

Treat the five scenarios in **Evaluation requirements** above as the
initial product test suite.

When changing prompts, memory behavior, workout logic, or the
UI-to-model context, re-run all five scenarios.

The goal is not that every answer uses identical wording. The behavioral
properties must remain true.

These scenarios should be implemented as repeatable fixtures as early as
practical.

------------------------------------------------------------------------

## Product success criterion

The product should eventually create this feeling:

> "I can tell it what happened, and it already understands what that
> means for my training."

That is more important for the MVP than physiological sophistication,
agent count, or dashboard depth.

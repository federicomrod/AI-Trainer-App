"""
Fixture: federico

Federico's real training history, rebuilt from the context file he
exported from his ChatGPT coaching chat (2026-11-16). It exists so the
coach can be tested against the person it is actually for, instead of
a made-up athlete.

Provenance rules, taken from that file's own warning that it is a
reconstruction and not a transcript:
- A session is marked `done` only where the file says it was completed
  or reported. Planned-but-unconfirmed sessions stay `planned`, with a
  note saying so. Nothing is silently promoted to completed.
- Exercise numbers appear only where the file gives them (the
  2026-11-08 pull). No loads or reps are invented.

Anchor: today is 2026-11-16 (Monday). Run `python3 seed.py federico`.
"""

import json
from datetime import date

TODAY = date(2026, 11, 16)


def profile_row():
    return (
        json.dumps([
            "Aesthetic hypertrophy: rounded lateral delts, upper chest, "
            "triceps, wide and thick back",
            "Cardiovascular endurance: cycling FTP and VO2max (target "
            "VO2max 50; FTP currently 161 W by Garmin ramp estimate)",
            "Strength targets: 100 kg for 8 reps on bench press, 2-minute "
            "dead hang",
            "Longevity and functional athleticism",
        ]),
        "5-6 sessions a week, mornings, often fasted about 45 minutes "
        "after waking. Rolling Push / Pull / Legs rather than fixed "
        "weekdays; Push alternates upper-chest-first and shoulder-first. "
        "Rides and easy swims fit around lifting.",
        50,
        "Commercial gyms (machines and Hammer Strength). Smith machine, "
        "hack or belt squat, hip thrust machine. Home: JetBlack VICTORY "
        "direct-drive smart trainer (ERG via Garmin ANT+ FE-C), Garmin "
        "Forerunner 965, chest-strap HR. Pool for easy 1.5-1.8 km swims.",
        json.dumps([
            "Bulgarian split squats (keep in leg plans; discuss before "
            "removing)",
            "chest-supported T-bar / Hammer Strength rows",
            "neutral-grip then supinated lat pulldown on the same machine",
            "standing EZ-bar curl + seated alternating hammer curl superset, "
            "then slow incline DB curls",
            "single-arm cable lateral raises (myo-reps)",
            "incline Smith/barbell or DB press",
            "overhead cable triceps extension and rope pressdown",
            "Smith squats, seated leg curls, hip thrust machine",
        ]),
        json.dumps(["traditional seated cable row (since the back injury)"]),
        "Acute sharp lower-left back pain on 2026-10-12 during a seated "
        "cable row, no leg symptoms, improved through October. Prefer "
        "chest-supported rows and stable torso; avoid heavy unsupported "
        "hinging and momentum until tolerance is shown. Kneeling ab-wheel "
        "only, stop if back pain appears. Cable rows may be reintroduced "
        "gradually, symptom-guided.",
        "Advanced: over 10 years lifting; comfortable with intensity "
        "techniques; experienced with cycling intervals",
    )


def _d(month, day):
    return date(2026, month, day).isoformat()


# (date, type, status, planned, actual, duration, rpe, notes, source)
def session_rows():
    return [
        (_d(10, 31), "legs", "done", None,
         "Germany gym legs: leg extension warm-up, seated curls, hip thrust "
         "machine, belt squat, leg press, glute kickback; lateral raises and "
         "curls for pump.", None, None, None, "manual"),
        (_d(11, 2), "push", "done", "Chest-first push",
         "Chest-first push: incline barbell, seated shoulder press, flat DB "
         "bench, lateral raises, triceps.", None, None,
         "Reported in the earlier chat; no numbers recorded.", "manual"),
        (_d(11, 3), "pull", "done", None,
         "Pull in Germany: lat pulldowns, Hammer Strength low and high rows, "
         "supported row, biceps triset, rear-delt work.", None, None, None,
         "manual"),
        (_d(11, 6), "legs", "planned",
         "Quad-biased legs: Smith squats first, then leg curls, hack squat, "
         "hip thrust, Bulgarians, extensions.", None, None, None,
         "Completion not confirmed in the chat export.", None),
        (_d(11, 7), "push", "planned",
         "Shoulder-first push: Smith shoulder press, incline DB, cable "
         "lateral myo-reps, seated chest press drop set, overhead triceps, "
         "rope pressdowns.", None, None, None,
         "Completion not confirmed in the chat export.", None),
        (_d(11, 8), "pull", "done",
         "High-volume pull, 24 working sets",
         "Neutral pulldown 4 sets (70 kg first, then 80 kg x3) plus 2 "
         "warm-ups; supinated pulldown 3 sets at 80 kg plus a 65 kg drop; "
         "chest-supported T-bar row 3 sets at 40 kg with a final 30/20 kg "
         "double drop; reverse cable fly 5 x 15; EZ-bar curl + seated "
         "alternating hammer curl superset, 3 rounds; incline DB curls "
         "3 x 8-10 slow with a stretched pause. 24 working sets.",
         50, None, None, "manual"),
        (_d(11, 10), "ride", "done", "Zone 2 indoor ride",
         "Indoor Zone 2 ride, main block up to 125 W, average HR 137 bpm, "
         "late HR drift near or above 150 bpm.", 58, None, None, "manual"),
        (_d(11, 11), "legs", "done", "Legs, 22 sets",
         "Legs completed (Smith squats, seated curls, hack or belt squat, "
         "Bulgarians, hip thrusts, extensions planned). Exercise-by-exercise "
         "results were not recorded.", None, None, None, "manual"),
        (_d(11, 12), "push", "done", "Upper-chest-first push",
         "Upper-chest-first push in about 45 minutes: incline press, seated "
         "shoulder press, chest press machine, lateral-raise myo-reps, "
         "overhead triceps, rope pressdowns. Added 3 sets of ab wheel.",
         45, None, None, "manual"),
        (_d(11, 13), "pull", "done", "Pull modelled on Nov 8",
         "Pull: pulldowns, chest-supported T-bar row, rear delt flies, "
         "EZ-curl / hammer / incline curl sequence. Reported a good pull; "
         "some residual chest soreness.", None, None,
         "Completion metrics not supplied.", "manual"),
        (_d(11, 14), "rest", "done", None,
         "Rest and walking instead of a planned double session: cumulative "
         "lifting fatigue and about 3 beers the evening before.",
         None, None, None, "manual"),
        (_d(11, 15), "intervals", "done", "Cycling intervals 4 x 4 min",
         "Indoor intervals, 4 x 4 min at about 180 W (about 112% of FTP "
         "estimate), about 4 min recoveries at 80 W. Garmin: 42:17 total, "
         "125 W avg, 192 W max, 138 bpm avg HR, 168 bpm max. Four blocks "
         "looked consistent; HR rose across the intervals.",
         42, None, None, "screenshot"),
        (_d(11, 16), "legs", "planned",
         "Legs, 21 working sets: Smith squats 4, seated leg curls 4, "
         "hack or belt squat 4, Bulgarians 3, hip thrust 3, leg "
         "extensions 3.", None, None, None, None, None),
        (_d(11, 17), "push", "planned",
         "Push before travel", None, None, None, None, None),
        (_d(11, 18), "pull", "planned",
         "Pull before travel", None, None, None, None, None),
        (_d(11, 19), "rest", "planned",
         "Long flight to Argentina; no training", None, None, None, None,
         None),
    ]


# (date, exercise, weight, reps, sets, note). Only numbers that appear in
# the export; reps are left out where the export doesn't give them.
def lift_rows():
    d = _d(11, 8)
    return [
        (d, "Neutral-grip lat pulldown", 80, None, 3,
         "after a 70 kg first set; 4 working sets plus 2 warm-ups"),
        (d, "Supinated lat pulldown", 80, None, 3, "then a 65 kg drop set"),
        (d, "Chest-supported T-bar row", 40, None, 3,
         "final set double drop 30 kg then 20 kg"),
    ]


def checkin_rows():
    return []  # none recorded in the export


def event_rows():
    return [
        (_d(10, 12), _d(10, 12), "other",
         "Sharp lower-left back pain during a seated cable row; improved "
         "through October.", None),
        (_d(11, 19), _d(11, 19), "travel",
         "About 14-hour flight to Argentina.",
         "No training that day; walk and hydrate."),
        (_d(11, 20), _d(11, 22), "travel",
         "Vacation in Argentina, flexible recovery.",
         "Next gym session likely 2026-11-23 or later."),
    ]


def memory_rows():
    added = TODAY.isoformat()
    return [
        (added, "Keep Bulgarian split squats in leg plans; discuss before removing."),
        (added, "Prefers 5-7 exercises and 20-24 working sets in 45-55 minutes; four sets on main lifts, 3-4 on accessories."),
        (added, "Likes a few purposeful intensity techniques per session (drop, myo-reps, rest-pause, supersets) but progressive overload stays the base."),
        (added, "Rolling Push / Pull / Legs: next session follows the last completed one, not the weekday. Push alternates chest-first and shoulder-first."),
        (added, "Wants routines as tables: exercise, sets x reps, rest, technique, plus a realistic time estimate."),
        (added, "Back: avoid unsupported rows and heavy hinging since 2026-10-12; chest-supported T-bar is fine. Ask if a row is supported."),
        (added, "Favourite biceps sequence: standing EZ-bar curl + seated alternating hammer curl superset, then slow incline DB curls."),
        (added, "Often trains fasted about 45 minutes after waking; a 20-30 g carb snack beforehand is worth testing."),
        (added, "Does not want volume lowered just to be cautious; adjust for real fatigue, travel and equipment."),
        (added, "Garmin ramp-test FTP estimate 161 W on 2026-10-28 (was about 134). Easy rides at 110-125 W; 125 W is about 78% of FTP and may sit at the top of easy."),
        (added, "Easy swim is relaxed 1.5-1.8 km in about 45 minutes."),
        (added, "Do not stack extra Zone 2 or intervals on top of fatigue; reschedule quality intervals instead."),
    ]


def message_rows():
    return []

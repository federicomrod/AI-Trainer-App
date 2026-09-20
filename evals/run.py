"""
run.py — run the frozen scenarios in scenarios.py.

Each scenario gets its own throwaway database in a temp directory, so
this can never touch the real one. Real model calls, so it costs money
and takes a few seconds per scenario -- run it when a prompt or the
path between a message and the database changes.

    server/.venv/bin/python evals/run.py [name-fragment ...]
"""

import os
import sys
import tempfile
from datetime import date, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "server"))

import scenarios as scenarios_module  # noqa: E402  (after sys.path)


def _prepare(scenario, db_path, today):
    """Build the scenario's database and return an open connection."""
    os.environ["HYBRID_COACH_DB_PATH"] = str(db_path)
    # Imported here, after the env var is set: db.py reads it at import.
    import importlib
    import db as db_module
    importlib.reload(db_module)
    conn = db_module.get_connection()
    db_module.init_db(conn)

    if scenario.profile:
        import onboarding
        onboarding.save_profile(conn, scenario.profile)

    for days_ago, session_type, status, summary in scenario.sessions:
        day = (today - timedelta(days=days_ago)).isoformat()
        conn.execute(
            "INSERT INTO sessions (date, type, status, actual_summary, source) "
            "VALUES (?, ?, ?, ?, 'manual')",
            (day, session_type, status, summary),
        )
    for role, content in scenario.messages:
        conn.execute(
            "INSERT INTO messages (role, content) VALUES (?, ?)", (role, content)
        )
    conn.commit()
    return conn


def run(scenario, today):
    with tempfile.TemporaryDirectory() as tmp:
        conn = _prepare(scenario, Path(tmp) / "eval.db", today)
        import importlib
        import coach
        importlib.reload(coach)
        result = coach.run_turn(conn, scenario.message)

        if result.error:
            return [(name, f"the turn failed: {result.error} "
                           f"({result.error_detail})")
                    for name in scenario.checks] or [
                ("the turn runs", f"{result.error}: {result.error_detail}")]

        failures = []
        for name, check in scenario.checks.items():
            problem = check(result, conn, today)
            if problem:
                failures.append((name, problem))
        return failures


def main(argv):
    wanted = argv[1:]
    today = date.today()
    chosen = [
        s for s in scenarios_module.SCENARIOS
        if not wanted or any(w in s.name for w in wanted)
    ]
    if not chosen:
        print(f"No scenario matches {wanted}")
        return 1

    failed = 0
    for scenario in chosen:
        print(f"\n=== {scenario.name}")
        print(f"    {scenario.about}")
        print(f'    message: "{scenario.message}"')
        failures = run(scenario, today)
        for name in scenario.checks:
            problem = dict(failures).get(name)
            print(f"    {'FAIL' if problem else 'ok  '}  {name}"
                  + (f"\n          -> {problem}" if problem else ""))
        failed += bool(failures)

    print(f"\n{len(chosen) - failed}/{len(chosen)} scenarios passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

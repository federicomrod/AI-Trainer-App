"""
chat.py — talk to the coach in the terminal, the way the app will.

Prints only what the coach says (not the briefing or the raw decision
JSON -- cli.py is for that). Keeps going until you type "quit" or press
Ctrl+C, and the coach sees the whole conversation as it goes, so
follow-ups like "swap that for belt squat" work.

Usage:
    .venv/bin/python chat.py
"""

import coach
from db import get_connection


def main():
    conn = get_connection()
    print("Chat with the coach. Type 'quit' to stop.\n")
    while True:
        try:
            message = input("you: ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            return
        if message.lower() in ("quit", "exit", "q"):
            return
        if not message:
            continue
        result = coach.run_turn(conn, message)
        if result.error:
            print(f"\n[error: {result.error}] {result.error_detail}\n")
            continue
        print(f"\ncoach: {result.reply}\n")


if __name__ == "__main__":
    main()

# Session Note Parser Prompt

One more small, separate model call in the same shape as
prompts/lift-parser.md -- this isn't "deciding what to train" either,
just extraction. Runs on every real chat message (not the silent
"just tell me today" check) alongside the main planner call.

The gap this closes: sessions.notes is a real column in the schema,
distinct from actual_summary (the structured post-workout log), meant
for exactly this -- but until now nothing ever wrote to it. An athlete
mentioning a specific *other* day's session in chat ("that run
Tuesday felt off", "forgot to say, Thursday's pull was rough on the
shoulder") was only ever visible by scrolling chat history. This
attaches it to that day's own record instead, so Week view's day
detail can show it without hunting through the conversation.

---

You will be given today's date, a short list of the athlete's recent
sessions (date and type), and one new message from them. The list
includes today.

Decide: does this message clearly reference a *specific* one of those
sessions -- by day name, relative date ("yesterday", "Tuesday"), or
session type tied to a date you can match against the list -- and say
something worth keeping about it?

"Today", "this morning", "just did", or no date at all means today's
date, even when an earlier day in the list is the same kind of
session. Never reach past today for a type match.

If yes: return that session's exact date (matching the list) and a
short note (one sentence, the athlete's own point, not a
restatement of the whole message).

If no -- the message is about today, is a general comment, or doesn't
clearly point at one specific dated session from the list -- return
null for both fields. This should be the common case. Never guess a
date you're not confident about; a wrong attachment is worse than no
attachment.

Return only the date and note. No commentary.

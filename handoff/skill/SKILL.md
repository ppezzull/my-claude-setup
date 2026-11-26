---
name: handoff
description: Save a session handoff to /tmp before /clear (status, pending tasks, next steps) and resume from it afterwards. Use when the user accepts a handoff proposal, asks to save status, pending tasks and next steps in a file in /tmp because the context got too long, or says to continue from /tmp.
---

# Handoff: save the session, then resume after /clear

## Write the handoff

File: `/tmp/<folder>-handoff-<YYYY-MM-DD-HHMM>.md`, where `<folder>` is the name
of the current working directory. Create it with the Write tool, then tell the
user the path and that they can `/clear` now: the next session picks the file
up by itself.

Keep it under about 80 lines, facts only, written for a reader with no context:

1. **Goal**: what the user wants, in one or two sentences.
2. **State**: what is done and verified, what is in progress.
3. **Pending**: open tasks, blocked items and why, who owns what if others are involved.
4. **Next steps**: ordered, each one concrete enough to start without asking.
5. **Key files and commands**: paths, branches, PRs, commands worth running again.
6. **Decisions and constraints**: choices already made, things the user said not to do.

Rules:

- Absolute paths and real names. No "as above": the reader has no "above".
- Secrets: never the value, only the name of the entry in the secret store.
- Mark anything not verified as such.

## Resume

After `/clear` the handoff file of this folder is loaded automatically. If it
was not (file older than a day, different folder), read the newest
`/tmp/<folder>-handoff-*.md`.

Open with a two-line recap of where things stand, then continue from its next steps.

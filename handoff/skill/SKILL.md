---
name: handoff
description: Save a session handoff to /tmp before /clear (status, pending tasks, next steps) and resume from it afterwards. Use when the user accepts a handoff proposal, asks to save status, pending tasks and next steps in a file in /tmp because the context got too long, or says to continue from /tmp or to save the current state.
---

# Handoff: save the session, start over from the file

## Write the handoff

File: `/tmp/<folder>-handoff-<YYYY-MM-DD-HHMM>.md`, where `<folder>` is the name
of the current working directory. Create it with the Write tool.

Writing that file starts the handoff by itself: when your reply ends, the
session runs `/clear` and sends `continue from <file>`. The next session loads
the file and goes on from its next steps. So end your reply with one line:
handoff saved in `<path>`, the session is starting over from it.

Inside tmux only. Outside tmux (or if the session does not start over by
itself) the user runs `/clear` and writes `continue from <path>`. If it did not
start over and the user wants it now, write the file again: that starts it.

To save the state **without** starting over, write
`/tmp/<folder>-status-<YYYY-MM-DD-HHMM>.md` instead and say so.

Keep the file under about 80 lines, facts only, written for a reader with no
context:

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

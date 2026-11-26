#!/usr/bin/env python3
"""handoff.py — propone un handoff quando il transcript di una sessione cresce.

Il flusso, a proposta (mai in automatico):
  transcript >= HANDOFF_MB (15)  ->  a fine risposta Claude PROpone il handoff
  l'utente dice si'              ->  Claude scrive /tmp/<cartella>-handoff-<data>.md (skill `handoff`)
  l'utente fa /clear             ->  la sessione nuova riparte da quel file

Hook:
  --hook prompt   UserPromptSubmit: una proposta ogni HANDOFF_STEP_MB (5) MB
  --hook start    SessionStart (matcher clear): inietta l'ultimo file, se recente
Mai un errore su stderr: un hook rotto non deve disturbare la sessione.
"""
import glob
import json
import os
import sys
import time

THRESHOLD_MB = float(os.environ.get("HANDOFF_MB", "15"))
STEP_MB = float(os.environ.get("HANDOFF_STEP_MB", "5"))
TTL_HOURS = float(os.environ.get("HANDOFF_TTL_HOURS", "24"))
STATE_DIR = "/tmp/claude-handoff-state"


def project(cwd):
    return os.path.basename(os.path.realpath(cwd)) or "root"


def latest_handoff(cwd):
    """Il file di handoff piu' recente di questa cartella, se piu' giovane di TTL_HOURS."""
    files = glob.glob(os.path.join("/tmp", project(cwd) + "-handoff-*.md"))
    files = [f for f in files if time.time() - os.path.getmtime(f) < TTL_HOURS * 3600]
    return max(files, key=os.path.getmtime) if files else None


def emit(event, context):
    print(json.dumps({"hookSpecificOutput": {"hookEventName": event, "additionalContext": context}}))


def on_prompt(data):
    transcript = data.get("transcript_path")
    prompt = data.get("prompt")
    if not transcript or not os.path.exists(transcript) or not isinstance(prompt, str):
        return
    if prompt.startswith("/"):
        return
    mb = os.path.getsize(transcript) / 1e6
    if mb < THRESHOLD_MB:
        return
    step = int((mb - THRESHOLD_MB) // STEP_MB)  # 0 alla soglia, 1 a +5 MB, ...
    state = os.path.join(STATE_DIR, str(data.get("session_id") or "unknown"))
    try:
        already = os.path.exists(state) and open(state).read().strip() == str(step)
        if not already:
            os.makedirs(STATE_DIR, exist_ok=True)
            open(state, "w").write(str(step))
    except OSError:
        return
    if already:
        return
    emit("UserPromptSubmit",
         f"[handoff] This session's transcript is {mb:.1f} MB (handoff threshold {THRESHOLD_MB:g} MB). "
         "PROPOSE a handoff, do not do it yet: end your reply with ONE line asking whether to save status, "
         "pending tasks and next steps to /tmp, so the user can /clear and resume from that file. "
         "Only if the user says yes: use the `handoff` skill to write the file and tell them it is ready for /clear.")


def on_start(data):
    path = latest_handoff(data.get("cwd") or os.getcwd())
    if not path:
        return
    with open(path, errors="replace") as f:
        body = f.read(24000)
    emit("SessionStart",
         "[handoff] The user ran /clear to resume from a handoff file saved by the previous session in this "
         "directory. When the user writes, open with a two-line recap of where things stand and continue "
         f"from its next steps. File: {path}\n\n{body}")


def main():
    try:
        event = sys.argv[sys.argv.index("--hook") + 1]
        data = json.load(sys.stdin)
    except (ValueError, OSError):
        return
    if event == "prompt":
        on_prompt(data)
    elif event == "start":
        on_start(data)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass

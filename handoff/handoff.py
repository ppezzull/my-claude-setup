#!/usr/bin/env python3
"""handoff.py — propone un handoff quando il transcript di una sessione cresce.

Il flusso, a proposta (mai senza il si dell'utente):
  transcript >= HANDOFF_MB (15)  ->  a fine risposta Claude PROpone il handoff
  l'utente dice si'              ->  Claude scrive /tmp/<cartella>-handoff-<data>.md (skill `handoff`)
  fine del turno                 ->  la sessione si azzera da sola (/clear) e riparte dal file

Solo dentro tmux: il clear e il "continue from <file>" sono tasti inviati al
pane della sessione. Fuori da tmux il file resta salvato e tocca farlo a mano.

Hook:
  --hook prompt   UserPromptSubmit: una proposta ogni HANDOFF_STEP_MB (5) MB
  --hook stop     Stop: se in questo turno e' stato scritto un handoff, lancia --drive
  --hook start    SessionStart (matcher clear): inietta l'ultimo file, se recente
Mai un errore su stderr: un hook rotto non deve disturbare la sessione.
"""
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import time

THRESHOLD_MB = float(os.environ.get("HANDOFF_MB", "15"))
STEP_MB = float(os.environ.get("HANDOFF_STEP_MB", "5"))
TTL_HOURS = float(os.environ.get("HANDOFF_TTL_HOURS", "24"))
STATE_DIR = "/tmp/claude-handoff-state"
IS_CLAUDE = re.compile(r"(^|/)claude( |$)|node\s+\S*/claude$")


def project(cwd):
    return os.path.basename(os.path.realpath(cwd)) or "root"


def state_path(session_id):
    return os.path.join(STATE_DIR, str(session_id or "unknown") + ".json")


def read_state(session_id):
    try:
        return json.load(open(state_path(session_id)))
    except (OSError, ValueError):
        return {}


def write_state(session_id, state):
    os.makedirs(STATE_DIR, exist_ok=True)
    with open(state_path(session_id), "w") as f:
        json.dump(state, f)


def latest_handoff(cwd):
    """Il file di handoff piu' recente di questa cartella, se piu' giovane di TTL_HOURS."""
    files = glob.glob(os.path.join("/tmp", project(cwd) + "-handoff-*.md"))
    files = [f for f in files if time.time() - os.path.getmtime(f) < TTL_HOURS * 3600]
    return max(files, key=os.path.getmtime) if files else None


def emit(event, context=None, message=None):
    out = {}
    if context:
        out["hookSpecificOutput"] = {"hookEventName": event, "additionalContext": context}
    if message:
        out["systemMessage"] = message
    if out:
        print(json.dumps(out))


def find_tui():
    """(pid di claude, id e pid del suo pane tmux) per il processo che ha lanciato questo hook."""
    pid, claude, parent = os.getpid(), None, None
    for _ in range(10):
        out = subprocess.run(["ps", "-o", "ppid=,command=", "-p", str(pid)],
                             capture_output=True, text=True).stdout.strip()
        m = re.match(r"(\d+)\s+(.*)", out, re.S)
        if not m:
            break
        parent, cmd = int(m.group(1)), m.group(2)
        if IS_CLAUDE.search(cmd) and not re.search(r"mcp|daemon|helper|bg-|attach|npm", cmd):
            claude = pid
            break
        if parent <= 1:
            break
        pid = parent
    if claude is None or not shutil.which("tmux"):
        return None, "", 0
    panes = subprocess.run(["tmux", "list-panes", "-a", "-F", "#{pane_id} #{pane_pid}"],
                           capture_output=True, text=True).stdout
    for pane_id, pane_pid in (line.split() for line in panes.splitlines() if len(line.split()) == 2):
        if int(pane_pid) in (claude, parent):
            return claude, pane_id, int(pane_pid)
    return claude, "", 0


def drive(pane, pane_pid, path, transcript):
    """Attende la fine vera del turno, poi /clear e "continue from <file>" nel pane."""
    time.sleep(3)
    last, stable = None, 0
    for _ in range(90):  # fino a 3 minuti; poi la sessione e' ancora attiva e non la interrompo
        try:
            size = os.path.getsize(transcript)
        except OSError:
            size = -1
        stable = stable + 1 if size == last else 0
        last = size
        if stable >= 2:  # transcript fermo da 4 secondi
            break
        time.sleep(2)
    else:
        return
    current = subprocess.run(["tmux", "display-message", "-p", "-t", pane, "#{pane_pid}"],
                             capture_output=True, text=True).stdout.strip()
    if current != str(pane_pid):
        return  # il pane non e' piu' quella sessione
    for wait, text in ((0, "/clear"), (8, f"continue from {path}")):
        time.sleep(wait)
        subprocess.run(["tmux", "send-keys", "-t", pane, "-l", text], capture_output=True)
        time.sleep(1)
        subprocess.run(["tmux", "send-keys", "-t", pane, "Enter"], capture_output=True)


def on_prompt(data):
    transcript, session_id = data.get("transcript_path"), data.get("session_id")
    prompt = data.get("prompt")
    if not transcript or not os.path.exists(transcript) or not isinstance(prompt, str):
        return
    mb = os.path.getsize(transcript) / 1e6
    state = read_state(session_id)
    state["prompt_at"] = time.time()
    step = int((mb - THRESHOLD_MB) // STEP_MB)  # 0 alla soglia, 1 a +5 MB, ...
    try:
        write_state(session_id, state)
    except OSError:
        return
    # Il contesto torna a OGNI prompt sopra la soglia: se il modello salta la
    # richiesta al primo giro (visto con glm-5.3-flash), la fa al successivo.
    if mb >= THRESHOLD_MB and not prompt.startswith("/"):
        emit("UserPromptSubmit",
             f"[handoff] This session's transcript is {mb:.1f} MB (handoff threshold {THRESHOLD_MB:g} MB), "
             f"handoff step {step}. If you have not asked the user about a handoff at this step yet, end your "
             "reply with ONE line asking whether to save status, pending tasks and next steps to /tmp, so the "
             "session can start over from that file. If you already asked at this step and the answer was not "
             "yes, do not ask again. Only if the user says yes: use the `handoff` skill to write the file.")


def on_stop(data):
    session_id = data.get("session_id")
    if data.get("agent_id") or data.get("team_name"):
        return  # un subagente o un teammate, non la sessione
    state = read_state(session_id)
    path = latest_handoff(data.get("cwd") or os.getcwd())
    if not path or not state.get("prompt_at") or os.path.getmtime(path) <= state["prompt_at"]:
        return  # nessun handoff scritto in questo turno
    state["prompt_at"] = 0  # un solo clear per handoff
    try:
        write_state(session_id, state)
    except OSError:
        pass
    _, pane, pane_pid = find_tui()
    if not pane or not data.get("transcript_path"):
        emit("Stop", message=f"Handoff salvato in {path}: fai /clear e poi scrivi \"continue from {path}\".")
        return
    subprocess.Popen([sys.executable, os.path.realpath(__file__), "--drive", pane, str(pane_pid),
                      path, data["transcript_path"]],
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True)


def on_start(data):
    path = latest_handoff(data.get("cwd") or os.getcwd())
    if not path:
        return
    with open(path, errors="replace") as f:
        body = f.read(24000)
    emit("SessionStart",
         "[handoff] This session started over (/clear) from a handoff file saved by the previous session in "
         "this directory. When the user writes, open with a two-line recap of where things stand and continue "
         f"from its next steps. File: {path}\n\n{body}")


def main():
    try:
        if len(sys.argv) > 1 and sys.argv[1] == "--drive":
            drive(*sys.argv[2:6])
            return
        event = sys.argv[sys.argv.index("--hook") + 1]
        data = json.load(sys.stdin)
    except (ValueError, OSError):
        return
    if event == "prompt":
        on_prompt(data)
    elif event == "stop":
        on_stop(data)
    elif event == "start":
        on_start(data)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass

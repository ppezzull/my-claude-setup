#!/usr/bin/env python3
"""quota-alert.py — avvisa sul bus quando una finestra quota GLM supera la soglia.

Cron */15 (la chiamata e' all'endpoint /api/monitor/usage/quota/limit, non costa
crediti). Token preso da ANTHROPIC_AUTH_TOKEN o da ~/.claude/settings.json e
mai stampato. Un avviso per scalino (80/90/100%) per finestra: lo stato sta in
~/.inter-session/quota-alert.state e si azzera quando cambia nextResetTime.

Il mittente e' un seat vivo (serve il suo .session per parlare col forwarder):
il job maintenance se c'e', altrimenti il primo seat sano della macchina.

  quota-alert.py              # uso da cron: silenzioso se sotto soglia
  quota-alert.py --dry-run    # stampa cosa farebbe, senza inviare
  quota-alert.py --force      # invia comunque (test di consegna)
"""
import glob
import json
import os
import socket
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

THRESHOLDS = (80, 90, 100)
TARGET = os.environ.get("QUOTA_ALERT_TARGET", "craftlead")
MAINTENANCE_JOB = "f685d8d7"  # seat "maintenance" (vedi BG_SEATS in watchdog.sh)
STATE = Path.home() / ".inter-session" / "quota-alert.state"
BIN = sorted(glob.glob(str(Path.home() / ".claude/plugins/cache/inter-session/*/*/skills/inter-session/bin")))[-1]
LABELS = {"TOKENS_LIMIT": "finestra 5h", "TIME_LIMIT": "mensile MCP"}


def load_settings():
    tok, base = os.environ.get("ANTHROPIC_AUTH_TOKEN"), os.environ.get("ANTHROPIC_BASE_URL")
    if not tok:
        env = json.loads((Path.home() / ".claude/settings.json").read_text())["env"]
        tok, base = env.get("ANTHROPIC_AUTH_TOKEN"), env.get("ANTHROPIC_BASE_URL")
    return tok, base


def query(tok, base):
    root = "/".join(base.split("/")[:3])  # https://api.z.ai
    req = urllib.request.Request(root + "/api/monitor/usage/quota/limit",
                                 headers={"Authorization": tok, "Accept-Language": "en-US,en",
                                          "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.load(r)["data"]["limits"]


def sender_pid():
    out = subprocess.run(["ps", "-eo", "pid=,command="], capture_output=True, text=True).stdout
    for line in out.splitlines():
        if "--bg-pty-host " in line and f"/pty/{MAINTENANCE_JOB}.sock" in line:
            return int(line.split()[0])
    for f in sorted(glob.glob(str(Path.home() / ".claude/data/inter-session/clients/*.session"))):
        try:
            os.kill(json.loads(Path(f).read_text())["listener_pid"], 0)
            return int(Path(f).stem)
        except (OSError, KeyError, ValueError):
            continue
    return None


def send(text):
    pid = sender_pid()
    if pid is None:
        raise SystemExit("nessun seat vivo: impossibile inviare")
    env = dict(os.environ, INTER_SESSION_PPID_OVERRIDE=str(pid))
    r = subprocess.run([sys.executable, os.path.join(BIN, "send.py"), "--to", TARGET, "--text", text],
                       env=env, capture_output=True, text=True)
    if r.returncode or r.stderr.strip():
        raise SystemExit(f"send fallito: {r.stderr.strip()}")


def main():
    force, dry = "--force" in sys.argv, "--dry-run" in sys.argv
    tok, base = load_settings()
    limits = query(tok, base)
    now = time.time()
    state = json.loads(STATE.read_text()) if STATE.exists() else {}
    lines, new_state = [], {}
    for item in limits:
        label = LABELS.get(item["type"], item["type"])
        reset = item.get("nextResetTime", 0) // 1000
        sent = state.get(label, {})
        if sent.get("reset") != reset:
            sent = {"reset": reset, "sent": []}
        due = [t for t in THRESHOLDS if item["percentage"] >= t and t not in sent["sent"]]
        new_state[label] = sent
        if due:
            sent["sent"] += due
            when = time.strftime("%H:%M", time.localtime(reset)) if reset > now else "n/d"
            lines.append(f"{label} al {item['percentage']}% (reset {when})")
    if not lines and not force:
        return
    if not lines:  # --force sotto soglia: report di prova con i valori correnti
        lines = [f"{LABELS.get(i['type'], i['type'])} al {i['percentage']}%" for i in limits]
    host = socket.gethostname().split(".")[0]
    test = "" if any(i["percentage"] >= THRESHOLDS[0] for i in limits) else " [test di consegna, nessuna azione]"
    text = "status: quota GLM " + host + ": " + "; ".join(lines) + "." + test + " [cron quota-alert]"
    if dry:
        print(text)
        return
    send(text)
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps(new_state))
    print(time.strftime("%F %T"), "->", TARGET, "|", text)


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # dal cron: il messaggio va nel log, mai il token
        print(time.strftime("%F %T"), "ERRORE", type(e).__name__, str(e)[:200])
        sys.exit(1)

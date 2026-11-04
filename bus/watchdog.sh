#!/usr/bin/env bash
# watchdog.sh — keep every Claude session on this machine seated on the bus.
#
# For each running `claude` main process:
#   - healthy monitor (clients/<ppid>.session exists, listener_pid alive) -> ok
#   - otherwise -> REARM: spawn a monitor keyed to that session via
#     INTER_SESSION_PPID_OVERRIDE, reusing the previous seat name if known
#
# Scheduling (health-check, not collaboration — cron is legitimate here):
#   macOS launchd / cron:   */5 * * * *  bash <plugin>/scripts/watchdog.sh
#   Linux systemd timer or: */5 * * * *  bash <plugin>/scripts/watchdog.sh
# Run it with `--loop <seconds>` to self-daemonize instead of scheduling.
set -uo pipefail

DATA="$HOME/.claude/data/inter-session"
BIN=$(ls -d "$HOME"/.claude/plugins/cache/inter-session/inter-session/*/skills/inter-session/bin 2>/dev/null | sort -V | tail -1)
LOGDIR="$HOME/.inter-session"
mkdir -p "$LOGDIR"
LOG="$LOGDIR/watchdog.log"
LOOP=""

say() { printf '%s %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG"; }

# --- find claude MAIN processes (exclude helpers/daemons) -------------------
claude_pids() {
  ps -eo pid=,command= | awk '
    /[c]laude/ {
      # keep bare "claude", "claude -r", "claude --resume ..." (main TUI processes)
      if ($0 ~ /\/claude( |$)/ || $0 ~ /^[ ]*[0-9]+ claude( |$)/) {
        if ($0 !~ /bg-|daemon|mcp|attach|helper|npm|node/) print $1
      }
    }'
}

# --- seat name from the tmux session hosting this claude pid ----------------
# Walks the ancestor chain until it hits a tmux pane_pid, then sanitizes the
# session name ("a-obsidian-ppezz-brain" -> "obsidian-ppezz-brain").
tmux_name() {  # $1 = claude pid -> echoes sanitized tmux session name, "" if not in tmux
  local p="$1" panes session
  panes=$(tmux list-panes -a -F '#{pane_pid} #{session_name}' 2>/dev/null) || return 0
  while [ -n "$p" ] && [ "$p" != "1" ]; do
    session=$(awk -v pp="$p" '$1==pp{print $2; exit}' <<<"$panes")
    if [ -n "$session" ]; then
      printf '%s' "${session#a-}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]//g'
      return 0
    fi
    p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ') || return 0
  done
  return 0
}

# --- seat name for a claude pid running in Warp (not tmux) -------------------
# Walks ancestors looking for Warp.app; names the seat "warp-<cwd-basename>".
warp_name() {  # $1 = claude pid -> echoes name, "" if not under Warp
  local p="$1" cwd
  while [ -n "$p" ] && [ "$p" != "1" ]; do
    if ps -p "$p" -o command= 2>/dev/null | grep -q "Warp.app"; then
      cwd=$(lsof -a -p "$1" -d cwd 2>/dev/null | awk 'END{print $NF}')
      if [ -n "$cwd" ] && [ "$cwd" != "/" ]; then
        basename "$cwd" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]//g'
      else
        echo "warp"
      fi
      return 0
    fi
    p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
  done
  return 0
}

# --- monitor health for a given claude pid ---------------------------------
monitor_alive() {  # $1 = claude pid -> echoes "name" if healthy, "" otherwise
  local f="$DATA/clients/$1.session"
  [ -f "$f" ] || return 1
  local lp name
  lp=$(python3 -c "import json;print(json.load(open('$f')).get('listener_pid',0))" 2>/dev/null)
  name=$(python3 -c "import json;print(json.load(open('$f')).get('name',''))" 2>/dev/null)
  [ -n "$lp" ] && [ "$lp" != "0" ] && kill -0 "$lp" 2>/dev/null || return 1
  echo "${name:-seat-$1}"
}

rearm() {  # $1 = claude pid, $2 = seat name
  nohup env INTER_SESSION_PPID_OVERRIDE="$1" INTER_SESSION_HOST="${INTERSESSION_HUB:-127.0.0.1}" \
    python3 "$BIN/client.py" --name "$2" --idle-shutdown-minutes 525600 \
    >> "$LOGDIR/rearm-$1.log" 2>&1 & disown
  say "REARM: claude pid $1 -> seat '$2' (monitor respawned)"
}

run_once() {
  local armed=0 ok=0
  for pid in $(claude_pids); do
    if name=$(monitor_alive "$pid"); then
      ok=$((ok+1))
    else
      # seat name: tmux session name, else Warp cwd, else previous, else seat-<pid>
      local f="$DATA/clients/$pid.session" name
      name=$(tmux_name "$pid")
      [ -n "$name" ] || name=$(warp_name "$pid")
      if [ -z "$name" ] && [ -f "$f" ]; then
        name=$(python3 -c "import json;print(json.load(open('$f')).get('name',''))" 2>/dev/null)
      fi
      [ -n "$name" ] || name="seat-$pid"
      rearm "$pid" "$name"
      armed=$((armed+1))
    fi
  done
  # reap monitors whose claude TUI no longer exists (session file is keyed by TUI pid)
  local reaped=0
  for f in "$DATA"/clients/*.session; do
    [ -f "$f" ] || continue
    local tpid cpid
    tpid=$(basename "$f" .session)
    cpid=$(python3 -c "import json;print(json.load(open('$f')).get('listener_pid',0))" 2>/dev/null)
    [ "$cpid" = "0" ] && continue
    if ! kill -0 "$tpid" 2>/dev/null; then
      if kill -0 "$cpid" 2>/dev/null && kill "$cpid" 2>/dev/null; then
        reaped=$((reaped+1))
        say "REAP: stale seat client $cpid (TUI $tpid gone)"
      fi
      rm -f "$f"
    fi
  done
  say "watchdog: $ok healthy, $armed re-armed, $reaped stale seat(s) reaped"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --loop) LOOP="${2:-30}"; shift 2 ;;
    *) shift ;;
  esac
done

if [ -n "$LOOP" ]; then
  say "watchdog: loop mode every ${LOOP}s"
  while true; do run_once; sleep "$LOOP"; done
else
  run_once
fi

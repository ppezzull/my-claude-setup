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

# cron parte con PATH minimale (/usr/bin:/bin): senza questo, tmux
# (/opt/homebrew/bin) e lsof (/usr/sbin) risultano irrangiungibili ->
# tmux_name() torna vuoto e i seat degradano a seat-<pid> anonimi,
# lane_keepalive() non vede il forwarder ("LANE: restart FAILED").
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

DATA="$HOME/.claude/data/inter-session"
BIN=$(ls -d "$HOME"/.claude/plugins/cache/inter-session/inter-session/*/skills/inter-session/bin 2>/dev/null | sort -V | tail -1)
LOGDIR="$HOME/.inter-session"
mkdir -p "$LOGDIR"
LOG="$LOGDIR/watchdog.log"
LOOP=""

# stdout only: il redirect del cron (>> watchdog.log) e' l'unico writer.
# Prima tee -a LOG + redirect = ogni riga scritta due volte.
say() { printf '%s %s\n' "$(date '+%F %T')" "$*"; }

# --- find claude MAIN processes (exclude helpers/daemons) -------------------
claude_pids() {
  ps -eo pid=,command= | awk '
    /[c]laude/ {
      # keep bare "claude", "claude -r", "claude --resume ..." (main TUI processes)
      if ($0 ~ /\/claude( |$)/ || $0 ~ /^[ ]*[0-9]+ claude( |$)/) {
        # un client tmux (`tmux new -A -s a-x ... claude -r`) resta vivo mentre
        # resta attaccato e porta "claude" nel comando: non e un TUI. Armava un
        # seat fantasma che si prendeva il nome base di quello vero (2026-11-27).
        # Nessun apostrofo in questo commento: siamo dentro awk con quote singole.
        if ($0 ~ /^[ ]*[0-9]+ tmux( |$)/) next
        if ($0 !~ /bg-|daemon|mcp|attach|helper|npm|node/) print $1
      }
    }'
  # I brain girano come "node <path>/claude" (nome processo senza "claude"):
  # l'awk sopra li salta e i loro seat non venivano MAI riarmati (2026-11-18).
  # Catturiamo SOLO quelli: figlio diretto dello shell di un pane a-*, exe
  # "node" e "claude" nel path del binario. Altri figli foreground (uv run,
  # caffeinate, MCP manuali...) NON sono agenti e non prendono seat.
  local panes=$(tmux list-panes -a -F '#{pane_pid} #{session_name}' 2>/dev/null | awk '$2 ~ /^a-/ {print $1}' | tr '\n' ' ')
  [ -n "$panes" ] || return 0
  ps -eo pid=,ppid=,command= | awk -v shells="$panes" '
    BEGIN { n = split(shells, arr, " "); for (i=1;i<=n;i++) sh[arr[i]]=1 }
    ($2 in sh) && ($3 == "node") && ($0 ~ /claude/) { print $1 }'
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

# --- seat manuali: job in background (`claude --bg-pty-host`) -----------------
# "<job-id>=<nome-seat>", separati da spazi. claude_pids() scarta i processi
# `bg-*`, quindi il client del job "maintenance" non veniva MAI riarmato: morto
# il monitor, il seat restava morto finche' qualcuno non lo rilanciava a mano
# (2026-11-24, 2 volte in un giorno). Il nome e' fisso qui perche' il session
# file viene cancellato all'uscita del client (niente "previous name") e il
# processo e' figlio del demone, non di un pane: tmux_name() e warp_name()
# danno vuoto e il seat degraderebbe a "seat-<pid>" anonimo.
# Il job id sta nel socket del command line (`.../pty/<job-id>.sock`): la riga
# resta valida anche se il job viene rilanciato (cambia il pid, non il job id).
BG_SEATS="f685d8d7=maintenance"
bg_seat_pids() {  # -> pid dei job elencati in BG_SEATS
  local seat
  for seat in $BG_SEATS; do
    ps -eo pid=,command= | awk -v sock="/pty/${seat%%=*}.sock" \
      '/--bg-pty-host / && index($0, sock) {print $1}'
  done
}
bg_seat_name() {  # $1 = pid -> nome configurato, "" se non e' un job elencato
  local cmd seat
  cmd=$(ps -p "$1" -o command= 2>/dev/null) || return 0
  case "$cmd" in *"--bg-pty-host "*) ;; *) return 0 ;; esac
  for seat in $BG_SEATS; do
    case "$cmd" in *"/pty/${seat%%=*}.sock"*) printf '%s' "${seat#*=}"; return 0 ;; esac
  done
  return 0
}

# --- monitor health for a given claude pid ---------------------------------
# --- un processo appena nato non e' un TUI ----------------------------------
# Un processo con "claude" nel comando che vive pochi istanti (uno statusline, un
# `claude --version`, un run headless) non e' una sessione: su nebula il watchdog
# ne armava uno nuovo a ogni giro come seat-<pid> anonimo, poi lo faceva sparire
# al giro dopo (2026-11-27). Una sessione vera dura: si arma solo quando il
# processo ha almeno MIN_AGE secondi di vita.
MIN_AGE=30
young() {  # $1 = pid -> esce 0 se il processo ha meno di MIN_AGE secondi
  local e d=0 h=0 m s
  e=$(ps -o etime= -p "$1" 2>/dev/null | tr -d ' ') || return 1
  case "$e" in *-*) d=${e%%-*}; e=${e#*-} ;; esac
  case "$e" in *:*:*) h=${e%%:*}; e=${e#*:} ;; esac
  m=${e%%:*}; s=${e##*:}; s=${s%%.*}  # macOS: "MM:SS.ss"
  # 10# perche' "09" con lo zero davanti verrebbe letto come ottale
  [ $((10#$d*86400 + 10#$h*3600 + 10#$m*60 + 10#$s)) -lt "$MIN_AGE" ]
}

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

# --- lane keepalive (2026-11-18) --------------------------------------------
# Regola di ppezz: seat vivo <=> agente aperto. Se la lane locale muore, tutti
# i monitor restano scollegati finche' qualcuno non la riavvia a mano (successo
# 2 volte in un giorno sul Mac). Attiva solo sulle spoke (file hub-endpoint):
# l'hub nebula ha il suo restarter e non va toccato.
lane_keepalive() {
  [ -f "$DATA/hub-endpoint" ] || return 0
  local hub; hub=$(cat "$DATA/hub-endpoint" 2>/dev/null)
  [ -n "$hub" ] || return 0
  local lp; lp=$(lsof -ti :9473 -sTCP:LISTEN | head -1)
  if [ -n "$lp" ]; then
    # listener presente: deve essere il NOSTRO forwarder. Uno squatter
    # (island hub rispawnato dal plugin) fa fallire l'identity check di
    # tutti i client = seat morti in silenzio (failure mode 2026-10-24).
    if ps -p "$lp" -o command= 2>/dev/null | grep -q "bin/server.py"; then
      # forwarder giusto. Il suo upstream e' PER-CONNESSIONE (thread-per-conn):
      # zero client locali = zero uplink e va bene cosi'. Stale solo se HA
      # client locali ma nessun socket verso l'hub (crafthost 2026-11-18:
      # i seat sembravano collegati e non lo erano).
      local localcli uplink
      localcli=$(netstat -an 2>/dev/null | grep ESTABLISHED | grep -c "127.0.0.1.9473")
      uplink=$(netstat -an 2>/dev/null | grep ESTABLISHED | grep -c "${hub}.9473")
      if [ "$uplink" -gt 0 ] || [ "$localcli" -eq 0 ]; then return 0; fi
      say "LANE: stale ($localcli client locali, 0 uplink verso $hub) — restart"
    else
      say "LANE: squatter su :9473 (pid $lp, non era il forwarder) — kill"
    fi
    kill "$lp" 2>/dev/null
    sleep 1
  fi
  nohup python3 "$DATA/bin/server.py" 127.0.0.1 9473 "$hub" 9473 \
    >> "$LOGDIR/forwarder.log" 2>&1 & disown
  sleep 1
  lp=$(lsof -ti :9473 -sTCP:LISTEN | head -1)
  if [ -n "$lp" ]; then
    echo "$lp" > "$DATA/server.9473.pid"
    printf '{"pid": %s, "host": "127.0.0.1", "port": 9473}\n' "$lp" \
      > "$DATA/server.9473.pid.meta"
    say "LANE: forwarder restarted -> hub $hub (pid $lp)"
  else
    say "LANE: restart FAILED (hub $hub)"
  fi
}

run_once() {
  local armed=0 ok=0 reaped=0
  lane_keepalive
  # PRIMA il reap dei seat orfani, POI il rearm (2026-11-26). Nell'ordine
  # inverso il client nuovo si presentava all'hub mentre quello della sessione
  # precedente era ancora registrato con lo stesso nome, e l'hub lo suffissava
  # (local-workspace-2, craftlead-2-2-2) a ogni riavvio di una sessione.
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
      rm -f "$f" "$DATA/clients/$tpid.lock"
    fi
  done
  # all'hub serve un istante per registrare la disconnessione e liberare il nome
  [ "$reaped" -eq 0 ] || sleep 1
  # lock di TUI morti: innocui (flock si rilascia alla morte) ma si accumulano da settimane
  for f in "$DATA"/clients/*.lock; do
    [ -f "$f" ] || continue
    local tpid=${f%.lock}; tpid=${tpid##*/}
    if ! kill -0 "$tpid" 2>/dev/null; then
      # niente .session = mai armato o gia' reaped: spazziamo via solo il lock
      [ -f "$DATA/clients/$tpid.session" ] || rm -f "$f"
    fi
  done
  for pid in $(claude_pids) $(bg_seat_pids); do
    # morto tra lo snapshot di ps e adesso: un processo effimero (per esempio un
    # `claude --version` lanciato da una statusline che si aggiorna proprio quando
    # il reap chiude un listener). Armare un pid morto crea un seat fantasma.
    kill -0 "$pid" 2>/dev/null || continue
    young "$pid" && continue
    if name=$(monitor_alive "$pid"); then
      ok=$((ok+1))
    else
      # seat name: tmux session name, else Warp cwd, else previous (never an
      # anonymous seat-*), else seat-<pid> as last resort
      local f="$DATA/clients/$pid.session" name prev
      name=$(bg_seat_name "$pid")
      [ -n "$name" ] || name=$(tmux_name "$pid")
      [ -n "$name" ] || name=$(warp_name "$pid")
      if [ -z "$name" ] && [ -f "$f" ]; then
        prev=$(python3 -c "import json;print(json.load(open('$f')).get('name',''))" 2>/dev/null)
        case "$prev" in seat-*|"") ;; *) name="$prev" ;; esac
      fi
      [ -n "$name" ] || name="seat-$pid"
      # un monitor orfano col lock in mano bloccherebbe il respawn
      # ("another monitor already running") e il seat resterebbe morto
      local orph
      for orph in $(lsof -t "$DATA/clients/$pid.lock" 2>/dev/null); do
        kill "$orph" 2>/dev/null && say "KILL: orphan lock holder $orph for TUI $pid"
      done
      rearm "$pid" "$name"
      armed=$((armed+1))
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

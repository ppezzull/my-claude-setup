#!/bin/bash
# agent-janitor.sh — stop vero degli agenti abbandonati.
# Regola (decisa da ppezz, 2026-11-13): sessione tmux a-* scollegata
# (nessun tab aperto) e senza attività da >12h → kill sessione
# + kill listener bus + rimozione clients/<ppid>.session (il seat sparisce dal bus).
# La riapertura (cd <cartella> && claude) ricrea la sessione e resurrect
# la ripristina col contesto (claude -c).
IDLE_LIMIT=$((12 * 3600))
NOW=$(date +%s)
SESSDIR="$HOME/.claude/data/inter-session/clients"
# Esonerate dal janitor: i brain persistenti vivono di messaggi bus e stanno
# idle per design giorni senza tab aperto (craftbrain/pezbrain, 2026-11-13).
EXEMPT="^a-obsidian-craftale-brain$|^a-obsidian-ppezz-brain$"

for line in $(tmux list-sessions -F "#{session_name}|#{session_attached}|#{session_activity}|#{pane_pid}" 2>/dev/null); do
  IFS='|' read -r name attached act pane <<< "$line"
  case "$name" in a-*) ;; *) continue ;; esac          # solo agenti, non "main"
  echo "$name" | grep -qE "$EXEMPT" && continue        # brain: mai stoppati
  [ "$attached" != "0" ] && continue                    # tab ancora aperto
  [ $((NOW - act)) -lt $IDLE_LIMIT ] && continue        # troppo recente
  # pane_pid = processo claude (la chiave del seat sul bus)
  sf="$SESSDIR/$pane.session"
  if [ -f "$sf" ]; then
    lp=$(python3 -c "import json; print(json.load(open('$sf')).get('listener_pid',''))" 2>/dev/null)
    [ -n "$lp" ] && kill "$lp" 2>/dev/null
    rm -f "$sf" "$SESSDIR/$pane.lock"
  fi
  tmux kill-session -t "$name" 2>/dev/null
  echo "$(date '+%F %T') janitor: stop $name (idle $(( (NOW - act) / 3600 ))h)"
done >> "$HOME/.inter-session/janitor.log" 2>&1

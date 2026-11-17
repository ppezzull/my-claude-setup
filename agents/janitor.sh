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

# Sweep MCP server orfani (2026-11-17): un "npm exec <mcp>" il cui padre e'
# uno zsh-pane (non un claude vivo) e' un server staccato che tiene il pane
# in ostaggio, finisce negli snapshot resurrect e si auto-perpetua ai reboot.
# Gli MCP legittimi hanno come padre il processo claude che li ha spawnati.
ps -eo pid=,ppid=,command= | grep -E "npm exec |npx " | grep -v grep | while read -r pid ppid cmd; do
  pcmd=$(ps -p "$ppid" -o command= 2>/dev/null)
  case "$pcmd" in
    *claude*) ;;                                # padre = claude vivo: MCP legittimo
    *zsh*|*bash*)
      kill "$pid" 2>/dev/null
      echo "$(date '+%F %T') janitor: sweep orphan MCP pid $pid ($cmd)"
      ;;
  esac
done >> "$HOME/.inter-session/janitor.log" 2>&1

# >>> agent persistenti (2026-10-29, v3 anti-nested-tmux 2026-11-18, v4 compattazione 2026-11-26) >>>
# Ogni "claude" gira in una sessione tmux dedicata alla cartella: chiudere il
# tab = detach (l'agente continua), al reboot il LaunchAgent + continuum
# ripristinano tutto e il pane riparte con "claude -c" (contesto intatto).
# v2: sessioni multiple sulla stessa cartella — se l'agente base ha già un
# terminale attaccato, il prossimo "claude" crea a-<dir>-1, -2, ... (o si
# riattacca a uno libero). "claude" da solo continua a riportarti al TUO agente.
# v3: "claude" lanciato DENTRO tmux (es. sessione main) non annida più tmux:
# crea/riattacca detached e switcha il client attivo (per tornare: prefix ) ).
# v4: se manca la base ma vivono a-<dir>-1, -2, ... vengono compattate verso il
# basso (il più vecchio torna a chiamarsi a-<dir>) e i loro seat sul bus seguono.
claude() {
  local bin=$(command -v claude)
  # in zsh command -v restituisce la FUNZIONE stessa ("claude", non un path):
  # fallback esplicito, altrimenti il pane parte con "claude: command not found"
  # nell'ambiente minimale di tmux (field-tested su crafthost 2026-11-17)
  [ -x "$bin" ] || bin="$HOME/.local/bin/claude"
  local base="a-$(basename "$PWD")" s="" n=1
  # v4: base mancante ma -1, -2, ... vivi → compatta verso il basso (-1 diventa
  # base, -2 diventa -1, ...): l'agente più vecchio porta sempre il nome pulito
  # e "claude" da solo torna da lui. Il seat sul bus nasce dal nome della sessione,
  # quindi i listener dei pidi rinominati si chiudono e un giro del watchdog li
  # riarma coi nomi nuovi.
  if ! tmux has-session -t "=$base" 2>/dev/null && tmux has-session -t "=$base-1" 2>/dev/null; then
    local bus="$HOME/.claude/data/inter-session" i=1 shifted=0 from to pid f lp
    while tmux has-session -t "=$base-$i" 2>/dev/null; do
      from="$base-$i"; to="$base-$((i-1))"; (( i == 1 )) && to="$base"
      # senza watchdog il seat resterebbe morto: meglio un nome vecchio ma vivo
      if [ -f "$bus/watchdog.sh" ]; then
        for pid in $(tmux list-panes -s -t "=$from" -F '#{pane_pid}' | while read -r pid; do echo "$pid"; pgrep -P "$pid"; done); do
          f="$bus/clients/$pid.session"
          [ -f "$f" ] || continue
          lp=$(sed -n 's/.*"listener_pid": \([0-9]*\).*/\1/p' "$f")
          [ -n "$lp" ] && [ "$lp" != "0" ] && kill "$lp" 2>/dev/null
          rm -f "$f" "$bus/clients/$pid.lock"
          shifted=1
        done
      fi
      tmux rename-session -t "=$from" "$to"
      i=$((i+1))
    done
    # all'hub serve un istante per liberare i nomi vecchi
    (( shifted )) && { sleep 1; bash "$bus/watchdog.sh" >/dev/null 2>&1; }
  fi
  # preferisci sempre riattaccarti a una sessione libera (nessun client attivo)
  if [ "$(tmux list-clients -t "=$base" 2>/dev/null | wc -l | tr -d ' ')" = "0" ]; then
    s="$base"
  else
    while :; do
      if ! tmux has-session -t "=$base-$n" 2>/dev/null; then s="$base-$n"; break; fi
      if [ "$(tmux list-clients -t "=$base-$n" 2>/dev/null | wc -l | tr -d ' ')" = "0" ]; then s="$base-$n"; break; fi
      n=$((n+1))
    done
  fi
  if [ -n "$TMUX" ]; then
    # già dentro tmux: crea/riattacca detached e switcha — niente tmux nel tmux
    tmux new -d -A -s "$s" -c "$PWD" "$bin $*" && tmux switch-client -t "$s"
  else
    tmux new -A -s "$s" -c "$PWD" "$bin $*"
  fi
}
# <<< agent persistenti <<<

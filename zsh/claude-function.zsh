# >>> agent persistenti (2026-10-29, v2 multi-session 2026-10-30) >>>
# Ogni "claude" gira in una sessione tmux dedicata alla cartella: chiudere il
# tab = detach (l'agente continua), al reboot il LaunchAgent + continuum
# ripristinano tutto e il pane riparte con "claude -c" (contesto intatto).
# v2: sessioni multiple sulla stessa cartella — se l'agente base ha già un
# terminale attaccato, il prossimo "claude" crea a-<dir>-2, -3, ... (o si
# riattacca a uno libero). "claude" da solo continua a riportarti al TUO agente.
claude() {
  local bin=$(command -v claude)
  local base="a-$(basename "$PWD")" s="" n=1
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
  tmux new -A -s "$s" -c "$PWD" "$bin $*"
}
# <<< agent persistenti <<<

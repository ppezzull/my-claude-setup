# >>> agent persistenti (2026-10-29, v3 anti-nested-tmux 2026-11-18) >>>
# Ogni "claude" gira in una sessione tmux dedicata alla cartella: chiudere il
# tab = detach (l'agente continua), al reboot il LaunchAgent + continuum
# ripristinano tutto e il pane riparte con "claude -c" (contesto intatto).
# v2: sessioni multiple sulla stessa cartella — se l'agente base ha già un
# terminale attaccato, il prossimo "claude" crea a-<dir>-1, -2, ... (o si
# riattacca a uno libero). "claude" da solo continua a riportarti al TUO agente.
# v3: "claude" lanciato DENTRO tmux (es. sessione main) non annida più tmux:
# crea/riattacca detached e switcha il client attivo (per tornare: prefix ) ).
claude() {
  local bin=$(command -v claude)
  # in zsh command -v restituisce la FUNZIONE stessa ("claude", non un path):
  # fallback esplicito, altrimenti il pane parte con "claude: command not found"
  # nell'ambiente minimale di tmux (field-tested su crafthost 2026-11-17)
  [ -x "$bin" ] || bin="$HOME/.local/bin/claude"
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
  if [ -n "$TMUX" ]; then
    # già dentro tmux: crea/riattacca detached e switcha — niente tmux nel tmux
    tmux new -d -A -s "$s" -c "$PWD" "$bin $*" && tmux switch-client -t "$s"
  else
    tmux new -A -s "$s" -c "$PWD" "$bin $*"
  fi
}
# <<< agent persistenti <<<

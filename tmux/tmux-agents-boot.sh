#!/bin/zsh
# tmux-agents-boot.sh — avvia il server tmux degli agenti al login.
# Il server che parte fa scattare continuum, che ripristina automaticamente
# le sessioni salvate (auto-save ogni 15 min, claude -c nei panes).
# PATH esplicito: launchd parte con un ambiente minimale — senza questo,
# ogni sessione eredita un PATH senza homebrew/.local e gli MCP (npx) muoiono.
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
if ! tmux ls >/dev/null 2>&1; then
  tmux new -d -s main
fi

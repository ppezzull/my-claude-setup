#!/usr/bin/env bash
# tmux-agents-boot.sh — avvia il server tmux degli agenti al login (macOS + Linux).
# Il server che parte fa scattare continuum, che ripristina automaticamente
# le sessioni salvate (auto-save ogni 15 min, claude -c nei panes).
# PATH esplicito e il piu' ampio possibile: launchd/systemd user partono con
# ambienti minimi — senza questo, le sessioni ereditano un PATH povero e
# gli MCP (npx) muoiono dentro tmux (field-tested 2026-10-29).
export PATH="$HOME/.local/bin:$HOME/.bun/bin:$HOME/.cargo/bin:$HOME/.foundry/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
if ! tmux ls >/dev/null 2>&1; then
  tmux new -d -s main
fi

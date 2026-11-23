#!/usr/bin/env bash
# tmux-agents-boot.sh — avvia il server tmux degli agenti al login (macOS + Linux).
# Il server che parte fa scattare continuum, che ripristina automaticamente
# le sessioni salvate (auto-save ogni 15 min, claude -c nei panes).
# PATH esplicito e il piu' ampio possibile: launchd/systemd user partono con
# ambienti minimi — senza questo, le sessioni ereditano un PATH povero e
# gli MCP (npx) muoiono dentro tmux (field-tested 2026-10-29).
export PATH="$HOME/.local/bin:$HOME/.bun/bin:$HOME/.cargo/bin:$HOME/.foundry/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# Attesa rete (max 30s, field-tested 2026-11-23): al boot la rete e' "mezza su"
# (TCP connette ma i dati non fluiscono) e npx -y degli MCP pianta claude su
# attesa infinita. Prima di resuscitare le sessioni, aspettiamo che il
# registry npm risponda davvero. Non blocca il login: 30s di grazia e si va.
NET_WAITED=0
while [ "$NET_WAITED" -lt 30 ]; do
  if curl -sf --max-time 3 https://registry.npmjs.org/ >/dev/null 2>&1; then
    break
  fi
  sleep 2
  NET_WAITED=$((NET_WAITED + 2))
done

if ! tmux ls >/dev/null 2>&1; then
  tmux new -d -s main
fi

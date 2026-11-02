#!/bin/bash
# install.sh — setup Claude Code completo (Mac). Idempotente: rilanciabile.
set -euo pipefail
cd "$(dirname "$0")"
say(){ echo "==> $*"; }

# ─── prerequisiti ───
command -v brew >/dev/null || { echo "brew mancante: https://brew.sh"; exit 1; }
command -v bun  >/dev/null || brew install bun
command -v tmux >/dev/null || brew install tmux

# ─── 1. tmux persistence ───
say "tmux config (My-Tmux-conf via symlink)"
[ -d ~/Desktop/Personal/My-Tmux-conf ] || git clone -q git@github.com:ppezzull/My-Tmux-conf.git ~/Desktop/Personal/My-Tmux-conf
ln -sf ~/Desktop/Personal/My-Tmux-conf/.tmux.conf ~/.tmux.conf
mkdir -p ~/.tmux/plugins
[ -d ~/.tmux/plugins/tpm ]            || git clone -q https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
[ -d ~/.tmux/plugins/tmux-resurrect ] || git clone -q https://github.com/tmux-plugins/tmux-resurrect ~/.tmux/plugins/tmux-resurrect
[ -d ~/.tmux/plugins/tmux-continuum ] || git clone -q https://github.com/tmux-plugins/tmux-continuum ~/.tmux/plugins/tmux-continuum

say "boot script + LaunchAgent"
mkdir -p ~/bin
cp tmux/tmux-agents-boot.sh ~/bin/ && chmod +x ~/bin/tmux-agents-boot.sh
cp tmux/com.ppezz.tmux-agents.plist ~/Library/LaunchAgents/
launchctl bootout gui/$(id -u)/com.ppezz.tmux-agents 2>/dev/null || true
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.ppezz.tmux-agents.plist
launchctl kickstart gui/$(id -u)/com.ppezz.tmux-agents

# ─── 2. funzione claude() ───
say "funzione claude() in ~/.zshrc"
if ! grep -q ">>> agent persistenti" ~/.zshrc 2>/dev/null; then
  { echo ""; cat zsh/claude-function.zsh; } >> ~/.zshrc
else
  echo "    già presente (blocco 'agent persistenti')"
fi

# ─── 3. HUD ───
say "HUD: wrapper (symlink) + fork renderer"
mkdir -p ~/.claude/scripts ~/.claude/plugins/cache/claude-hud/claude-hud
[ -d ~/Desktop/Personal/glm-claude-hud ] || git clone -q git@github.com:ppezzull/glm-claude-hud.git ~/Desktop/Personal/glm-claude-hud
ln -sf ~/Desktop/Personal/glm-claude-hud/glm-wrapper.ts ~/.claude/scripts/glm-wrapper.ts
[ -d ~/.claude/plugins/cache/claude-hud/claude-hud/0.1.0 ] || \
  git clone -q https://github.com/ppezzull/claude-hud ~/.claude/plugins/cache/claude-hud/claude-hud/0.1.0

say "statusLine in ~/.claude/settings.json (merge manuale se mancante)"
if ! grep -q '"statusLine"' ~/.claude/settings.json 2>/dev/null; then
  python3 - << 'EOF'
import json, os
p = os.path.expanduser('~/.claude/settings.json')
d = json.load(open(p))
d['statusLine'] = {"type": "command",
  "command": "/opt/homebrew/bin/bun \"$HOME/.claude/scripts/glm-wrapper.ts\""}
json.dump(d, open(p, 'w'), indent=2)
EOF
  echo "    aggiunta"
else
  echo "    già presente — verifica punti a ~/.claude/scripts/glm-wrapper.ts"
fi

# ─── 4. bus inter-session (facoltativo, richiede hub raggiungibile) ───
say "bus: watchdog cron (setup completo: /interserver setup spoke --hub <ip>)"
if ! crontab -l 2>/dev/null | grep -q watchdog.sh; then
  (crontab -l 2>/dev/null; echo '*/4 * * * * bash $HOME/.claude/data/inter-session/watchdog.sh >> $HOME/.inter-session/watchdog.log 2>&1') | crontab -
  echo "    cron aggiunto"
else
  echo "    cron già presente"
fi

say "fatto. Test: apri un NUOVO tab → cd <progetto> → claude"

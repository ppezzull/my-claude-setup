#!/usr/bin/env bash
# install.sh — setup Claude Code completo. macOS + Linux (WSL su Windows).
# Tier: --minimal | --medium (default) | --full. Idempotente: rilanciabile.
# Flavor: --anthropic (default, endpoint ufficiale) | --glm (piano GLM, wrapper quota).
#          Senza flag: auto-detect dal settings.json esistente.
set -euo pipefail
cd "$(dirname "$0")"
say(){ echo "==> $*"; }
die(){ echo "ERRORE: $*" >&2; exit 1; }

TIER="medium"; FLAVOR=""
for a in "$@"; do
  case "$a" in
    --minimal|--medium|--full) TIER="${a#--}" ;;
    --anthropic|--glm) FLAVOR="${a#--}" ;;
    -h|--help) sed -n '2,4p' "$0"; exit 0 ;;
    *) die "flag sconosciuto: $a (usi: --minimal --medium --full --anthropic --glm)" ;;
  esac
done
# auto-detect flavor: se il settings esistente punta a z.ai e' un setup GLM
if [ -z "$FLAVOR" ] && [ -f "$HOME/.claude/settings.json" ]; then
  if grep -q "api.z.ai" "$HOME/.claude/settings.json" 2>/dev/null; then
    FLAVOR="glm"; say "auto-detect: settings esistente punta a GLM -> flavor glm"
  fi
fi
[ -n "$FLAVOR" ] || FLAVOR="anthropic"
say "tier: $TIER · flavor: $FLAVOR"

# ─── OS detection ───
OS="unknown"; PKG=""
case "$(uname -s)" in
  Darwin) OS="macos" ;;
  Linux)  OS="linux" ;;
  MINGW*|MSYS*|CYGWIN*) OS="windows" ;;
esac
if [ "$OS" = "windows" ]; then
  cat << 'EOF'
Windows nativo: la persistenza agenti richiede tmux (POSIX).
Usa WSL2:  wsl --install -d Ubuntu   poi, dentro WSL, rilancia ./install.sh
( dentro WSL la cache Claude e' separata: installa anche claude con il
  metodo ufficiale, poi ./install.sh )
EOF
  exit 1
fi
command -v tmux >/dev/null || {
  say "tmux mancante — installo via package manager"
  if [ "$OS" = "macos" ]; then
    command -v brew >/dev/null || die "brew mancante: https://brew.sh"
    brew install tmux
  elif command -v apt-get >/dev/null; then sudo apt-get update && sudo apt-get install -y tmux git
  elif command -v dnf >/dev/null; then sudo dnf install -y tmux git
  elif command -v pacman >/dev/null; then sudo pacman -S --noconfirm tmux git
  else die "nessun package manager noto (apt/dnf/pacman) — installa tmux a mano e rilancia"
  fi
}

# ─── helper shell rc (zsh o bash) ───
RC="$HOME/.zshrc"; [ -f "$RC" ] || RC="$HOME/.bashrc"
BUN="$(command -v bun || true)"
[ -n "$BUN" ] || { say "bun mancante — installo"; curl -fsSL https://bun.sh/install | bash; BUN="$HOME/.bun/bin/bun"; }

# ─── 1. tmux persistence [minimo] ───
say "tmux config (My-Tmux-conf via symlink)"
[ -d "$HOME/Desktop/Personal/My-Tmux-conf" ] || git clone -q https://github.com/ppezzull/My-Tmux-conf.git "$HOME/Desktop/Personal/My-Tmux-conf"
ln -sf "$HOME/Desktop/Personal/My-Tmux-conf/.tmux.conf" "$HOME/.tmux.conf"
mkdir -p ~/.tmux/plugins
[ -d ~/.tmux/plugins/tpm ]            || git clone -q https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
[ -d ~/.tmux/plugins/tmux-resurrect ] || git clone -q https://github.com/tmux-plugins/tmux-resurrect ~/.tmux/plugins/tmux-resurrect
[ -d ~/.tmux/plugins/tmux-continuum ] || git clone -q https://github.com/tmux-plugins/tmux-continuum ~/.tmux/plugins/tmux-continuum

say "boot service"
mkdir -p ~/bin
cp tmux/tmux-agents-boot.sh ~/bin/ && chmod +x ~/bin/tmux-agents-boot.sh
if [ "$OS" = "macos" ]; then
  cp tmux/com.ppezz.tmux-agents.plist ~/Library/LaunchAgents/
  launchctl bootout "gui/$(id -u)/com.ppezz.tmux-agents" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/com.ppezz.tmux-agents.plist
  launchctl kickstart "gui/$(id -u)/com.ppezz.tmux-agents"
else
  mkdir -p ~/.config/systemd/user
  cp tmux/tmux-agents.service ~/.config/systemd/user/
  systemctl --user daemon-reload && systemctl --user enable --now tmux-agents.service
fi

say "funzione claude() in $RC"
if ! grep -q ">>> agent persistenti" "$RC" 2>/dev/null; then
  { echo ""; cat zsh/claude-function.zsh; } >> "$RC"
else
  echo "    già presente"
fi

say "janitor agenti abbandonati (stop vero dopo 12h da tab chiuso)"
mkdir -p ~/bin && cp agents/janitor.sh ~/bin/agent-janitor.sh && chmod +x ~/bin/agent-janitor.sh
if ! crontab -l 2>/dev/null | grep -q agent-janitor; then
  (crontab -l 2>/dev/null; echo '*/15 * * * * bash ~/bin/agent-janitor.sh') | crontab -
  echo "    cron aggiunto"
else
  echo "    cron già presente"
fi

# ─── 2. HUD [medio] ───
if [ "$TIER" != "minimal" ]; then
  say "HUD (flavor: $FLAVOR)"
  mkdir -p ~/.claude/plugins/cache/claude-hud/claude-hud
  [ -d ~/.claude/plugins/cache/claude-hud/claude-hud/0.1.0 ] || \
    git clone -q https://github.com/ppezzull/claude-hud ~/.claude/plugins/cache/claude-hud/claude-hud/0.1.0
  # il renderer va compilato se la clone arriva senza dist/
  HUD_RENDERER="$HOME/.claude/plugins/cache/claude-hud/claude-hud/0.1.0/dist/index.js"
  if [ ! -f "$HUD_RENDERER" ]; then
    say "build renderer claude-hud"
    (cd ~/.claude/plugins/cache/claude-hud/claude-hud/0.1.0 && "$BUN" install --silent && "$BUN" run build)
  fi

  if [ "$FLAVOR" = "glm" ]; then
    # wrapper GLM: quota del piano + contesto — solo per setup con endpoint GLM
    say "GLM: wrapper quota (symlink)"
    mkdir -p ~/.claude/scripts
    [ -d "$HOME/Desktop/Personal/glm-claude-hud" ] || git clone -q https://github.com/ppezzull/glm-claude-hud.git "$HOME/Desktop/Personal/glm-claude-hud"
    ln -sf "$HOME/Desktop/Personal/glm-claude-hud/glm-wrapper.ts" ~/.claude/scripts/glm-wrapper.ts
    HUD_CMD="$BUN \"\$HOME/.claude/scripts/glm-wrapper.ts\""
  else
    # anthropic: endpoint ufficiale, niente wrapper — renderer diretto
    say "anthropic: statusLine renderer diretto (niente wrapper GLM)"
    HUD_CMD="$BUN \"$HUD_RENDERER\""
  fi

  if [ -f ~/.claude/settings.json ]; then
    say "statusLine in ~/.claude/settings.json"
    if ! grep -q '"statusLine"' ~/.claude/settings.json 2>/dev/null; then
      HUD_CMD="$HUD_CMD" python3 - << 'EOF'
import json, os
p = os.path.expanduser('~/.claude/settings.json')
d = json.load(open(p))
d['statusLine'] = {"type": "command", "command": os.environ['HUD_CMD']}
json.dump(d, open(p, 'w'), indent=2)
EOF
      echo "    aggiunta"
    else
      echo "    già presente — verifica punti al flavor giusto (glm-wrapper.ts o dist/index.js)"
    fi
  else
    echo "    (~/.claude/settings.json assente: installa Claude Code prima, poi rilancia)"
  fi
fi

# ─── 3. bus inter-session [pieno] ───
if [ "$TIER" = "full" ]; then
  say "bus: watchdog + cron (setup spoke completo: /interserver setup spoke --hub <ip>)"
  # watchdog con seat name reale (sessione tmux / cwd Warp), vedi bus/README.md
  BUSDIR="$HOME/.claude/data/inter-session"
  mkdir -p "$BUSDIR"
  if [ ! -f "$BUSDIR/watchdog.sh" ]; then
    cp bus/watchdog.sh "$BUSDIR/watchdog.sh"
    echo "    watchdog installato"
  else
    echo "    watchdog già presente (aggiornalo a mano dal repo se diverge)"
  fi
  if ! crontab -l 2>/dev/null | grep -q watchdog.sh; then
    (crontab -l 2>/dev/null; echo '*/4 * * * * bash $HOME/.claude/data/inter-session/watchdog.sh >> $HOME/.inter-session/watchdog.log 2>&1') | crontab -
    echo "    cron aggiunto"
  else
    echo "    cron già presente"
  fi
  # auto-start plugin OFF: senza nome genererebbe seat-NNNNN anonimi;
  # la connessione automatica la garantisce il watchdog (max 4 min), col nome reale
  AUTOSTART=$(ls -d "$HOME"/.claude/plugins/cache/inter-session/inter-session/*/skills/inter-session/bin/auto_start.py 2>/dev/null | sort -V | tail -1)
  if [ -n "$AUTOSTART" ]; then
    python3 "$AUTOSTART" --off >/dev/null 2>&1 && echo "    plugin auto-start OFF (lazy)"
  fi
fi

say "fatto (tier: $TIER, OS: $OS). Test: apri un NUOVO tab → cd <progetto> → claude"

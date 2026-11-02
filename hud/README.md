# HUD — statusline GLM per Claude Code

Lo stack è composto da DUE repo che collaborano:

1. **[ppezzull/glm-claude-hud](https://github.com/ppezzull/glm-claude-hud)** — il *wrapper*
   (`glm-wrapper.ts`): sta tra Claude Code e claude-hud. Inietta la quota GLM
   (Z.AI), sintetizza `context_window` dal transcript (modelli proxied tipo
   glm-5.3 non la passano), aggiunge scala colori context a 5 livelli e il nome
   del seat inter-session nella riga dei counts.

2. **[ppezzull/claude-hud](https://github.com/ppezzull/claude-hud)** (fork, v0.1.0) —
   il *renderizzatore*. Il fork aggiunge il supporto `rate_limits`, ovvero la
   riga **Usage** (percentuale quota + reset). L'upstream NON lo ha: se il
   plugin si auto-aggiorna all'upstream, la riga Usage sparisce (successo
   davvero, 2026-10-29).

## Deploy sul Mac

```bash
# 1. wrapper via symlink: git pull = deploy automatico, mai più versione stale
git clone git@github.com:ppezzull/glm-claude-hud.git ~/Desktop/Personal/glm-claude-hud
mkdir -p ~/.claude/scripts
ln -s ~/Desktop/Personal/glm-claude-hud/glm-wrapper.ts ~/.claude/scripts/glm-wrapper.ts

# 2. fork del renderizzatore come 0.1.0 nel cache del plugin
#    (il wrapper sceglie sempre la versione più alta → il fork vince)
git clone https://github.com/ppezzull/claude-hud \
  ~/.claude/plugins/cache/claude-hud/claude-hud/0.1.0
```

E in `~/.claude/settings.json` (vedi `settings/settings.example.json`):

```json
"statusLine": {
  "type": "command",
  "command": "/opt/homebrew/bin/bun \"$HOME/.claude/scripts/glm-wrapper.ts\""
}
```

## Sintomi noti e cure

| Sintomo | Causa | Cura |
|---|---|---|
| Riga Usage sparita | plugin auto-updatato all'upstream (niente rate_limits) | ri-clonare il fork come 0.1.0 (sopra) |
| Context line vuota | wrapper vecchio senza sintesi transcript | il symlink risolve: `git pull` nel repo wrapper |
| Nome seat assente | bus non connesso o seat con nome automatico (`seat-<pid>`, nascosto di progettazione) | `/interserver connect <nome>` |
| Niente colori | TERM povero dentro tmux | `set -g default-terminal "screen-256color"` |
